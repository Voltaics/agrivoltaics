import io
import torch
from google.cloud import storage
from config import Config


def model_blob_for_zone(cfg: Config) -> str:
    return f"{cfg.gcs_prefix}_zone_{cfg.zone_id}.pt"


def load_state(cfg: Config) -> dict | None:
    if not cfg.gcs_bucket:
        return None

    blob_name = model_blob_for_zone(cfg)
    if not blob_name:
        return None

    client = storage.Client(project=cfg.project_id)
    bucket = client.bucket(cfg.gcs_bucket)
    blob = bucket.blob(blob_name)

    if not blob.exists():
        return None

    data = blob.download_as_bytes()
    return torch.load(io.BytesIO(data), map_location="cpu")


def save_state(cfg: Config, state: dict) -> None:
    if not cfg.gcs_bucket:
        return

    blob_name = model_blob_for_zone(cfg)
    if not blob_name:
        return

    buf = io.BytesIO()
    torch.save(state, buf)
    buf.seek(0)

    client = storage.Client(project=cfg.project_id)
    bucket = client.bucket(cfg.gcs_bucket)
    blob = bucket.blob(blob_name)

    blob.upload_from_file(
        buf,
        rewind=True,
        content_type="application/octet-stream",
    )
