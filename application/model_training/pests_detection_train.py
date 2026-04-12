# vine_presence_train_resnet.py

import os
import torch
import torch.nn as nn
from PIL import Image
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
import numpy as np
from sklearn.metrics import classification_report, f1_score
from tqdm import tqdm
import torchvision.transforms.functional as TF
import torchvision.models as models
import torchvision
import torchvision.transforms as transforms
import random
from collections import Counter

# Classes
# 0 - Adult Spotted Lanternfly
# 1 - Early Nymph Spotted Laternfly
# 2 - Green Leafhopper
# 3 - Healthy
# 4 - Japanese Beetle
# 5 - Late Nymph Spotted Laternfly


#config
TRAIN_DIR = "./pests_presence/train"
VALID_DIR = "./pests_presence/valid"
TEST_DIR = "./pests_presence/test"

BATCH_SIZE = 32
EPOCHS = 100
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"Using device: {DEVICE}")

def adjust_brightness(tensor, factor):
    return tensor * factor

def adjust_contrast(tensor, factor):
    mean = tensor.mean(dim=(1, 2), keepdim=True)
    return (tensor - mean) * factor + mean

class PestAugmentation:
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

class PestPresenceDataset(Dataset):
    def __init__(self, data_dir, transform=None):
        self.transform = transform

        # preload all samples into memory from all folders
        self.data, self.labels = [], []

        images_dir = os.path.join(data_dir, "images")
        labels_dir = os.path.join(data_dir, "labels")
        
        # List files from the images directory
        samples = [f for f in sorted(os.listdir(images_dir)) if f.endswith(".jpg")]
        
        for fname in samples:
            img_path = os.path.join(images_dir, fname)
            label_fname = fname.replace("image_", "label_").replace(".jpg", ".txt")
            label_path = os.path.join(labels_dir, label_fname)

            # Only add if label exists
            if os.path.exists(label_path):
                image = np.array(Image.open(img_path)).astype(np.float32) / 255.0
                
                with open(label_path, 'r') as f:
                    lines = f.readlines()
                
                if lines:
                    # Extract the first column (class_id) from every line
                    classes = [line.split()[0] for line in lines]
                    # Assign the label based on the most frequent class in that image
                    most_common_class = Counter(classes).most_common(1)[0][0]
                    label = int(most_common_class)
                else:
                    # If file is empty, we assume it's background/class 0
                    label = 0

                self.data.append(torch.tensor(image).permute(2,0,1))
                self.labels.append(torch.tensor(label, dtype=torch.long))

    def __len__(self):
        return len(self.data)

    def __getitem__(self, idx):
        image, label = self.data[idx].clone(), self.labels[idx]

        if self.transform:
            image = self.transform(image)

        return image, label
        #image = np.array(Image.open(img_path)).astype(np.float32)
        # image, label = self.data[idx].clone(), self.labels[idx]

        # if self.transform:
        #     image = self.transform(image)


        # return image, label


class PestPresenceResNet18(nn.Module):
    def __init__(self):
        super().__init__()
        weights = models.ResNet18_Weights.DEFAULT
        self.model = models.resnet18(weights=weights)

        in_features = self.model.fc.in_features
        self.model.fc = nn.Linear(in_features, 6)
        #base = models.resnet18(weights=weights)
        # base = models.resnet18(pretrained=False)
        # self.conv1 = nn.Conv2d(3, 64, kernel_size=7, stride=2, padding=3, bias=False)
        # self.bn1 = base.bn1
        # self.relu = base.relu
        # self.maxpool = base.maxpool
        # self.layer1 = base.layer1
        # self.layer2 = base.layer2
        # self.layer3 = base.layer3
        # self.layer4 = base.layer4
        # self.avgpool = base.avgpool
        # self.fc = nn.Linear(512, 6)

    def forward(self, x):
        return self.model(x)
        # x = self.conv1(x)
        # x = self.bn1(x)
        # x = self.relu(x)
        # x = self.maxpool(x)
        # x = self.layer1(x)
        # x = self.layer2(x)
        # x = self.layer3(x)
        # x = self.layer4(x)
        # x = self.avgpool(x)
        # x = torch.flatten(x, 1)
        # x = self.fc(x)
        # return x

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
    
    print("Initializing Training Dataset... \n")
    normalize = torchvision.transforms.Normalize(
        mean=[0.485, 0.456, 0.406],
        std=[0.229, 0.224, 0.225]
    )

    train_transform = transforms.Compose([
        #transforms.RandomResizedCrop(size=(224, 224), scale=(0.8, 1.0)),
        PestAugmentation(), 
        normalize
    ])

    val_transform = transforms.Compose([
        normalize
    ])
    train_dataset = PestPresenceDataset(TRAIN_DIR, transform=train_transform,)
    print("Initializing Validation Dataset... \n")
    val_dataset = PestPresenceDataset(VALID_DIR, transform=val_transform)

    print("Loading and Shuffling Training Dataset... \n")
    train_loader = DataLoader(train_dataset, batch_size=BATCH_SIZE, shuffle=True)
    print("Loading and Shuffling Validation Dataset... \n")
    val_loader = DataLoader(val_dataset, batch_size=BATCH_SIZE)

    print("Setting up the model \n")
    model = PestPresenceResNet18().to(DEVICE)
    
    
    optimizer = optim.Adam(model.parameters(), lr=1e-4, weight_decay=1e-5)
    class_weights = torch.tensor([1.0, 1.0, 1.0, 1.0, 1.0, 2.5]).to(DEVICE)
    criterion = nn.CrossEntropyLoss(weight=class_weights)

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
            torch.save(model.state_dict(), "pest_presence_resnet.pth")
            print(f"✅ New best model saved! F1 = {val_f1:.4f}")
            output_filename = "pest_presence_resnet.pth"
            torch.save(model.state_dict(), output_filename)
            print(f"✅ New best model saved to {os.path.abspath(output_filename)}! F1 = {val_f1:.4f}")
            stagnation = 0
        else:
            stagnation += 1
            print(f"No improvement for {stagnation} epochs")
            if stagnation >= patience:
                print("⛔ Early stopping triggered")
                break

if __name__ == "__main__":
    main()
