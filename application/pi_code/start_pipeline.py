import subprocess
import time
import threading
import queue
import os
import argparse

def parse_args():
    parser = argparse.ArgumentParser(description="Start the capture pipeline.")
    parser.add_argument('--mode', choices=['single', 'continuous'], default='single',
                        help="Set to 'single' for one capture or 'continuous' for looping.")
    return parser.parse_args()

CAPTURE_SCRIPT = "/application/pi_code/camera_data.py"
ALIGN_SCRIPT   = "/application/pi_code/align_images.py"
PROCESS_SCRIPT = "/application/pi_code/process_images_new.py"
UPLOAD_SCRIPT  = "/application/pi_code/firebase_upload.py"
INFERENCE_SCRIPT = "/application/pi_code/run_inference.py"

#Queue to pass capture folder paths from the capture thread to the processing thread
capture_queue = queue.Queue()

def capture_worker(mode):
    """Continuously run camera_data.py to capture images and put the capture folder path on the queue."""
    print("starting capture loop")
    while True:
        try:
            # Run camera_data.py and capture its output
            proc = subprocess.run(
                ["python3", CAPTURE_SCRIPT],
                capture_output=True,
                text=True,
                check=True
            )
            output = proc.stdout.strip().split("Images stored in ")[-1].strip()
            output = "Capture folder:" + output
            print("[Capture Worker] Raw output: ", output)
            # Look for the capture folder in the output. Expecting a line like:
            #"Capture folder: /home/hover-squad/senior_design/camera_images/capture_20230415_143200"
            if "Capture folder:" in output:
                folder = output.split("Capture folder:")[-1].strip()
                if os.path.exists(folder):
                    print(f"[Capture Worker] New capture folder detected: {folder}")
                    capture_queue.put(folder)
                else:
                    print("[Capture Worker] Capture folder not found:", folder)
            else:
                print("[Capture Worker] Could not determine capture folder from output.")
        except subprocess.CalledProcessError as e:
            print("[Capture Worker] Error during capture:", e)
        time.sleep(1)  #Adjust delay between captures

        if mode == "single":
            break
    
    print("finished capturing loop")

def processing_worker():
    """Take a capture folder from the queue, run alignment and processing scripts sequentially."""
    while True:
        try:
            capture_folder = capture_queue.get(timeout=10)
        except queue.Empty:
            continue

        print(f"[Processing Worker] Processing capture folder: {capture_folder}")
        #Run the alignment script with the capture folder as input.
        try:
            subprocess.run(
                ["python3", ALIGN_SCRIPT, "--folder", capture_folder],
                check=True
            )
        except subprocess.CalledProcessError as e:
            print("[Processing Worker] Alignment error:", e)
            capture_queue.task_done()
            continue

        #The aligned images are assumed to be stored in a corresponding subfolder under aligned_images.
        capture_name = os.path.basename(capture_folder)
        aligned_folder = os.path.join("/home/hover-squad/senior_design/aligned_images", capture_name)
        print(f"[Processing Worker] Aligned folder: {aligned_folder}")

        #Run the processing script on the aligned folder.
        try:
            subprocess.run(
                ["python3", PROCESS_SCRIPT, "--folder", aligned_folder],
                check=True
            )
        except subprocess.CalledProcessError as e:
            print("[Processing Worker] Processing error:", e)
        
        #classification

        processed_folder = os.path.join("/home/hover-squad/senior_design/processed_images", capture_name)
        try:
            subprocess.run(
                ["python3", INFERENCE_SCRIPT, "--folder", aligned_folder],
                check=True
            )
        except subprocess.CalledProcessError as e:
            print("[Processing Worker] Processing error:", e)

        processed_folder = os.path.join("/home/hover-squad/senior_design/processed_images", capture_name)
        try:
            subprocess.run(
                ["python3", UPLOAD_SCRIPT, "--folder", processed_folder],
                check=True
            )
        except subprocess.CalledProcessError as e:
            print("[Processing Worker] Upload error:", e)
        print(f"[Processing Worker] Processing complete for {capture_name}")
        
        capture_queue.task_done()

def main():
    args = parse_args()
    mode = args.mode

    print(f"Starting pipeline in {mode.upper()} mode\n")
    
    #Start the capture thread (daemon thread so it exits with the main process)
    cap_thread = threading.Thread(target=capture_worker, args=(mode,), daemon=True)
    cap_thread.start()
    print("[Main] Capture thread started.")
    
    #Start the processing worker thread
    proc_thread = threading.Thread(target=processing_worker, daemon=True)
    proc_thread.start()
    print("[Main] Processing worker thread started.")
    
    #Keep the main thread alive.
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[Main] Terminating pipeline...")

if __name__ == "__main__":
    main()
