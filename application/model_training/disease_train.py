import os
import copy
import random
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
import numpy as np
from sklearn.metrics import classification_report, f1_score
from tqdm import tqdm
import torchvision.models as models
import torchvision.transforms.functional as TF
import torch.nn.functional as F

# ---------------- USER CONFIG ----------------
DATA_DIR = "./training_data"
BATCH_SIZE = 32
EPOCHS = 500
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
PATIENCE = 100
TEACHER_NAMES = [
    "resnet50",
    "resnet101",
    "resnet152", 
    "efficientnet_b4",   # efficient conv scaling

]
STUDENT_NAME = "resnet18"  # student architecture
NUM_CLASSES = 2
ADAPTER_OUT_CH = 64         # adapter maps 7 -> 64 channels for models expecting 64
SEED_BASE = 42
# Distillation hyperparams
DISTILL_T = 2.0
DISTILL_ALPHA = 0.7  # weight on soft loss, (1-alpha) on hard CE
# ------------------------------------------------

class RandomAugmentation(object):
    def __init__(self, rotation_range=15, translation_range=5, p_flip=0.5):
        self.rotation_range = rotation_range
        self.translation_range = translation_range
        self.p_flip = p_flip

    def __call__(self, tensor):
        # tensor shape: (C, H, W)
        if random.random() < self.p_flip:
            tensor = torch.flip(tensor, dims=[2])
        angle = random.uniform(-self.rotation_range, self.rotation_range)
        tensor = TF.rotate(tensor, angle, interpolation=TF.InterpolationMode.BILINEAR)
        tx = random.uniform(-self.translation_range, self.translation_range)
        ty = random.uniform(-self.translation_range, self.translation_range)
        tensor = TF.affine(tensor, angle=0, translate=(tx, ty), scale=1.0, shear=0,
                           interpolation=TF.InterpolationMode.BILINEAR)
        return tensor

def adjust_brightness_multichannel(tensor, brightness_factor):
    return tensor * brightness_factor

def adjust_contrast_multichannel(tensor, contrast_factor):
    mean = tensor.mean(dim=(1, 2), keepdim=True)
    return (tensor - mean) * contrast_factor + mean

class StrongAugmentation(object):
    def __init__(self, rotation_range=15, translation_range=5,
                 brightness_range=(0.8, 1.2), contrast_range=(0.8, 1.2),
                 p_flip=0.5):
        self.rotation_range = rotation_range
        self.translation_range = translation_range
        self.brightness_range = brightness_range
        self.contrast_range = contrast_range
        self.p_flip = p_flip

    def __call__(self, tensor):
        if random.random() < self.p_flip:
            tensor = torch.flip(tensor, dims=[2])

        angle = random.uniform(-self.rotation_range, self.rotation_range)
        tensor = TF.rotate(tensor, angle, interpolation=TF.InterpolationMode.BILINEAR)
        tx = random.uniform(-self.translation_range, self.translation_range)
        ty = random.uniform(-self.translation_range, self.translation_range)
        tensor = TF.affine(tensor, angle=0, translate=(tx, ty), scale=1.0, shear=0,
                           interpolation=TF.InterpolationMode.BILINEAR)

        brightness_factor = random.uniform(*self.brightness_range)
        tensor = adjust_brightness_multichannel(tensor, brightness_factor)
        contrast_factor = random.uniform(*self.contrast_range)
        tensor = adjust_contrast_multichannel(tensor, contrast_factor)
        return tensor

class BotrytisDataset(Dataset):
    def __init__(self, data_dir, transform=None):
        self.data_dir = data_dir
        self.transform = transform
        self.images = []
        self.labels = []

        # Load global normalization stats
        self.global_mean = np.load("global_mean.npy")  # shape (7,)
        self.global_std = np.load("global_std.npy")    # shape (7,)

        # Preload all images + labels into memory
        for f in sorted(os.listdir(data_dir)):
            if f.endswith(".npy") and f.startswith("image_"):
                label_path = os.path.join(data_dir, f.replace("image_", "label_").replace(".npy", ".txt"))
                if os.path.exists(label_path):
                    image_path = os.path.join(data_dir, f)
                    image = np.load(image_path).astype(np.float32)  # shape (7,H,W)
                    label = int(open(label_path).read().strip())
                    self.images.append(torch.tensor(image))
                    self.labels.append(torch.tensor(label, dtype=torch.long))

    def __len__(self):
        return len(self.images)

    def __getitem__(self, idx):
        image = self.images[idx].clone()  # copy so augmentations don’t overwrite
        label = self.labels[idx]

        if self.transform is not None:
            image = self.transform(image)

        # Normalize channel-wise
        for c in range(image.shape[0]):
            image[c] = (image[c] - self.global_mean[c]) / (self.global_std[c] + 1e-8)

        return image, label

