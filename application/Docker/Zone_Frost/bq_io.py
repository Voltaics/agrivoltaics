from typing import Optional, Dict, Any
import pandas as pd
import numpy as np
from datetime import datetime
from google.cloud import bigquery
from config import Config


def bq_table(project: str, dataset: str, table: str) -> str:
    if "." in table:
        return f"`{project}.{table}`"
    return f"`{project}.{dataset}.{table}`"

def fetch_readings(bq: bigquery.Client, cfg: Config) -> pd.DataFrame:
    query = f"""
    SELECT
      timestamp,
      MAX(IF(field = "temperature", value, NULL)) AS temperature,
      MAX(IF(field = "humidity", value, NULL)) AS humidity,
      MAX(IF(field = "soilMoisture", value, NULL)) AS soilMoisture,
      MAX(IF(field = "soilTemperature", value, NULL)) AS soilTemperature,
      MAX(IF(field = "light", value, NULL)) AS light
    FROM {bq_table(cfg.project_id, cfg.dataset, cfg.readings_table)}
    WHERE
      timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL {cfg.lookback_hours} HOUR)
      AND field IN ("temperature", "humidity", "soilMoisture", "soilTemperature", "light")
      AND zoneId = @zoneId
    GROUP BY timestamp
    ORDER BY timestamp
    """
    job = bq.query(
        query,
        job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("zoneId", "STRING", cfg.zone_id)]
        ),
    )
    df = job.to_dataframe()
    if df.empty:
        raise RuntimeError("No sensor data returned for this zone in the lookback window.")
    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True)
    return df


def fetch_prediction_near_time(
    bq: bigquery.Client,
    cfg: Config,
    target_time_utc: pd.Timestamp,
    tolerance_minutes: int = 20,
) -> Optional[Dict[str, Any]]:
    """
    Fetch the prediction row closest to target_time_utc (within tolerance),
    but ONLY if it has not yet been resolved (trained_on_label IS NULL).
    """
    start = target_time_utc - pd.Timedelta(minutes=tolerance_minutes)
    end = target_time_utc + pd.Timedelta(minutes=tolerance_minutes)

    query = f"""
    SELECT *
    FROM {bq_table(cfg.project_id, cfg.dataset, cfg.predictions_table)}
    WHERE zoneId = @zoneId
      AND timestamp BETWEEN @start AND @end
      AND trained_on_label IS NULL
    ORDER BY ABS(TIMESTAMP_DIFF(timestamp, @target, SECOND)) ASC
    LIMIT 1
    """

    job = bq.query(
        query,
        job_config=bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("zoneId", "STRING", cfg.zone_id),
                bigquery.ScalarQueryParameter("start", "TIMESTAMP", start.to_pydatetime()),
                bigquery.ScalarQueryParameter("end", "TIMESTAMP", end.to_pydatetime()),
                bigquery.ScalarQueryParameter("target", "TIMESTAMP", target_time_utc.to_pydatetime()),
            ]
        ),
    )

    df = job.to_dataframe()
    if df.empty:
        return None

    row = df.iloc[0].to_dict()
    row["timestamp"] = pd.to_datetime(row["timestamp"], utc=True)
    return row


def fetch_candle_events(bq: bigquery.Client, cfg: Config, hours: int = 6) -> pd.DataFrame:
    query = f"""
    SELECT timestamp, candlesOn
    FROM {bq_table(cfg.project_id, cfg.dataset, cfg.interventions_table)}
    WHERE zoneId = @zoneId
      AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL {hours} HOUR)
    ORDER BY timestamp
    """
    job = bq.query(
        query,
        job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("zoneId", "STRING", cfg.zone_id)]
        ),
    )
    df = job.to_dataframe()
    if df.empty:
        return pd.DataFrame(columns=["timestamp", "candlesOn"])
    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True)
    df["candlesOn"] = df["candlesOn"].astype(bool)
    return df


def latest_candles_on(candle_df: pd.DataFrame, t_utc: pd.Timestamp) -> bool:
    if candle_df.empty:
        return False
    past = candle_df[candle_df["timestamp"] <= t_utc]
    if past.empty:
        return False
    return bool(past.iloc[-1]["candlesOn"])


