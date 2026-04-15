# -*- coding: utf-8 -*-
"""
Created on Tue Mar 10 19:57:08 2026

@author: ayushi
"""

# export_model.py
import torch
from transformers import ViTForImageClassification, ViTConfig, ViTFeatureExtractor

# Load your weights
checkpoint = torch.load(r"C:\Users\ayush\Desktop\vines\output\checkpoints\best.pt", map_location="cpu")

# Pull the labels directly from the checkpoint
id2label = checkpoint["id2label"]
label2id = checkpoint["label2id"]

# Convert string keys to ints if needed (common after saving/loading JSON)
if isinstance(list(id2label.keys())[0], str):
    id2label = {int(k): v for k, v in id2label.items()}
    label2id = {v: int(k) for k, v in id2label.items()}

print(f"Found {len(id2label)} classes: {list(id2label.values())}")

# Build config
config = ViTConfig(
    num_labels=len(id2label),
    id2label=id2label,
    label2id=label2id,
    image_size=224,
)

model = ViTForImageClassification(config)

# Load just the model weights from the nested key
state_dict = checkpoint["model_state"]

# Remove pooler keys — not used by ViTForImageClassification
state_dict = {k: v for k, v in state_dict.items() 
              if not k.startswith("vit.pooler")}

model.load_state_dict(state_dict)
model.eval()

model.save_pretrained("./model")

extractor = ViTFeatureExtractor(image_size=224)
extractor.save_pretrained("./model")

print(f"Done — best val acc from training: {checkpoint.get('best_val_acc', 'N/A')}")
print("Model exported to ./model/")