# ---------------- model builder helpers ----------------

class ChannelAdapterAndHead(nn.Module):
    """
    Universal wrapper: modifies first conv layer to accept 7 input channels directly,
    preserving pretrained weights otherwise. Also replaces classification head for NUM_CLASSES outputs.
    """
    def __init__(self, base_model, in_ch=7, num_classes=2):
        super().__init__()
        self.base = base_model
        self._adapt_first_conv(in_ch)
        self._replace_head(num_classes)

    def _adapt_first_conv(self, in_ch):
        m = self.base
        name = m.__class__.__name__.lower()

        def expand_conv(conv, in_ch):
            """Expand pretrained conv weight (3→7 channels) using mean replication strategy."""
            new_conv = nn.Conv2d(in_ch, conv.out_channels,
                                 kernel_size=conv.kernel_size,
                                 stride=conv.stride,
                                 padding=conv.padding,
                                 bias=(conv.bias is not None))
            if conv.weight.shape[1] == 3:
                # replicate averaged pretrained filters across new channels
                with torch.no_grad():
                    new_conv.weight[:, :3, :, :] = conv.weight
                    if in_ch > 3:
                        avg = conv.weight.mean(dim=1, keepdim=True)
                        new_conv.weight[:, 3:, :, :] = avg.repeat(1, in_ch - 3, 1, 1)
            else:
                # if custom pretrained conv already matches, just copy shape
                new_conv.weight[:, :conv.weight.shape[1], :, :] = conv.weight[:, :conv.weight.shape[1], :, :]
            return new_conv

        if "resnet" in name:
            m.conv1 = expand_conv(m.conv1, in_ch)

        elif "efficientnet" in name:
            m.features[0][0] = expand_conv(m.features[0][0], in_ch)

        else:
            # fallback: try to detect first Conv2d automatically
            for name, module in m.named_children():
                if isinstance(module, nn.Conv2d):
                    setattr(m, name, expand_conv(module, in_ch))
                    break

    def _replace_head(self, num_classes):
        m = self.base
        name = m.__class__.__name__.lower()

        def make_head(in_features):
            return nn.Sequential(
                nn.Linear(in_features, 1000),
                nn.BatchNorm1d(1000),
                nn.ReLU(),
                nn.Dropout(0.3),
                nn.Linear(1000, num_classes)
            )

        if "resnet" in name:
            in_features = m.fc.in_features
            m.fc = make_head(in_features)


        elif "efficientnet" in name:
            in_features = m.classifier[1].in_features
            m.classifier[1] = make_head(in_features)


        else:
            # fallback for unknown models
            for name, module in m.named_modules():
                if isinstance(module, nn.Linear) and module.out_features == 1000:
                    in_f = module.in_features
                    setattr(m, name, nn.Linear(in_f, num_classes))
                    break

    def forward(self, x):
        return self.base(x)


# ----------------------------
# ViT Wrapper for resizing
# ----------------------------
class ViTWrapper(nn.Module):
    def __init__(self, vit_model, target_size=(224, 224)):
        super().__init__()
        self.vit = vit_model
        self.target_size = target_size

    def forward(self, x):
        x = F.interpolate(x, size=self.target_size, mode='bilinear', align_corners=False)
        return self.vit(x)

def build_model_by_name(name):
    """
    Create model instance and wrap with adapter to accept 7-channel input.
    """
    name = name.lower()
    if name == "resnet152":
        base = models.resnet152(weights=models.ResNet152_Weights.DEFAULT)
    elif name == "resnet18":
        base = models.resnet18(weights=models.ResNet18_Weights.DEFAULT)
    elif name == "efficientnet_b4":
        base = models.efficientnet_b4(weights=models.EfficientNet_B4_Weights.DEFAULT)
    elif name == "resnet101":
        base = models.resnet101(weights=models.ResNet101_Weights.DEFAULT)
    elif name == "resnet50":
        base = models.resnet50(weights=models.ResNet50_Weights.DEFAULT)
    else:
        raise ValueError(f"Unknown model name: {name}")
    wrapped = ChannelAdapterAndHead(base,in_ch=7, num_classes=NUM_CLASSES)
    return wrapped

# ---------------- training / eval helpers ----------------
def train_one_epoch(model, loader, optimizer, criterion):
    model.train()
    total_loss = 0.0
    for images, labels in tqdm(loader, leave=False):
        images, labels = images.to(DEVICE), labels.to(DEVICE)
        optimizer.zero_grad()
        outputs = model(images)
        loss = criterion(outputs, labels)
        loss.backward()
        optimizer.step()
        total_loss += loss.item()
    return total_loss / max(1, len(loader))

