# Preprocessing (from leaf_preprocess.py) — operates on BGR uint8 images (OpenCV).

from __future__ import annotations

import cv2
import numpy as np

# ════════════════════════════════════════════════════════════════════════════
# Constants
# ════════════════════════════════════════════════════════════════════════════

LESION_HSV_LOWER = np.array([5, 60, 60])
LESION_HSV_UPPER = np.array([30, 255, 200])
DARK_MARK_LOWER = np.array([0, 0, 0])
DARK_MARK_UPPER = np.array([180, 80, 60])
MIN_LESION_AREA = 20


def _leaf_mask(bgr: np.ndarray) -> np.ndarray:
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    m = cv2.inRange(hsv, np.array([25, 30, 30]), np.array([95, 255, 255]))
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, k, iterations=3)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, k, iterations=2)
    return m


def _edges(bgr: np.ndarray, mask: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (3, 3), 0)
    e = cv2.Canny(blur, 30, 100)
    return cv2.bitwise_and(e, e, mask=mask)


def _lesions(bgr: np.ndarray, mask: np.ndarray) -> np.ndarray:
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    m = cv2.inRange(hsv, LESION_HSV_LOWER, LESION_HSV_UPPER)
    m = cv2.bitwise_and(m, m, mask=mask)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, k)
    cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    out = np.zeros_like(m)
    for c in cnts:
        if cv2.contourArea(c) >= MIN_LESION_AREA:
            cv2.drawContours(out, [c], -1, 255, -1)
    return out


def _dark_marks(bgr: np.ndarray, mask: np.ndarray) -> np.ndarray:
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    m = cv2.inRange(hsv, DARK_MARK_LOWER, DARK_MARK_UPPER)
    m = cv2.bitwise_and(m, m, mask=mask)
    cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    out = np.zeros_like(m)
    for c in cnts:
        a = cv2.contourArea(c)
        if MIN_LESION_AREA <= a <= 500:
            cv2.drawContours(out, [c], -1, 255, -1)
    return out


def preprocess_bgr_to_stacked(bgr: np.ndarray, size: int = 224) -> np.ndarray:
    """
    Return a (size, size, 3) uint8 array where:
      - channel 0: grayscale of original (normalised texture)
      - channel 1: lesion + dark-mark binary mask (disease signal)
      - channel 2: edge map (leaf structure)

    Compatible with ViT 3-channel input; stack is treated as RGB by the image processor.
    """
    if bgr is None or bgr.ndim != 3 or bgr.shape[2] != 3:
        raise ValueError("expected BGR image with shape (H, W, 3)")

    lm = _leaf_mask(bgr)
    e = _edges(bgr, lm)
    les = _lesions(bgr, lm)
    dm = _dark_marks(bgr, lm)

    disease = cv2.bitwise_or(les, dm)
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)

    stacked = np.stack([gray, disease, e], axis=-1)
    stacked = cv2.resize(stacked, (size, size), interpolation=cv2.INTER_AREA)
    return stacked.astype(np.uint8)


def preprocess_to_rgb(image_path: str, size: int = 224) -> np.ndarray:
    """Load from disk (same behaviour as original leaf_preprocess.py)."""
    bgr = cv2.imread(image_path)
    if bgr is None:
        raise FileNotFoundError(image_path)
    return preprocess_bgr_to_stacked(bgr, size=size)
