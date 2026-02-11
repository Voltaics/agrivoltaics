import cv2
import tifffile as tiff
import numpy as np
import glob
import os
import argparse

def align_images(input_folder,  output_folder):

    image_paths = sorted(glob.glob(os.path.join(input_folder, "*.tif")))
    if len(image_paths) == 0:
        print("No images in the input folder.")
        return

    images = [tiff.imread(path).astype(np.float32) for path in image_paths]
    

    # Ensure single-channel for ORB
    images_for_orb = []
    for img in images:
        if img.ndim == 3:
            images_for_orb.append(img[:, :, 0])  # take first channel
        else:
            images_for_orb.append(img)

    # Convert to uint8 for ORB
    images_uint8 = [
        np.uint8(255 * (img - img.min()) / (img.max() - img.min() + 1e-8))
        for img in images_for_orb
    ]




    #Choose the middle band as the reference (adjust index as needed)
    reference_index = 2
    reference_image = images[reference_index]

    aligned_images = [reference_image]  # Store aligned images

    #Use ORB for feature detection & matching
    orb = cv2.ORB_create(5000)

    kp_ref, des_ref = orb.detectAndCompute(images_uint8[reference_index], None)

    for i, img in enumerate(images):
        if i == reference_index:
            continue  #Skip reference image

        #Detect keypoints and compute descriptors
        kp_img, des_img = orb.detectAndCompute(images_uint8[i], None)

        #Use BFMatcher to find feature matches
        bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)
        matches = bf.match(des_img, des_ref)
        matches = sorted(matches, key=lambda x: x.distance)

        #Extract matched keypoints
        src_pts = np.float32([kp_img[m.queryIdx].pt for m in matches]).reshape(-1, 1, 2)
        dst_pts = np.float32([kp_ref[m.trainIdx].pt for m in matches]).reshape(-1, 1, 2)

        #Compute Homography matrix
        H, _ = cv2.findHomography(src_pts, dst_pts, cv2.RANSAC, 5.0)

        #Warp the image to align with the reference
        aligned = cv2.warpPerspective(img, H, (reference_image.shape[1], reference_image.shape[0]))

        aligned_images.append(aligned)

    os.makedirs(output_folder, exist_ok=True)
    #Save the aligned images
    for idx, img in enumerate(aligned_images):
        cv2.imwrite(os.path.join(output_folder, f"aligned_band{idx+1}.tif"), img)

    print("All bands aligned successfully.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Align images from a capture folder.")
    parser.add_argument("--folder", type=str, required=True, help="Path to the capture folder containing images.")
    args = parser.parse_args()
    
    input_folder = args.folder
    #Create a corresponding aligned folder (e.g., aligned_images/capture_<timestamp>)
    base_aligned_dir = r"F:\Documents\Things\school work\Senior Design\test_inference_data\aligned_images"
    capture_name = os.path.basename(input_folder)
    output_folder = os.path.join(base_aligned_dir, capture_name)
    
    align_images(input_folder, output_folder)