from __future__ import annotations

import argparse
import os
from pathlib import Path

import requests

import camera_data


def parse_args():
    p = argparse.ArgumentParser(description='Capture images on the Pi and upload them to the cloud inference service.')
    p.add_argument('--cloud-url', required=True, help='Base URL of the cloud service, e.g. https://my-service-abc-uc.a.run.app')
    p.add_argument('--capture-id', default=None, help='Optional capture id to send to the server')
    p.add_argument('--timeout', type=int, default=600)
    return p.parse_args()


def upload_capture_folder(cloud_url: str, folder: str, capture_id: str | None = None, timeout: int = 600):
    folder_path = Path(folder)
    tif_files = sorted([p for p in folder_path.iterdir() if p.suffix.lower() in ['.tif', '.tiff']])
    if len(tif_files) < 5:
        raise RuntimeError(f'Expected at least 5 tif files in {folder}, found {len(tif_files)}')

    files = [('files', (p.name, open(p, 'rb'), 'image/tiff')) for p in tif_files]
    data = {}
    print(f"Found {len(tif_files)} tif files, starting upload to {cloud_url}")
    if capture_id:
        data['capture_id'] = capture_id

    try:
        resp = requests.post(f"{cloud_url.rstrip('/')}/process-capture", files=files, data=data, timeout=timeout)
        resp.raise_for_status()
        return resp.json()
    finally:
        for _, (name, fh, _) in files:
            fh.close()


def main():
    args = parse_args()
    capture_folder = camera_data.run_capture_cycle()
    if not capture_folder:
        raise RuntimeError('Capture failed; no folder was produced.')

    print(f"Uploading capture from {capture_folder} to {args.cloud_url} with capture_id={args.capture_id} and timeout={args.timeout}s...")
    result = upload_capture_folder(args.cloud_url, capture_folder, capture_id=args.capture_id, timeout=args.timeout)
    print("Server responded:")
    print(result)


if __name__ == '__main__':
    main()
