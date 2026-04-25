import argparse
import glob
import os

import cv2
import numpy as np
import tifffile as tiff


def _to_single_channel_float32(img: np.ndarray) -> np.ndarray:
    if img.ndim == 3:
        if img.shape[-1] == 1:
            img = img[:, :, 0]
        else:
            img = img[:, :, 0]
    return img.astype(np.float32)


def _to_uint8_for_orb(img: np.ndarray) -> np.ndarray:
    img = img.astype(np.float32)
    lo = float(np.percentile(img, 1))
    hi = float(np.percentile(img, 99))
    if hi <= lo:
        hi = lo + 1.0
    img = np.clip(img, lo, hi)
    img = (img - lo) / (hi - lo)
    return (img * 255.0).astype(np.uint8)


def align_images(input_folder: str, output_folder: str, reference_index: int = 2):
    image_paths = sorted(glob.glob(os.path.join(input_folder, '*.tif')) + glob.glob(os.path.join(input_folder, '*.tiff')))
    if len(image_paths) < 5:
        raise ValueError(f'Expected at least 5 TIFF images in {input_folder}, found {len(image_paths)}')

    images = [_to_single_channel_float32(tiff.imread(path)) for path in image_paths]
    images_uint8 = [_to_uint8_for_orb(img) for img in images]

    if reference_index >= len(images):
        raise IndexError(f'reference_index {reference_index} out of range for {len(images)} images')

    reference_image = images[reference_index]
    aligned_images = [None] * len(images)
    aligned_images[reference_index] = reference_image

    orb = cv2.ORB_create(5000)
    kp_ref, des_ref = orb.detectAndCompute(images_uint8[reference_index], None)
    if des_ref is None or len(kp_ref) < 4:
        raise RuntimeError('Could not find enough ORB features in reference image for alignment.')

    for i, img in enumerate(images):
        if i == reference_index:
            continue

        kp_img, des_img = orb.detectAndCompute(images_uint8[i], None)
        if des_img is None or len(kp_img) < 4:
            aligned_images[i] = img
            continue

        bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)
        matches = bf.match(des_img, des_ref)
        matches = sorted(matches, key=lambda x: x.distance)
        if len(matches) < 4:
            aligned_images[i] = img
            continue

        src_pts = np.float32([kp_img[m.queryIdx].pt for m in matches]).reshape(-1, 1, 2)
        dst_pts = np.float32([kp_ref[m.trainIdx].pt for m in matches]).reshape(-1, 1, 2)
        H, _ = cv2.findHomography(src_pts, dst_pts, cv2.RANSAC, 5.0)

        if H is None:
            aligned_images[i] = img
            continue

        aligned_images[i] = cv2.warpPerspective(img, H, (reference_image.shape[1], reference_image.shape[0]))

    os.makedirs(output_folder, exist_ok=True)
    for idx, img in enumerate(aligned_images):
        out_path = os.path.join(output_folder, f'aligned_band{idx + 1}.tif')
        tiff.imwrite(out_path, img.astype(np.float32))

    print(f'All bands aligned successfully into {output_folder}')
    return output_folder


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Align a raw multispectral capture folder into a target folder.')
    parser.add_argument('--folder', required=True, help='Raw capture folder containing TIFFs.')
    parser.add_argument('--output', required=True, help='Output folder for aligned TIFFs.')
    parser.add_argument('--reference-index', type=int, default=2, help='Band index to use as reference (default: 2 = red).')
    args = parser.parse_args()

    align_images(args.folder, args.output, reference_index=args.reference_index)
