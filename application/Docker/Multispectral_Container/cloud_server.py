from __future__ import annotations

import json
import os
import shutil
import tempfile
import uuid
from pathlib import Path
from typing import Dict, List

from flask import Flask, jsonify, request
from werkzeug.utils import secure_filename

from pipeline_runner import process_capture_folder

app = Flask(__name__)

ALLOWED_EXTENSIONS = {'.tif', '.tiff'}
CAPTURE_ROOT = Path(os.environ.get('CAPTURE_ROOT', '/tmp/captures'))
CAPTURE_ROOT.mkdir(parents=True, exist_ok=True)


def _is_allowed(filename: str) -> bool:
    return Path(filename).suffix.lower() in ALLOWED_EXTENSIONS


def _save_uploaded_files(files) -> tuple[str, Path, List[str]]:
    capture_id = request.form.get('capture_id') or f"capture_{uuid.uuid4().hex[:12]}"
    capture_dir = CAPTURE_ROOT / capture_id / 'raw'
    capture_dir.mkdir(parents=True, exist_ok=True)

    saved = []
    for f in files:
        if not f or not f.filename:
            continue
        filename = secure_filename(f.filename)
        if not _is_allowed(filename):
            continue
        out_path = capture_dir / filename
        f.save(out_path)
        saved.append(filename)

    return capture_id, capture_dir, saved


@app.get('/healthz')
def healthz():
    return jsonify({'ok': True})


@app.post('/process-capture')
def process_capture():
    print("Received /process-capture request")
    uploaded = request.files.getlist('files')
    if not uploaded:
        return jsonify({'error': 'No files uploaded. Use multipart/form-data with repeated field name "files".'}), 400

    capture_id, raw_dir, saved = _save_uploaded_files(uploaded)
    if len(saved) < 5:
        shutil.rmtree(raw_dir.parent, ignore_errors=True)
        return jsonify({'error': f'Expected at least 5 TIFF files, got {len(saved)}', 'saved_files': saved}), 400

    try:
        result = process_capture_folder(
            raw_input_dir=raw_dir,
            capture_id=capture_id,
            cleanup=os.environ.get('CLEANUP_AFTER_UPLOAD', 'false').lower() == 'true',
        )
        return jsonify(result), 200
    except Exception as exc:
        return jsonify({'error': str(exc), 'capture_id': capture_id}), 500


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', '8080')))
