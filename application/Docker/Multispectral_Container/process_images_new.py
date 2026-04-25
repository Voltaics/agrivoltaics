import argparse
import json
import os
from pathlib import Path

import cv2
import numpy as np
import tifffile as tiff


def read_tif_grayscale_u8(path):
    arr = tiff.imread(path)
    if arr.ndim == 3:
        if arr.shape[0] in (3, 4, 5, 6, 7) and arr.shape[0] < arr.shape[-1]:
            arr = arr[0]
        else:
            arr = arr.mean(axis=2)
    arr = arr.astype(np.float32)
    lo = np.percentile(arr, 1)
    hi = np.percentile(arr, 99)
    if hi <= lo:
        hi = lo + 1.0
    arr = np.clip(arr, lo, hi)
    arr = (arr - lo) / (hi - lo)
    return (arr * 255.0).astype(np.uint8)


def compute_ndvi(nir, red):
    return (nir.astype(np.float32) - red.astype(np.float32)) / (nir.astype(np.float32) + red.astype(np.float32) + 1e-6)


def compute_ndre(nir, rede):
    return (nir.astype(np.float32) - rede.astype(np.float32)) / (nir.astype(np.float32) + rede.astype(np.float32) + 1e-6)


def to_vis(arr_float):
    return ((arr_float + 1.0) / 2.0 * 255.0).clip(0, 255).astype(np.uint8)


def create_side_by_side_collage(image_paths, target_size=(400, 400), padding=10):
    images = [cv2.resize(read_tif_grayscale_u8(path), target_size) for path in image_paths]
    top_row = cv2.hconcat(images[:3])
    bottom_row = cv2.hconcat(images[3:])
    if top_row.shape[1] > bottom_row.shape[1]:
        diff = top_row.shape[1] - bottom_row.shape[1]
        bottom_row = cv2.copyMakeBorder(bottom_row, 0, 0, 0, diff, cv2.BORDER_CONSTANT, value=0)
    padding_array = np.full((padding, top_row.shape[1]), 0, dtype=np.uint8)
    return cv2.vconcat([top_row, padding_array, bottom_row])


def create_combined_visualization(input_folder, output_folder):
    input_folder = Path(input_folder)
    output_folder = Path(output_folder)
    output_folder.mkdir(parents=True, exist_ok=True)

    image_files = sorted([str(input_folder / f) for f in os.listdir(input_folder) if f.lower().endswith(('.tif', '.tiff'))])
    if len(image_files) < 5:
        raise ValueError(f'Not enough TIFF images in {input_folder}; found {len(image_files)}')

    capture_files = image_files[:5]
    collage = create_side_by_side_collage(capture_files)
    cv2.imwrite(str(output_folder / 'band_collage.jpg'), collage)

    target_size = (400, 400)
    blue = cv2.resize(read_tif_grayscale_u8(capture_files[0]), target_size)
    green = cv2.resize(read_tif_grayscale_u8(capture_files[1]), target_size)
    red = cv2.resize(read_tif_grayscale_u8(capture_files[2]), target_size)
    nir = cv2.resize(read_tif_grayscale_u8(capture_files[3]), target_size)
    rede = cv2.resize(read_tif_grayscale_u8(capture_files[4]), target_size)

    ndvi_float = compute_ndvi(nir, red)
    ndre_float = compute_ndre(nir, rede)
    cv2.imwrite(str(output_folder / 'ndvi.jpg'), to_vis(ndvi_float))
    cv2.imwrite(str(output_folder / 'ndre.jpg'), to_vis(ndre_float))
    np.save(output_folder / 'ndvi_float.npy', ndvi_float)
    np.save(output_folder / 'ndre_float.npy', ndre_float)

    stats = {
        'ndvi_stats': {
            'mean': float(ndvi_float.mean()),
            'std': float(ndvi_float.std()),
            'min': float(ndvi_float.min()),
            'max': float(ndvi_float.max()),
        },
        'ndre_stats': {
            'mean': float(ndre_float.mean()),
            'std': float(ndre_float.std()),
            'min': float(ndre_float.min()),
            'max': float(ndre_float.max()),
        },
    }
    with open(output_folder / 'spectral_stats.json', 'w', encoding='utf-8') as f:
        json.dump(stats, f, indent=2)

    return {
        'output_folder': str(output_folder),
        'files': ['band_collage.jpg', 'ndvi.jpg', 'ndre.jpg', 'ndvi_float.npy', 'ndre_float.npy', 'spectral_stats.json'],
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Generate preview and spectral derivative outputs from aligned TIFFs.')
    parser.add_argument('--folder', required=True, help='Aligned image folder')
    parser.add_argument('--output', required=True, help='Output folder')
    args = parser.parse_args()
    create_combined_visualization(args.folder, args.output)
