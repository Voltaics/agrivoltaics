import pandas as pd
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
      MAX(IF(field = "soilTemperature", value, NULL)) AS soilTemperature
    FROM {bq_table(cfg.project_id, cfg.dataset, cfg.readings_table)}
    WHERE
      timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL {cfg.lookback_hours} HOUR)
      AND field IN ("temperature", "humidity", "soilMoisture", "soilTemperature")
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


def insert_prediction_row(bq: bigquery.Client, cfg: Config, row: dict) -> None:
    table_id = f"{cfg.project_id}.{cfg.dataset}.{cfg.predictions_table.split('.')[-1]}"
    errors = bq.insert_rows_json(table_id, [row])
    if errors:
        raise RuntimeError(f"BigQuery insert errors: {errors}")


def has_processed_ingest(bq: bigquery.Client, cfg: Config) -> bool:
    if not cfg.ingest_id:
        return False

    query = f"""
    SELECT 1
    FROM {bq_table(cfg.project_id, cfg.dataset, cfg.predictions_table)}
    WHERE zoneId = @zoneId AND ingest_id = @ingest_id
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


def fetch_prediction_near_time(
    bq: bigquery.Client,
    cfg: Config,
    target: pd.Timestamp,
    tolerance_minutes: int = 20,
) -> dict | None:
    query = f"""
    SELECT *
    FROM {bq_table(cfg.project_id, cfg.dataset, cfg.predictions_table)}
    WHERE zoneId = @zoneId
      AND timestamp BETWEEN TIMESTAMP_SUB(@t, INTERVAL {tolerance_minutes} MINUTE)
                        AND TIMESTAMP_ADD(@t, INTERVAL {tolerance_minutes} MINUTE)
    ORDER BY ABS(TIMESTAMP_DIFF(timestamp, @t, SECOND))
    LIMIT 1
    """
    job = bq.query(
        query,
        job_config=bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("zoneId", "STRING", cfg.zone_id),
                bigquery.ScalarQueryParameter("t", "TIMESTAMP", target.to_pydatetime()),
            ]
        ),
    )
    df = job.to_dataframe()
    if df.empty:
        return None
    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True)
    return df.iloc[0].to_dict()
