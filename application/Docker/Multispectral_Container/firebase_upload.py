from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Dict, Any

import firebase_admin
from firebase_admin import credentials, firestore, storage


_APP = None


def get_firebase_app():
    global _APP
    if _APP is not None:
        return _APP

    bucket_name = os.environ.get('FIREBASE_STORAGE_BUCKET')
    cred_path = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')

    kwargs = {}
    if bucket_name:
        kwargs['storageBucket'] = bucket_name

    if cred_path:
        cred = credentials.Certificate(cred_path)
        _APP = firebase_admin.initialize_app(cred, kwargs)
    else:
        _APP = firebase_admin.initialize_app(options=kwargs)
    return _APP


def _upload_folder(bucket, local_folder: Path, remote_prefix: str) -> Dict[str, str]:
    urls = {}
    for path in sorted(local_folder.iterdir()):
        if not path.is_file():
            continue
        if path.suffix.lower() not in {'.jpg', '.jpeg', '.png', '.json'}:
            continue
        blob = bucket.blob(f'{remote_prefix}/{path.name}')
        blob.upload_from_filename(str(path))
        blob.make_public()
        urls[path.name] = blob.public_url
    return urls


def upload_capture_results(capture_id: str, raw_folder: str, processed_folder: str, inference_folder: str, inference_summary: Dict[str, Any]):
    get_firebase_app()
    db = firestore.client()
    bucket = storage.bucket()

    processed_folder = Path(processed_folder)
    inference_folder = Path(inference_folder)

    processed_urls = _upload_folder(bucket, processed_folder, f'captures/{capture_id}/processed')
    inference_urls = _upload_folder(bucket, inference_folder, f'captures/{capture_id}/inference')

    doc = {
        'capture_id': capture_id,
        'timestamp': firestore.SERVER_TIMESTAMP,
        'raw_folder_name': Path(raw_folder).name,
        'detected_disease': bool(inference_summary['disease_detected']),
        'analysis': inference_summary,
        'processed_urls': processed_urls,
        'inference_urls': inference_urls,
    }
    db.collection('captures').document(capture_id).set(doc)
    return {'firestore_document': f'captures/{capture_id}', 'processed_urls': processed_urls, 'inference_urls': inference_urls}
