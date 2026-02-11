import time
import os
import cv2
import numpy as np
from sklearn.decomposition import PCA
import argparse
import json
import tifffile as tiff

def read_tif_grayscale_u8(path):
    """
    Robust TIFF reader for 16-bit/32-bit/float TIFFs.
    Returns an 8-bit grayscale numpy array suitable for OpenCV resize/merge.
    """
    arr = tiff.imread(path)

    # If multi-channel, reduce to single channel
    if arr.ndim == 3:
        # common cases: (H,W,C) or (C,H,W)
        if arr.shape[0] in (3, 4, 5, 6, 7) and arr.shape[0] < arr.shape[-1]:
            # (C,H,W) -> take first channel
            arr = arr[0]
        else:
            # (H,W,C) -> average channels
            arr = arr.mean(axis=2)

    arr = arr.astype(np.float32)

    # Robust normalization to 0..255 (avoid outliers)
    lo = np.percentile(arr, 1)
    hi = np.percentile(arr, 99)
    if hi <= lo:
        hi = lo + 1.0

    arr = np.clip(arr, lo, hi)
    arr = (arr - lo) / (hi - lo)  # 0..1
    arr = (arr * 255.0).astype(np.uint8)
    return arr

def compute_ndvi(nir, red):
    #Compute NDVI = (NIR - Red) / (NIR + Red)
    #Returns an 8-bit image scaled to [0, 255].
    nir_f = nir.astype(np.float32)
    red_f = red.astype(np.float32)

    numerator = nir_f - red_f
    denominator = nir_f + red_f + 1e-6  #tiny offset to avoid division by zero
    ndvi = numerator / denominator  # Range ~ [-1, +1]

    #Map from [-1, +1] to [0, 255] for visualization
    ndvi_vis = ((ndvi + 1) / 2.0 * 255.0).astype(np.uint8)
    return ndvi_vis

def compute_ndre(nir, rede):
    #Compute NDRE = (NIR - RedEdge) / (NIR + RedEdge)
    #
    # Returns an 8-bit image scaled to [0, 255].
    nir_f = nir.astype(np.float32)
    rede_f = rede.astype(np.float32)

    numerator = nir_f - rede_f
    denominator = nir_f + rede_f + 1e-6
    ndre = numerator / denominator  #Range ~ [-1, +1]

    #Map from [-1, +1] to [0, 255]
    ndre_vis = ((ndre + 1) / 2.0 * 255.0).astype(np.uint8)
    return ndre_vis

def create_false_color(green, red, nir):
    #Create a false color composite using:
    #  - B = Green
    #  - G = Red
    #  - R = NIR
    #Returns a 3-channel color image.
    false_color = cv2.merge([green, red, nir])
    return false_color

def create_side_by_side_collage(image_paths, target_size=(400, 400), padding=10):
    """
    Places 5 grayscale images in a grid layout: 3 on top, 2 on bottom.
    Resizes them to target_size first, then concatenates.
    """
    images = [cv2.resize(read_tif_grayscale_u8(path), target_size) for path in image_paths]
   
    #Top row (3 images)
    top_row = cv2.hconcat(images[:3])
    #Bottom row (2 images)
    bottom_row = cv2.hconcat(images[3:])
   
    #If top is wider than bottom, pad the bottom
    if top_row.shape[1] > bottom_row.shape[1]:
        diff = top_row.shape[1] - bottom_row.shape[1]
        bottom_row = cv2.copyMakeBorder(bottom_row, 0, 0, 0, diff, cv2.BORDER_CONSTANT, value=0)
   
    #Vertical concat with a padding row between top and bottom
    padding_array = np.full((padding, top_row.shape[1]), 0, dtype=np.uint8)
    collage = cv2.vconcat([top_row, padding_array, bottom_row])
   
    return collage

