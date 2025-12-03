# vine_presence_train_resnet.py

import os
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
import numpy as np
from sklearn.metrics import classification_report, f1_score
from tqdm import tqdm
import torchvision.transforms.functional as TF
import torchvision.models as models
import random

#config
DATA_DIR = "./vine_presence_data_64"
BATCH_SIZE = 32
EPOCHS = 100
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

def adjust_brightness(tensor, factor):
    return tensor * factor

def adjust_contrast(tensor, factor):
    mean = tensor.mean(dim=(1, 2), keepdim=True)
    return (tensor - mean) * factor + mean

class VineAugmentation:
    def __call__(self, tensor):
        if random.random() < 0.5:
            tensor = torch.flip(tensor, dims=[2])
        angle = random.uniform(-10, 10)
        tensor = TF.rotate(tensor, angle, interpolation=TF.InterpolationMode.BILINEAR)
        tx, ty = random.uniform(-5, 5), random.uniform(-5, 5)
        tensor = TF.affine(tensor, angle=0, translate=(tx, ty), scale=1.0, shear=0, interpolation=TF.InterpolationMode.BILINEAR)
        tensor = adjust_brightness(tensor, random.uniform(0.9, 1.1))
        tensor = adjust_contrast(tensor, random.uniform(0.9, 1.1))
        return tensor

class VinePresenceDataset(Dataset):
    def __init__(self, data_dir, transform=None):
        self.transform = transform
        self.global_mean = np.load("global_mean.npy")
        self.global_std = np.load("global_std.npy")

        # preload all samples into memory
        self.data, self.labels = [], []
        samples = [f for f in sorted(os.listdir(data_dir)) if f.startswith("image_") and f.endswith(".npy")]
        for fname in samples:
            img_path = os.path.join(data_dir, fname)
            label_path = img_path.replace("image_", "label_").replace(".npy", ".txt")

            image = np.load(img_path).astype(np.float32)
            label = int(open(label_path).read().strip())

            self.data.append(torch.tensor(image))
            self.labels.append(torch.tensor(label, dtype=torch.long))

    def __len__(self):
        return len(self.data)

    def __getitem__(self, idx):
        image, label = self.data[idx].clone(), self.labels[idx]

        if self.transform:
            image = self.transform(image)

        # normalize channels
        for c in range(image.shape[0]):
            image[c] = (image[c] - self.global_mean[c]) / (self.global_std[c] + 1e-8)

        return image, label


class VinePresenceResNet18(nn.Module):
    def __init__(self):
        super().__init__()
        base = models.resnet18(pretrained=False)
        self.conv1 = nn.Conv2d(7, 64, kernel_size=7, stride=2, padding=3, bias=False)
        self.bn1 = base.bn1
        self.relu = base.relu
        self.maxpool = base.maxpool
        self.layer1 = base.layer1
        self.layer2 = base.layer2
        self.layer3 = base.layer3
        self.layer4 = base.layer4
        self.avgpool = base.avgpool
        self.fc = nn.Linear(512, 2)

    def forward(self, x):
        x = self.conv1(x)
        x = self.bn1(x)
        x = self.relu(x)
        x = self.maxpool(x)
        x = self.layer1(x)
        x = self.layer2(x)
        x = self.layer3(x)
        x = self.layer4(x)
        x = self.avgpool(x)
        x = torch.flatten(x, 1)
        x = self.fc(x)
        return x

def train(model, loader, optimizer, criterion):
    model.train()
    total_loss = 0
    for x, y in tqdm(loader):
        x, y = x.to(DEVICE), y.to(DEVICE)
        optimizer.zero_grad()
        pred = model(x)
        loss = criterion(pred, y)
        loss.backward()
        optimizer.step()
        total_loss += loss.item()
    return total_loss / len(loader)

def evaluate(model, loader):
    model.eval()
    y_true, y_pred = [], []
    with torch.no_grad():
        for x, y in loader:
            x = x.to(DEVICE)
            logits = model(x)
            pred = torch.argmax(logits, dim=1).cpu().numpy()
            y_true.extend(y.numpy())
            y_pred.extend(pred)
    print(classification_report(y_true, y_pred, digits=4))
    return f1_score(y_true, y_pred, average='macro')

def main():
    dataset = VinePresenceDataset(DATA_DIR)
    train_size = int(0.8 * len(dataset))
    val_size = len(dataset) - train_size
    train_set, val_set = torch.utils.data.random_split(dataset, [train_size, val_size])

    train_loader = DataLoader(train_set, batch_size=BATCH_SIZE, shuffle=True)
    val_loader = DataLoader(val_set, batch_size=BATCH_SIZE)

    model = VinePresenceResNet18().to(DEVICE)
    optimizer = optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-5)
    criterion = nn.CrossEntropyLoss(weight=torch.tensor([1.0, 1.0]).to(DEVICE))

    best_f1 = 0
    patience = 40
    stagnation = 0

    for epoch in range(EPOCHS):
        print(f"\nEpoch {epoch+1}/{EPOCHS}")
        loss = train(model, train_loader, optimizer, criterion)
        print(f"Train Loss: {loss:.4f}")
        val_f1 = evaluate(model, val_loader)
        if val_f1 > best_f1:
            best_f1 = val_f1
            torch.save(model.state_dict(), "vine_presence_resnet.pth")
            print(f"✅ New best model saved! F1 = {val_f1:.4f}")
            stagnation = 0
        else:
            stagnation += 1
            print(f"No improvement for {stagnation} epochs")
            if stagnation >= patience:
                print("⛔ Early stopping triggered")
                break

if __name__ == "__main__":
    main()
