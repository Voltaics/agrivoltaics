from __future__ import annotations

import json
import os
import shutil
from pathlib import Path
from typing import Dict, Any

import align_images
import process_images_new
import run_inference
import firebase_upload


WORK_ROOT = Path(os.environ.get('WORK_ROOT', '/tmp/pipeline_work'))
WORK_ROOT.mkdir(parents=True, exist_ok=True)


def process_capture_folder(raw_input_dir: str | Path, capture_id: str, cleanup: bool = False) -> Dict[str, Any]:
    raw_input_dir = Path(raw_input_dir)
    job_root = WORK_ROOT / capture_id
    aligned_dir = job_root / 'aligned'
    processed_dir = job_root / 'processed'
    inference_dir = job_root / 'inference'

    for d in (aligned_dir, processed_dir, inference_dir):
        d.mkdir(parents=True, exist_ok=True)

    align_images.align_images(str(raw_input_dir), str(aligned_dir))
    process_images_new.create_combined_visualization(str(aligned_dir), str(processed_dir))
    inference_summary = run_inference.run_inference(
        input_folder=str(aligned_dir),
        output_folder=str(inference_dir),
    )

    upload_summary = firebase_upload.upload_capture_results(
        capture_id=capture_id,
        raw_folder=str(raw_input_dir),
        processed_folder=str(processed_dir),
        inference_folder=str(inference_dir),
        inference_summary=inference_summary,
    )

    result = {
        'capture_id': capture_id,
        'aligned_dir': str(aligned_dir),
        'processed_dir': str(processed_dir),
        'inference_dir': str(inference_dir),
        'inference_summary': inference_summary,
        'firebase_upload': upload_summary,
    }

    if cleanup:
        shutil.rmtree(job_root, ignore_errors=True)
        shutil.rmtree(raw_input_dir.parent, ignore_errors=True)
        result['cleanup'] = True
    else:
        result['cleanup'] = False

    return result