def evaluate_model_f1(model, loader):
    model.eval()
    all_preds, all_labels = [], []
    with torch.no_grad():
        for images, labels in loader:
            images = images.to(DEVICE)
            outputs = model(images)
            preds = torch.argmax(outputs, dim=1).cpu().numpy()
            all_preds.extend(preds)
            all_labels.extend(labels.numpy())
    report = classification_report(all_labels, all_preds, digits=4)
    print(report)
    return f1_score(all_labels, all_preds, average='macro')

def evaluate_model_f1_student(model, loader):
    model.eval()
    all_preds, all_labels = [], []
    with torch.no_grad():
        for images, labels, _ in loader:
            images = images.to(DEVICE)
            outputs = model(images)
            preds = torch.argmax(outputs, dim=1).cpu().numpy()
            all_preds.extend(preds)
            all_labels.extend(labels.numpy())
    report = classification_report(all_labels, all_preds, digits=4)
    print(report)
    return f1_score(all_labels, all_preds, average='macro')

def generate_soft_targets(teacher_paths, dataset, batch_size=32):
    """
    Given list of teacher ckpt paths, load each and produce averaged soft probabilities
    for every sample in dataset (in order). Returns a numpy array shape (N, num_classes).
    """
    loader = DataLoader(dataset, batch_size=batch_size, shuffle=False)
    device = DEVICE
    # load teachers
    teachers = []
    for p in teacher_paths:
        name = p.split("__")[0]  # we saved like name__teacher_best.pth
        model = build_model_by_name(name).to(device)
        model.load_state_dict(torch.load(p, map_location=device))
        model.eval()
        teachers.append(model)

    all_avg_probs = []
    with torch.no_grad():
        for images, _ in tqdm(loader, desc="Generating soft targets"):
            images = images.to(device)
            probs_stack = []
            for t in teachers:
                logits = t(images)
                probs = torch.softmax(logits, dim=1)
                probs_stack.append(probs)
            avg = torch.mean(torch.stack(probs_stack, dim=0), dim=0)  # (B, C)
            all_avg_probs.append(avg.cpu())
    avg_probs = torch.cat(all_avg_probs, dim=0).numpy()
    return avg_probs

# Distillation loss
def distillation_loss(student_logits, teacher_probs, true_labels, T=2.0, alpha=0.7):
    # KL divergence between softened probabilities (teacher_probs here are already probs)
    log_p_s = nn.LogSoftmax(dim=1)(student_logits / T)
    p_t = torch.from_numpy(teacher_probs).to(student_logits.device) if isinstance(teacher_probs, np.ndarray) else teacher_probs
    # if teacher_probs are logits, apply softmax; we assume probs
    p_t = p_t.to(student_logits.device)
    soft_loss = nn.KLDivLoss(reduction='batchmean')(log_p_s, (p_t / p_t.sum(dim=1, keepdim=True))) * (T * T)
    hard_loss = nn.CrossEntropyLoss()(student_logits, true_labels)
    return alpha * soft_loss + (1.0 - alpha) * hard_loss