def create_combined_visualization(input_folder, output_folder):
    #Get .tif images
    image_files = sorted([
        os.path.join(input_folder, f)
        for f in os.listdir(input_folder)
        if f.endswith(".tif")
    ])
   
    #Check if we have at least 5 bands
    if len(image_files) < 5:
        print("Not enough images to process.")
        return

    #[Blue, Green, Red, NIR, RedEdge]
    capture_files = image_files[:5]

    # Create collage for reference
    collage = create_side_by_side_collage(capture_files)
    collage_path = os.path.join(output_folder, "band_collage.jpg")
    cv2.imwrite(collage_path, collage)
    print(f"Saved collage to: {collage_path}")

    #Load and resize bands individually
    target_size = (400, 400)
    blue  = cv2.resize(read_tif_grayscale_u8(capture_files[0]), target_size)
    green = cv2.resize(read_tif_grayscale_u8(capture_files[1]), target_size)
    red   = cv2.resize(read_tif_grayscale_u8(capture_files[2]), target_size)
    nir   = cv2.resize(read_tif_grayscale_u8(capture_files[3]), target_size)
    rede  = cv2.resize(read_tif_grayscale_u8(capture_files[4]), target_size)


    #False color composite: (B=Green, G=Red, R=NIR)
    false_color = create_false_color(green, red, nir)
    false_path = os.path.join(output_folder, "false_color.jpg")
    #cv2.imwrite(false_path, false_color) don't need this image anymore
    #print(f"Saved false color image to: {false_path}")

    ndvi_image = compute_ndvi(nir, red)
    ndvi_path = os.path.join(output_folder, "ndvi.jpg")
    cv2.imwrite(ndvi_path, ndvi_image)
    print(f"Saved NDVI (8-bit) to: {ndvi_path}")

    #also store NDVI in float form
    # Re-run the same logic but keep the actual float array
    nir_f = nir.astype(np.float32)
    red_f = red.astype(np.float32)
    numerator = nir_f - red_f
    denominator = nir_f + red_f + 1e-6
    ndvi_float = numerator / denominator  # [-1..+1]
    ndvi_float_out = os.path.join(output_folder, "ndvi_float.npy")
    np.save(ndvi_float_out, ndvi_float)
    print(f"Saved NDVI (float) to: {ndvi_float_out}")

    ndre_image = compute_ndre(nir, rede)
    ndre_path = os.path.join(output_folder, "ndre.jpg")
    cv2.imwrite(ndre_path, ndre_image)
    print(f"Saved NDRE (8-bit) to: {ndre_path}")

    #also store NDRE float
    rede_f = rede.astype(np.float32)
    numerator_ndre = nir_f - rede_f
    denominator_ndre = nir_f + rede_f + 1e-6
    ndre_float = numerator_ndre / denominator_ndre  # [-1..+1]
    ndre_float_out = os.path.join(output_folder, "ndre_float.npy")
    np.save(ndre_float_out, ndre_float)
    print(f"Saved NDRE (float) to: {ndre_float_out}")

    def compute_stats(arr):
        return {
            "mean": float(arr.mean()),
            "std": float(arr.std()),
            "min": float(arr.min()),
            "max": float(arr.max())
        }

    ndvi_stats = compute_stats(ndvi_float)
    ndre_stats = compute_stats(ndre_float)
    stats_dict = {"ndvi_stats": ndvi_stats, "ndre_stats": ndre_stats}
    stats_json_path = os.path.join(output_folder, "spectral_stats.json")
    with open(stats_json_path, "w") as f:
        json.dump(stats_dict, f, indent=2)
    print(f"Saved NDVI/NDRE stats to: {stats_json_path}")

    print("All processing complete!")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Process aligned images for a capture")
    parser.add_argument("--folder", type=str, required=True,
                        help="Path to the aligned images folder for a capture")
    args = parser.parse_args()

    input_folder = args.folder
   
    base_processed_dir = "/home/hover-squad/senior_design/processed_images"

    timestamp = time.strftime("%Y%m%d_%H%M%S")
    output_folder = os.path.join(base_processed_dir, timestamp)
    os.makedirs(output_folder, exist_ok=True)

    if not os.path.exists(output_folder):
        os.makedirs(output_folder)

    create_combined_visualization(input_folder, output_folder)
