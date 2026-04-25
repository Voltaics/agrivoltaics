from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import cv2
import matplotlib.pyplot as plt
import numpy as np
import tifffile as tiff
import torch
import torch.nn as nn
import torch.nn.functional as F
import torchvision.models as models
from tqdm import tqdm

TILE_SIZE = 64
STRIDE = 32
DEVICE = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
APP_ROOT = Path(__file__).resolve().parent

GLOBALS_ROOT = Path(os.environ.get('GLOBALS_ROOT', APP_ROOT / 'globals'))
MODEL_ROOT = Path(os.environ.get('MODEL_ROOT', APP_ROOT / 'model_weights'))

VINE_MODEL_PATH = Path(os.environ.get('VINE_MODEL_PATH', MODEL_ROOT / 'vine_presence_resnet.pth'))
DISEASE_MODEL_PATH = Path(os.environ.get('DISEASE_MODEL_PATH', MODEL_ROOT / 'student_resnet18_distilled.pth'))

GLOBAL_MEAN_PATH = Path(os.environ.get('GLOBAL_MEAN_PATH', GLOBALS_ROOT / 'global_mean.npy'))
GLOBAL_STD_PATH = Path(os.environ.get('GLOBAL_STD_PATH', GLOBALS_ROOT / 'global_std.npy'))


class StudentResNetWrapper(nn.Module):
    def __init__(self, num_classes=2, in_ch=7):
        super().__init__()
        base = models.resnet18(weights=None)
        self.base = base
        self._adapt_first_conv(in_ch)
        self._replace_head(num_classes)

    def _adapt_first_conv(self, in_ch):
        conv = self.base.conv1
        new_conv = nn.Conv2d(in_ch, conv.out_channels, kernel_size=conv.kernel_size, stride=conv.stride, padding=conv.padding, bias=(conv.bias is not None))
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
            nn.Linear(1000, num_classes),
        )

    def forward(self, x):
        return self.base(x)


def sliding_window(image, tile_size, stride):
    _, H, W = image.shape
    for y in range(0, H - tile_size + 1, stride):
        for x in range(0, W - tile_size + 1, stride):
            yield x, y, image[:, y:y + tile_size, x:x + tile_size]


def normalize_to_uint8(img):
    img = np.asarray(img, dtype=np.float32)
    min_val = float(np.min(img))
    max_val = float(np.max(img))
    if max_val <= min_val:
        return np.zeros_like(img, dtype=np.uint8)
    return (((img - min_val) / (max_val - min_val)) * 255.0).clip(0, 255).astype(np.uint8)


def _load_models():
    if not VINE_MODEL_PATH.exists():
        raise FileNotFoundError(f'Missing vine model weights: {VINE_MODEL_PATH}')
    if not DISEASE_MODEL_PATH.exists():
        raise FileNotFoundError(f'Missing disease model weights: {DISEASE_MODEL_PATH}')

    vine_model = models.resnet18(weights=None)
    vine_model.conv1 = nn.Conv2d(7, 64, kernel_size=7, stride=2, padding=3, bias=False)
    vine_model.fc = nn.Linear(512, 2)
    vine_model.load_state_dict(torch.load(VINE_MODEL_PATH, map_location=DEVICE, weights_only=True))
    vine_model.to(DEVICE).eval()

    disease_model = StudentResNetWrapper(num_classes=2, in_ch=7)
    disease_model.load_state_dict(torch.load(DISEASE_MODEL_PATH, map_location=DEVICE, weights_only=True))
    disease_model.to(DEVICE).eval()
    return vine_model, disease_model