# ---------------- main pipeline ----------------
def main():
    random.seed(SEED_BASE)
    torch.manual_seed(SEED_BASE)
    augmentation = RandomAugmentation(rotation_range=15, translation_range=0, p_flip=0.5)
    dataset_full = BotrytisDataset(DATA_DIR, transform=augmentation)
    n = len(dataset_full)
    print(f"Total samples: {n}")

    # create a no-aug dataset for inference & soft-target generation (same normalization applied)
    dataset_noaug = BotrytisDataset(DATA_DIR, transform=None)

    teacher_ckpts = []  # paths saved for each teacher

    # Train teachers sequentially on different random splits (different seeds)
    for i, tname in enumerate(TEACHER_NAMES):
        print(f"\n=== TRAINING TEACHER {i+1}/{len(TEACHER_NAMES)}: {tname} ===")
        # make split with different random generator per teacher
        g = torch.Generator()
        g.manual_seed(SEED_BASE + i * 13 + 7)
        train_size = int(0.8 * n)
        val_size = n - train_size
        train_set, val_set = torch.utils.data.random_split(dataset_full, [train_size, val_size], generator=g)
        train_loader = DataLoader(train_set, batch_size=BATCH_SIZE, shuffle=True)
        val_loader = DataLoader(val_set, batch_size=BATCH_SIZE)

        model = build_model_by_name(tname).to(DEVICE)
        optimizer = optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-5)
        criterion = nn.CrossEntropyLoss()

        best_val_score = 0.0
        best_model_path = f"{tname}__teacher_best.pth"
        no_improve = 0

        for epoch in range(EPOCHS):
            print(f"\nEpoch {epoch+1}/{EPOCHS} (Teacher {tname})")
            train_loss = train_one_epoch(model, train_loader, optimizer, criterion)
            print(f"Train Loss: {train_loss:.4f}")
            val_f1 = evaluate_model_f1(model, val_loader)
            if val_f1 > best_val_score:
                best_val_score = val_f1
                torch.save(model.state_dict(), best_model_path)
                print(f"✅ Saved new best teacher model: {best_model_path} (F1={val_f1:.4f})")
                no_improve = 0
            else:
                no_improve += 1
                print(f"No improvement for {no_improve} epoch(s).")
            if no_improve >= PATIENCE:
                print("Early stopping teacher.")
                break

        print(f"Finished teacher {tname}. Best F1: {best_val_score:.4f}")
        teacher_ckpts.append(best_model_path)

    # ---------- generate averaged soft targets on the full dataset ----------
    print("\n=== Generating averaged soft targets from teacher ensemble ===")
    # Use the dataset without augmentation (dataset_noaug). Important: the dataset code applies normalization even with transform=None.
    soft_targets = generate_soft_targets(teacher_ckpts, dataset_noaug, batch_size=BATCH_SIZE)
    # soft_targets: shape (N, NUM_CLASSES) matching dataset_noaug ordering
    print(f"Soft targets shape: {soft_targets.shape}")

    # ---------- build student dataset & loader ----------
    # train student on the same dataset (with augmentation) but pair each sample with its soft target.
    class DistillDataset(Dataset):
        def __init__(self, base_dataset, soft_targets, transform=None):
            assert len(base_dataset) == len(soft_targets)
            self.base = base_dataset
            self.soft = soft_targets
            self.transform = transform

        def __len__(self):
            return len(self.base)

        def __getitem__(self, idx):
            img, label = self.base[idx]  # base dataset applies normalization already
            soft = self.soft[idx]
            return img, label, soft

    # create a train/val split for student training (we can use a fresh split)
    g = torch.Generator()
    g.manual_seed(SEED_BASE + 999)
    train_size = int(0.8 * n)
    val_size = n - train_size
    train_inds, val_inds = torch.utils.data.random_split(torch.arange(n), [train_size, val_size], generator=g)

    # Build datasets mapped to the same ordering as dataset_noaug
    # To index dataset_noaug directly, we need datasets that support indexing by integer in same order; our BotrytisDataset does.
    # Build arrays of imgs + labels via subset indices
    from torch.utils.data import Subset
    student_train_base = Subset(dataset_full, train_inds.indices if hasattr(train_inds, "indices") else train_inds)
    student_val_base = Subset(dataset_full, val_inds.indices if hasattr(val_inds, "indices") else val_inds)
    # Map soft targets correspondingly (dataset_noaug ordering is identical to dataset_full ordering)
    soft_np = soft_targets
    train_soft = soft_np[train_inds.indices if hasattr(train_inds, "indices") else train_inds]
    val_soft = soft_np[val_inds.indices if hasattr(val_inds, "indices") else val_inds]

    student_train = DistillDataset(student_train_base, train_soft, transform=None)
    student_val = DistillDataset(student_val_base, val_soft, transform=None)

    train_loader = DataLoader(student_train, batch_size=BATCH_SIZE, shuffle=True)
    val_loader = DataLoader(student_val, batch_size=BATCH_SIZE)

    # ---------- train student with distillation ----------
    print("\n=== Training student (distillation) ===")
    student = build_model_by_name(STUDENT_NAME).to(DEVICE)
    optimizer = optim.Adam(student.parameters(), lr=1e-3, weight_decay=1e-5)

    best_val = 0.0
    best_student_path = f"student_{STUDENT_NAME}_distilled.pth"
    no_improve = 0

    for epoch in range(EPOCHS):
        print(f"\nEpoch {epoch+1}/{EPOCHS} (Student)")
        student.train()
        total_loss = 0.0
        for imgs, labels, soft in tqdm(train_loader, leave=False):
            imgs = imgs.to(DEVICE)
            labels = labels.to(DEVICE)
            soft = soft.to(DEVICE)
            optimizer.zero_grad()
            logits = student(imgs)
            loss = distillation_loss(logits, soft, labels, T=DISTILL_T, alpha=DISTILL_ALPHA)
            loss.backward()
            optimizer.step()
            total_loss += loss.item()
        avg_train_loss = total_loss / max(1, len(train_loader))
        print(f"Train loss: {avg_train_loss:.4f}")

        # eval student using hard labels F1
        val_f1 = evaluate_model_f1_student(student, DataLoader(student_val, batch_size=BATCH_SIZE))
        if val_f1 > best_val:
            best_val = val_f1
            torch.save(student.state_dict(), best_student_path)
            print(f"✅ Saved new best student model: {best_student_path} (F1={val_f1:.4f})")
            no_improve = 0
        else:
            no_improve += 1
            print(f"No improvement for {no_improve} epoch(s).")
        if no_improve >= PATIENCE:
            print("Early stopping student.")
            break

    print(f"\nFinished. Best distilled student saved to {best_student_path} with F1={best_val:.4f}")

if __name__ == "__main__":
    main()