def candles_on_during_window(candle_df: pd.DataFrame, start: pd.Timestamp, end: pd.Timestamp) -> bool:
    if candle_df.empty:
        return False

    past = candle_df[candle_df["timestamp"] <= start]
    state_at_start = bool(past.iloc[-1]["candlesOn"]) if not past.empty else False

    window_events = candle_df[(candle_df["timestamp"] >= start) & (candle_df["timestamp"] <= end)]
    if state_at_start:
        return True
    if not window_events.empty and window_events["candlesOn"].any():
        return True
    return False

def _jsonify_row(row: dict) -> dict:
    out = {}
    for k, v in row.items():
        if isinstance(v, datetime):
            out[k] = v.isoformat()
        elif isinstance(v, (np.floating, np.integer)):
            out[k] = v.item()
        else:
            out[k] = v
    return out

def insert_prediction_row(bq: bigquery.Client, cfg: Config, row: dict) -> None:
    table_id = f"{cfg.project_id}.{cfg.dataset}.{cfg.predictions_table}" if "." not in cfg.predictions_table else f"{cfg.project_id}.{cfg.predictions_table}"
    json_row = _jsonify_row(row)
    errors = bq.insert_rows_json(table_id, [json_row])
    if errors:
        raise RuntimeError(f"BigQuery insert errors: {errors}")


def has_processed_ingest(bq: bigquery.Client, cfg: Config) -> bool:
    if not cfg.ingest_id:
        return False

    query = f"""
    SELECT 1
    FROM {bq_table(cfg.project_id, cfg.dataset, cfg.predictions_table)}
    WHERE zoneId = @zoneId
    AND ingest_id = @ingest_id
    AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    LIMIT 1
    """
    job = bq.query(
        query,
        job_config=bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("zoneId", "STRING", cfg.zone_id),
                bigquery.ScalarQueryParameter("ingest_id", "STRING", cfg.ingest_id),
            ]
        ),
    )
    df = job.to_dataframe()
    return not df.empty


def fetch_untrained_matured_predictions(
    bq: bigquery.Client,
    cfg: Config,
    now: pd.Timestamp,
    limit: int = 50,
) -> pd.DataFrame:
    query = f"""
    SELECT *
    FROM {bq_table(cfg.project_id, cfg.dataset, cfg.predictions_table)}
    WHERE zoneId = @zoneId
      AND trained_on_label IS NULL
      AND timestamp <= TIMESTAMP_SUB(@now, INTERVAL {cfg.horizon_minutes} MINUTE)
    ORDER BY timestamp ASC
    LIMIT {limit}
    """
    job = bq.query(
        query,
        job_config=bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("zoneId", "STRING", cfg.zone_id),
                bigquery.ScalarQueryParameter("now", "TIMESTAMP", now.to_pydatetime()),
            ]
        ),
    )
    df = job.to_dataframe()
    if df.empty:
        return df
    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True)
    return df


def update_prediction_training_status(
    bq: bigquery.Client,
    cfg: Config,
    pred_timestamp_utc: pd.Timestamp,
    trained_on_label: bool,
    skipped_reason: str | None,
    label_frost_observed: int | None,
    label_window_start_utc: pd.Timestamp | None,
    label_window_end_utc: pd.Timestamp | None,
) -> None:
    query = f"""
    UPDATE {bq_table(cfg.project_id, cfg.dataset, cfg.predictions_table)}
    SET
      trained_on_label = @trained_on_label,
      skipped_reason = @skipped_reason,
      label_frost_observed = @label_frost_observed,
      label_window_start = @label_window_start,
      label_window_end = @label_window_end
    WHERE zoneId = @zoneId
      AND timestamp = @pred_ts
    """
    job = bq.query(
        query,
        job_config=bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("trained_on_label", "BOOL", trained_on_label),
                bigquery.ScalarQueryParameter("skipped_reason", "STRING", skipped_reason),
                bigquery.ScalarQueryParameter("label_frost_observed", "INT64", label_frost_observed),
                bigquery.ScalarQueryParameter(
                    "label_window_start",
                    "TIMESTAMP",
                    label_window_start_utc.to_pydatetime() if label_window_start_utc is not None else None,
                ),
                bigquery.ScalarQueryParameter(
                    "label_window_end",
                    "TIMESTAMP",
                    label_window_end_utc.to_pydatetime() if label_window_end_utc is not None else None,
                ),
                bigquery.ScalarQueryParameter("zoneId", "STRING", cfg.zone_id),
                bigquery.ScalarQueryParameter("pred_ts", "TIMESTAMP", pred_timestamp_utc.to_pydatetime()),
            ]
        ),
    )
    job.result()  # wait; raises on failure

