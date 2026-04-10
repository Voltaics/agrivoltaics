import os
import torch
import torch.nn as nn
from PIL import Image
import numpy as np
from torch.utils.data import Dataset, DataLoader
import torchvision.transforms as transforms
import torchvision.models as models
from sklearn.metrics import classification_report, confusion_matrix
import argparse
from collections import Counter

# --- CONFIGURATION ---
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
MODEL_PATH = "pest_presence_resnet.pth"
TEST_DIR = "./pests_presence/valid"

# Exact mapping from your training script
CLASS_NAMES = [
    "Adult Spotted Lanternfly",      # 0
    "Early Nymph Spotted Lanternfly",# 1
    "Green Leafhopper",              # 2
    "Healthy",                       # 3
    "Japanese Beetle",               # 4
    "Late Nymph Spotted Lanternfly"  # 5
]

# --- MODEL DEFINITION (Must match your train.py exactly) ---
class PestPresenceResNet18(nn.Module):
    def __init__(self):
        super().__init__()
        self.model = models.resnet18(weights=None)
        in_features = self.model.fc.in_features
        self.model.fc = nn.Linear(in_features, 6)

    def forward(self, x):
        return self.model(x)

# --- DATASET DEFINITION (Matches your images/labels logic) ---
class PestPresenceDataset(Dataset):
    def __init__(self, data_dir, transform=None):
        self.transform = transform
        self.data, self.labels = [], []
        images_dir = os.path.join(data_dir, "images")
        labels_dir = os.path.join(data_dir, "labels")
        
        samples = [f for f in sorted(os.listdir(images_dir)) if f.endswith(".jpg")]
        
        for fname in samples:
            img_path = os.path.join(images_dir, fname)
            label_fname = fname.replace("image_", "label_").replace(".jpg", ".txt")
            label_path = os.path.join(labels_dir, label_fname)

            if os.path.exists(label_path):
                # Match your training load logic (1/255 normalization)
                image = np.array(Image.open(img_path)).astype(np.float32) / 255.0
                with open(label_path, 'r') as f:
                    lines = f.readlines()
                
                if lines:
                    classes = [line.split()[0] for line in lines]
                    most_common_class = Counter(classes).most_common(1)[0][0]
                    label = int(most_common_class)
                else:
                    label = 0 # Default to class 0 if empty

                self.data.append(torch.tensor(image).permute(2,0,1))
                self.labels.append(torch.tensor(label, dtype=torch.long))

    def __len__(self):
        return len(self.data)

    def __getitem__(self, idx):
        image, label = self.data[idx].clone(), self.labels[idx]
        if self.transform:
            image = self.transform(image)
        return image, label

# --- INFERENCE FUNCTION ---
def predict_single_image(image_path, model, transform):
    # Load and normalize like training
    image = np.array(Image.open(image_path)).astype(np.float32) / 255.0
    image_tensor = torch.tensor(image).permute(2,0,1)
    image_tensor = transform(image_tensor).unsqueeze(0).to(DEVICE)
    
    with torch.no_grad():
        output = model(image_tensor)
        probabilities = torch.nn.functional.softmax(output[0], dim=0)
        conf, pred = torch.max(probabilities, 0)
        
    return pred.item(), conf.item()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--image', type=str, help='Path to a single image to test')
    parser.add_argument('--folder', type=str, help='Path to a folder of images to test')
    args = parser.parse_args()

    # Define the exact same normalization used in val_transform
    normalize = transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])

    # 1. Load Model
    print(f"Loading weights from {MODEL_PATH}...")
    model = PestPresenceResNet18().to(DEVICE)
    model.load_state_dict(torch.load(MODEL_PATH, map_location=DEVICE))
    model.eval()

    # 2. RUN MODES
    if args.image:
        # Single Image Inference
        label_idx, confidence = predict_single_image(args.image, model, normalize)
        print(f"\nTarget: {args.image}")
        print(f"Result: {CLASS_NAMES[label_idx]} ({confidence:.2%})")

    elif args.folder:
        # Folder Inference (No labels needed)
        print(f"\n{'Filename':<30} | {'Prediction':<25} | {'Conf'}")
        print("-" * 70)
        for f in sorted(os.listdir(args.folder)):
            if f.lower().endswith(('.jpg', '.png', '.jpeg')):
                idx, conf = predict_single_image(os.path.join(args.folder, f), model, normalize)
                print(f"{f:<30} | {CLASS_NAMES[idx]:<25} | {conf:.2%}")

    else:
        # Default: Run evaluation on official TEST_DIR
        print(f"Running full evaluation on: {TEST_DIR}")
        test_dataset = PestPresenceDataset(TEST_DIR, transform=normalize)
        test_loader = DataLoader(test_dataset, batch_size=32, shuffle=False)

        y_true, y_pred = [], []
        with torch.no_grad():
            for x, y in test_loader:
                x = x.to(DEVICE)
                logits = model(x)
                preds = torch.argmax(logits, dim=1).cpu().numpy()
                y_true.extend(y.numpy())
                y_pred.extend(preds)

        print("\n--- FINAL TEST REPORT ---")
        print(classification_report(y_true, y_pred, target_names=CLASS_NAMES, digits=4))

if __name__ == "__main__":
    main()