def run_inference(input_folder: str, output_folder: str):
    input_folder = Path(input_folder)
    output_folder = Path(output_folder)
    output_folder.mkdir(parents=True, exist_ok=True)

    band_paths = [input_folder / f'aligned_band{i}.tif' for i in range(1, 6)]
    for path in band_paths:
        if not path.exists():
            raise FileNotFoundError(f'Missing band file: {path}')

    bands = [tiff.imread(str(p)).astype(np.float32) for p in band_paths]
    bands = [b[:, :, 0] if b.ndim == 3 else b for b in bands]
    image = np.stack(bands)

    red = image[2]
    nir = image[3]
    red_edge = image[4]
    ndvi = (nir - red) / (nir + red + 1e-6)
    ndre = (nir - red_edge) / (nir + red_edge + 1e-6)
    image = np.concatenate([image, ndvi[np.newaxis, ...], ndre[np.newaxis, ...]], axis=0)

    global_mean = np.load(GLOBAL_MEAN_PATH)
    global_std = np.load(GLOBAL_STD_PATH)
    for c in range(image.shape[0]):
        image[c] = (image[c] - global_mean[c]) / (global_std[c] + 1e-8)

    H, W = image.shape[1], image.shape[2]
    composite_color = cv2.merge([
        normalize_to_uint8(bands[1]),
        normalize_to_uint8(bands[2]),
        normalize_to_uint8(bands[0]),
    ])

    vine_model, disease_model = _load_models()

    gradcam_activations = {}
    gradcam_gradients = {}

    def forward_hook(module, _input, output):
        gradcam_activations['value'] = output.detach()

    def backward_hook(module, grad_input, grad_output):
        gradcam_gradients['value'] = grad_output[0].detach()

    target_layer = disease_model.base.layer4[-1].conv2
    target_layer.register_forward_hook(forward_hook)
    target_layer.register_full_backward_hook(backward_hook)

    heatmap = np.zeros((H, W), dtype=np.float32)
    count_map = np.zeros((H, W), dtype=np.float32)
    disease_positive_tiles = 0
    vine_positive_tiles = 0
    max_disease_prob = 0.0

    for x, y, patch in tqdm(sliding_window(image, TILE_SIZE, STRIDE)):
        patch_tensor = torch.tensor(patch, dtype=torch.float32, requires_grad=True).unsqueeze(0).to(DEVICE)
        with torch.no_grad():
            vine_out = vine_model(patch_tensor)
            vine_prob = torch.softmax(vine_out, dim=1)[0, 1].item()
        if vine_prob < 0.5:
            continue
        vine_positive_tiles += 1

        output = disease_model(patch_tensor)
        disease_prob = torch.softmax(output, dim=1)[0, 1].item()
        max_disease_prob = max(max_disease_prob, float(disease_prob))
        heatmap[y:y + TILE_SIZE, x:x + TILE_SIZE] += disease_prob
        count_map[y:y + TILE_SIZE, x:x + TILE_SIZE] += 1

        if disease_prob < 0.9:
            continue
        disease_positive_tiles += 1

        loss = output[0, 1]
        disease_model.zero_grad()
        loss.backward()

        act = gradcam_activations['value'][0]
        grad = gradcam_gradients['value'][0]
        weights = grad.mean(dim=(1, 2))
        cam = (weights.unsqueeze(1).unsqueeze(2) * act).sum(0)
        cam = F.relu(cam)
        cam = F.interpolate(cam.unsqueeze(0).unsqueeze(0), size=(TILE_SIZE, TILE_SIZE), mode='bilinear', align_corners=False)[0, 0]
        cam = (cam - cam.min()) / (cam.max() - cam.min() + 1e-8)
        cam_np = (cam.cpu().numpy() * 255).astype(np.uint8)

        _, binary_map = cv2.threshold(cam_np, 200, 255, cv2.THRESH_BINARY)
        contours, _ = cv2.findContours(binary_map, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        for cnt in contours:
            bx, by, bw, bh = cv2.boundingRect(cnt)
            if bw * bh < 50:
                continue
            cv2.rectangle(composite_color, (x + bx, y + by), (x + bx + bw, y + by + bh), (0, 0, 255), 2)

    valid_mask = count_map > 0
    heatmap[valid_mask] /= count_map[valid_mask]
    heatmap_vis = (heatmap * 255).clip(0, 255).astype(np.uint8)
    heatmap_color = cv2.applyColorMap(heatmap_vis, cv2.COLORMAP_JET)
    overlay = cv2.addWeighted(composite_color, 0.6, heatmap_color, 0.4, 0)

    overlay_path = output_folder / 'FINAL_combined_overlay_with_boxes.png'
    heatmap_path = output_folder / 'FINAL_combined_heatmap.png'
    boxes_path = output_folder / 'FINAL_combined_cam_boxes.png'
    cv2.imwrite(str(overlay_path), overlay)
    cv2.imwrite(str(heatmap_path), heatmap_color)
    cv2.imwrite(str(boxes_path), composite_color)

    disease_detected = disease_positive_tiles > 0
    summary = {
        'device': str(DEVICE),
        'disease_detected': disease_detected,
        'analysis_label': int(disease_detected),
        'max_disease_probability': float(max_disease_prob),
        'vine_positive_tiles': int(vine_positive_tiles),
        'disease_positive_tiles': int(disease_positive_tiles),
        'output_files': {
            'overlay': str(overlay_path),
            'heatmap': str(heatmap_path),
            'boxes': str(boxes_path),
        },
    }
    with open(output_folder / 'response.json', 'w', encoding='utf-8') as f:
        json.dump(summary, f, indent=2)
    return summary


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Run disease inference on aligned multispectral bands.')
    parser.add_argument('--folder', required=True, help='Aligned folder')
    parser.add_argument('--output', required=True, help='Inference output folder')
    args = parser.parse_args()
    result = run_inference(args.folder, args.output)
    print(json.dumps(result, indent=2))
