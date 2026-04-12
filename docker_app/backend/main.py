# -*- coding: utf-8 -*-
"""FastAPI inference server for ViT plant disease classification.

Inference uses the same leaf stacking pipeline as training (see leaf_preprocess.py).
"""

from pathlib import Path

import io
import os

import cv2
import numpy as np
import torch
from fastapi import FastAPI, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image
from transformers import AutoImageProcessor, ViTForImageClassification

try:
    from .leaf_preprocess import preprocess_bgr_to_stacked
except ImportError:
    from leaf_preprocess import preprocess_bgr_to_stacked

# Model directory: next to this file (works in Docker and local runs).
_MODEL_DIR = Path(__file__).resolve().parent / "model"

# Preprocessing is on by default to match the trained checkpoint. Set DISABLE_LEAF_PREPROCESS=1
# only for local debugging (predictions will not match training otherwise).
_USE_LEAF_PREPROCESS = os.environ.get("DISABLE_LEAF_PREPROCESS", "").lower() not in (
    "1",
    "true",
    "yes",
)

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

print("Loading model...")
model = ViTForImageClassification.from_pretrained(str(_MODEL_DIR))
feature_extractor = AutoImageProcessor.from_pretrained(str(_MODEL_DIR))
model.eval()
print("Model ready.")


@app.get("/health")
def health():
    return {"status": "ok"}


def _bytes_to_model_input(raw: bytes) -> Image.Image:
    """Decode upload → training-aligned leaf stack → PIL RGB for ViTImageProcessor."""
    if _USE_LEAF_PREPROCESS:
        arr = np.frombuffer(raw, dtype=np.uint8)
        bgr = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if bgr is None:
            image = Image.open(io.BytesIO(raw)).convert("RGB")
            bgr = cv2.cvtColor(np.asarray(image), cv2.COLOR_RGB2BGR)
        stacked = preprocess_bgr_to_stacked(bgr, size=224)
        return Image.fromarray(stacked, mode="RGB")
    return Image.open(io.BytesIO(raw)).convert("RGB")


@app.post("/predict")
async def predict(file: UploadFile = File(...)):
    raw = await file.read()
    image = _bytes_to_model_input(raw)
    inputs = feature_extractor(images=image, return_tensors="pt")

    with torch.no_grad():
        outputs = model(**inputs)

    logits = outputs.logits
    predicted_class = logits.argmax(-1).item()
    label = model.config.id2label[predicted_class]
    probs = torch.softmax(logits, dim=-1)[0]
    confidence = probs[predicted_class].item()

    top3 = torch.topk(probs, min(3, len(probs)))
    top3_results = [
        {
            "disease": model.config.id2label[idx.item()],
            "confidence": round(score.item(), 4),
        }
        for score, idx in zip(top3.values, top3.indices)
    ]

    return {
        "disease": label,
        "confidence": round(confidence, 4),
        "top3": top3_results,
    }
