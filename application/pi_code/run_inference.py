#combined_infer_with_cam_boxes.py — Runs vine classifier then, for vine-positive tiles,
#computes a Grad-CAM for the disease classifier, extracts bounding boxes from it, and
#draws these boxes on the full composite image.

import os
import cv2
import tifffile as tiff
import torch
import numpy as np
import torch.nn as nn
import torchvision.models as models
import torch.nn.functional as F
from tqdm import tqdm
import matplotlib.pyplot as plt
import argparse

#CONFIGURATION
TILE_SIZE = 64
STRIDE = 32
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

#MODEL PATHS
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
VINE_MODEL_PATH = os.path.join(PROJECT_ROOT, "model_training", "vine_presence_resnet.pth")
DISEASE_MODEL_PATH = os.path.join(PROJECT_ROOT, "model_training", "student_resnet18_distilled.pth")
DISEASE_TRAIN_PATH = os.path.join(PROJECT_ROOT, "model_training", "disease_train.py")

#SLIDING WINDOW FUNCTION
def sliding_window(image, tile_size, stride):
    # image shape: (C, H, W)
    C, H, W = image.shape
    for y in range(0, H - tile_size + 1, stride):
        for x in range(0, W - tile_size + 1, stride):
            patch = image[:, y:y+tile_size, x:x+tile_size]
            yield (x, y, patch)

#STUDENT RESNET-18 WRAPPER (for disease classifier)
class StudentResNetWrapper(nn.Module):
    def __init__(self, num_classes=2, in_ch=7):
        super().__init__()
        # load base ResNet-18
        base = models.resnet18(weights=None)  # no ImageNet weights
        self.base = base
        self._adapt_first_conv(in_ch)
        self._replace_head(num_classes)

    def _adapt_first_conv(self, in_ch):
        conv = self.base.conv1
        new_conv = nn.Conv2d(
            in_ch, conv.out_channels,
            kernel_size=conv.kernel_size,
            stride=conv.stride,
            padding=conv.padding,
            bias=(conv.bias is not None)
        )
        with torch.no_grad():
            if conv.weight.shape[1] == 3:
                new_conv.weight[:, :3, :, :] = conv.weight
                avg = conv.weight.mean(dim=1, keepdim=True)
                new_conv.weight[:, 3:, :, :] = avg.repeat(1, in_ch - 3, 1, 1)
        self.base.conv1 = new_conv

    def _replace_head(self, num_classes):
        in_features = self.base.fc.in_features
        self.base.fc = nn.Sequential(
            nn.Linear(in_features, 1000),
            nn.BatchNorm1d(1000),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(1000, num_classes)
        )

    def forward(self, x):
        return self.base(x)

