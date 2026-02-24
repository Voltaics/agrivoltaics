import os
from dataclasses import dataclass

@dataclass
class Config:
    project_id: str
    dataset: str
    readings_table: str
    predictions_table: str
    interventions_table: str

    zone_id: str
    frost_temp_threshold: float

    lookback_hours: int = 24 * 3  # 3 days
    interval_minutes: int = 15
    horizon_minutes: int = 60 * 6  # 6 hours

    lr: float = 1e-3
    weight_decay: float = 1e-6
    model_version: str = "mlp_v1"
    seed: int = 42

    gcs_bucket: str | None = None
    gcs_prefix: str | None = None
    ingest_id: str | None = None


def load_config() -> Config:
    def req(name: str) -> str:
        v = os.getenv(name)
        if not v:
            raise RuntimeError(f"Missing required env var: {name}")
        return v

    return Config(
        project_id=req("BQ_PROJECT_ID"),
        dataset=req("BQ_DATASET"),
        readings_table=req("BQ_READINGS_TABLE"),
        predictions_table=req("BQ_PREDICTIONS_TABLE"),
        interventions_table=req("BQ_INTERVENTIONS_TABLE"),
        zone_id=req("ZONE_ID"),
        frost_temp_threshold=float(os.getenv("FROST_TEMP_THRESHOLD", "32.0")),
        gcs_bucket=os.getenv("MODEL_GCS_BUCKET"),
        gcs_prefix=os.getenv("MODEL_GCS_PREFIX"),
        lr=float(os.getenv("LR", "0.001")),
        weight_decay=float(os.getenv("WEIGHT_DECAY", "1e-6")),
        model_version=os.getenv("MODEL_VERSION", "mlp_v1"),
        ingest_id=os.getenv("INGEST_ID"),
    )
