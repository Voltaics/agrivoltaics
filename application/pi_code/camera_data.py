import requests
import time
import os
import subprocess

CAMERA_IP = "http://192.168.10.254"
DOWNLOAD_DIR = "/home/hover-squad/senior_design/camera_images"

if not os.path.exists(DOWNLOAD_DIR):
    #os.makedirs(DOWNLOAD_DIR)
    pass

def get_connection_status(timeout=30):
    status_url = f"{CAMERA_IP}/status"
    start_time = time.time()
    
    while True:
        try:
            response = requests.post(status_url)
            response.raise_for_status()
            data = response.json()
            print(f"status information: {data}")
        except Exception as e:
            print("status check failed:", e)
            return None
        if time.time() - start_time > timeout:
            print("Timeout waiting for status check.")
            break
        time.sleep(1)
    return None

def capture_image():
    capture_url = f"{CAMERA_IP}/capture"
    try:
        response = requests.post(capture_url)
        response.raise_for_status()
        data = response.json()
        print(f"Capture initiated: {data}")
        return data.get("id")
    except Exception as e:
        print("Capture failed:", e)
        return None

def wait_for_capture(image_id, timeout=30):
    capture_status_url = f"{CAMERA_IP}/capture/{image_id}"
    start_time = time.time()
    while True:
        try:
            response = requests.get(capture_status_url)
            response.raise_for_status()
            data = response.json()
            if data.get("status") == "complete":
                print("Capture complete.")
                return data
            else:
                print("Waiting for capture to complete...")
        except Exception as e:
            print("Error checking capture status:", e)
        if time.time() - start_time > timeout:
            print("Timeout waiting for capture completion.")
            break
        time.sleep(1)
    return None

def download_image(image_url, filename):
    try:
        response = requests.get(image_url)
        response.raise_for_status()
        with open(filename, "wb") as file:
            file.write(response.content)
        print(f"Image saved to {filename}")
    except Exception as e:
        print(f"Failed to download image from {image_url}:", e)

def run_capture_cycle():
    
    image_id = capture_image()
    if not image_id:
        return

    capture_data = wait_for_capture(image_id)
    if capture_data is None:
        print("Capture did not complete successfully.")
        return

    raw_cache_paths = capture_data.get("raw_cache_path", {})
    if not raw_cache_paths:
        print("No image paths found in capture data.")
        return
    
    #create subfolder for capture using timestamp
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    capture_folder = os.path.join(DOWNLOAD_DIR, f"capture_{timestamp}")
    os.makedirs(capture_folder, exist_ok=True)

    for key, path in raw_cache_paths.items():
        image_url = f"{CAMERA_IP}{path}"
        local_filename = os.path.join(capture_folder, os.path.basename(path))
        download_image(image_url, local_filename)

    print(f"capture cycle complete. Images stored in {capture_folder}")
    return capture_folder

def main():
    #input("Press Enter to trigger capture... ")
    #single capture cylce
    capture_folder = run_capture_cycle()
    #use this for continous capture
    #while (True):
    #    print("running capture cycle")
    #    run_capture_cycle()
    #
    #subprocess.run(["python3", "/home/hover-squad/senior_design/align_images.py", "--folder", capture_folder])

if __name__ == "__main__":
    main()