def main(input_folder, output_folder): 
    #BAND PATHS 
    BAND_PATHS = [
        f"{input_folder}/aligned_band1.tif",  # Blue
        f"{input_folder}/aligned_band2.tif",  # Green
        f"{input_folder}/aligned_band3.tif",  # Red
        f"{input_folder}/aligned_band4.tif",  # NIR
        f"{input_folder}/aligned_band5.tif",  # RedEdge
    ]

    for path in BAND_PATHS:
        if not os.path.exists(path):
            raise FileNotFoundError(f"Missing band file: {path}")

    #LOAD IMAGE BANDS
    bands = [tiff.imread(p).astype(np.float32) for p in BAND_PATHS]

    # If the band is HxWxC (e.g., RGB/1-channel), take first channel
    bands = [b[:, :, 0] if b.ndim == 3 else b for b in bands]

    image = np.stack(bands)  # shape: (num_bands, H, W)


    #Compute NDVI and NDRE
    red = image[2]
    nir = image[3]
    red_edge = image[4]
    eps = 1e-6
    ndvi = (nir - red) / (nir + red + eps)
    ndre = (nir - red_edge) / (nir + red_edge + eps)
    #Now we have 7 channels: 5 original + NDVI + NDRE
    image = np.concatenate([image, ndvi[np.newaxis, ...], ndre[np.newaxis, ...]], axis=0)

    #Normalize using precomputed global mean and std
    global_mean = np.load("global_mean.npy")
    global_std = np.load("global_std.npy")
    for c in range(image.shape[0]):
        image[c] = (image[c] - global_mean[c]) / (global_std[c] + 1e-8)

    H, W = image.shape[1], image.shape[2]

    def normalize_to_uint8(img):
        """Normalize a single-channel or multi-channel array to uint8 [0, 255]."""
        img = np.asarray(img, dtype=np.float32)
        min_val = float(np.min(img))
        max_val = float(np.max(img))
        if max_val <= min_val:
            return np.zeros_like(img, dtype=np.uint8)
        scaled = (img - min_val) / (max_val - min_val)
        return (scaled * 255.0).clip(0, 255).astype(np.uint8)

    #Create a composite image for visualization
    #Here we use a simple RGB composite (channels: Green, Red, NIR) → (B, G, R) for false color
    composite = cv2.merge([
        normalize_to_uint8(bands[1]), # Green
        normalize_to_uint8(bands[2]), # Red
        normalize_to_uint8(bands[0]), # Blue
    ])
    composite_color = composite.copy()

    #Load Vine Classifier (ResNet-18)
    vine_model = models.resnet18(weights=None)
    vine_model.conv1 = nn.Conv2d(7, 64, kernel_size=7, stride=2, padding=3, bias=False)
    vine_model.fc = nn.Linear(512, 2)
    vine_model.load_state_dict(torch.load(VINE_MODEL_PATH, map_location=DEVICE, weights_only=True))
    vine_model.to(DEVICE)
    vine_model.eval()

    #Load Disease Classifier (ResNet-18)
    disease_model = StudentResNetWrapper(num_classes=2, in_ch=7)
    disease_model.load_state_dict(torch.load(DISEASE_MODEL_PATH, map_location=DEVICE, weights_only=True))
    disease_model.to(DEVICE)
    disease_model.eval()


    #Register Grad-CAM hooks on disease_model
    gradcam_activations = {}
    gradcam_gradients = {}

    def forward_hook(module, input, output):
        gradcam_activations['value'] = output.detach()

    def backward_hook(module, grad_input, grad_output):
        gradcam_gradients['value'] = grad_output[0].detach()

    #Hook into the last conv layer of ResNet-18:
    target_layer = disease_model.base.layer4[-1].conv2
    target_layer.register_forward_hook(forward_hook)
    target_layer.register_full_backward_hook(backward_hook)

    heatmap = np.zeros((H, W), dtype=np.float32)
    count_map = np.zeros((H, W), dtype=np.float32)

    #Process each patch
    for (x, y, patch) in tqdm(sliding_window(image, TILE_SIZE, STRIDE)):
        #Convert patch (7, TILE_SIZE, TILE_SIZE) to tensor
        patch_tensor = torch.tensor(patch, dtype=torch.float32, requires_grad=True).unsqueeze(0).to(DEVICE)

        #Stage 1: Vine classification (no gradients needed)
        with torch.no_grad():
            vine_out = vine_model(patch_tensor)
            vine_prob = torch.softmax(vine_out, dim=1)[0, 1].item()
        if vine_prob < 0.5:
            continue  # Skip patches that are likely not vines

        #Stage 2: Disease classification with Grad-CAM
        output = disease_model(patch_tensor)
        disease_prob = torch.softmax(output, dim=1)[0, 1].item()

        heatmap[y:y+TILE_SIZE, x:x+TILE_SIZE] += disease_prob
        count_map[y:y+TILE_SIZE, x:x+TILE_SIZE] += 1

        if disease_prob < 0.9:
            continue

        #Use the "infected" class score for Grad-CAM
        loss = output[0, 1]
        disease_model.zero_grad()
        loss.backward()

        #Compute Grad-CAM for this patch
        act = gradcam_activations['value'][0]  # shape: (C, h, w)
        grad = gradcam_gradients['value'][0]     # shape: (C, h, w)
        weights = grad.mean(dim=(1, 2))          # shape: (C,)
        cam = (weights.unsqueeze(1).unsqueeze(2) * act).sum(0)
        cam = F.relu(cam)
        #Upsample CAM to patch size (TILE_SIZE x TILE_SIZE)
        cam = F.interpolate(cam.unsqueeze(0).unsqueeze(0),
                            size=(TILE_SIZE, TILE_SIZE),
                            mode='bilinear',
                            align_corners=False)[0, 0]
        cam = (cam - cam.min()) / (cam.max() - cam.min() + 1e-8)
        cam_np = (cam.cpu().numpy() * 255).astype(np.uint8)

        #Extract bounding boxes from the CAM
        #Adjust the threshold as needed (here we use 200)
        thresh_val = 200
        ret, binary_map = cv2.threshold(cam_np, thresh_val, 255, cv2.THRESH_BINARY)
        contours, _ = cv2.findContours(binary_map, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        #For each contour, compute bounding box and draw it on the composite image
        for cnt in contours:
            bx, by, bw, bh = cv2.boundingRect(cnt)
            #Optionally, filter out small boxes (e.g., area < 50 pixels)
            if bw * bh < 50:
                continue
            #Offset the local patch coordinates (bx, by) by the patch position (x, y)
            cv2.rectangle(composite_color, (x + bx, y + by), (x + bx + bw, y + by + bh), (0, 0, 255), 2)

    #heatmap
    valid_mask = count_map > 0
    heatmap[valid_mask] /= count_map[valid_mask]
    heatmap_vis = (heatmap * 255).astype(np.uint8)
    heatmap_color = cv2.applyColorMap(heatmap_vis, cv2.COLORMAP_JET)
    overlay = cv2.addWeighted(composite_color, 0.6, heatmap_color, 0.4, 0)

    cv2.imwrite(f"{output_folder}/FINAL_combined_overlay_with_boxes.png", overlay)
    print("Output saved: FINAL_combined_overlay_with_boxes.png")


    cv2.imwrite(f"{output_folder}/FINAL_combined_heatmap.png", heatmap_color)
    print("Output saved: FINAL_combined_heatmap.png")        

    #Save and display the final composite image with CAM-based bounding boxes
    cv2.imwrite(f"{output_folder}/FINAL_combined_cam_boxes.png", composite_color)
    print("Output saved: FINAL_combined_cam_boxes.png")
    plt.figure(figsize=(10, 10))
    plt.imshow(cv2.cvtColor(composite_color, cv2.COLOR_BGR2RGB).astype(np.uint8))
    plt.title("CAM-based Bounding Boxes")
    plt.axis("off")
    #plt.show()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="run inferense")
    parser.add_argument("--folder", type=str, required=True,
                        help="Path to the processed images folder")
    parser.add_argument("--output", type=str, required=True,
                        help="Path to the processed images folder")
    args = parser.parse_args()

    input_folder = args.folder
    output_folder = args.output
    
    main(input_folder, output_folder)
