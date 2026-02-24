import json
import numpy as np
import pandas as pd
import torch
import torch.nn.functional as F
from datetime import datetime, timezone
from google.cloud import bigquery

from config import load_config, Config
from model import FrostMLP
from features import resample_to_grid, build_features, compute_label_frost_in_window
from bq_io import (
    fetch_readings,
    fetch_untrained_matured_predictions,
    fetch_candle_events,
    latest_candles_on,
    candles_on_during_window,
    insert_prediction_row,
    has_processed_ingest,
    update_prediction_training_status,
)
from state import load_state, save_state


def required_steps(lookback_hours: int, interval_minutes: int) -> int:
    return int((lookback_hours * 60) / interval_minutes)


def has_enough_history(grid_df: pd.DataFrame, cfg: Config) -> tuple[bool, str | None]:
    need = required_steps(cfg.lookback_hours, cfg.interval_minutes)
    if len(grid_df) < need:
        return False, f"need_{need}_bins_have_{len(grid_df)}"

    tail = grid_df.tail(need)

    # Require at least some real temp values (not all NaN)
    if tail["temperature"].isna().all():
        return False, "temperature_all_nan"

    need_span = pd.Timedelta(hours=cfg.lookback_hours)
    if (grid_df["timestamp"].max() - grid_df["timestamp"].min()) < need_span * 0.95:
        return False, "insufficient_timespan"

    return True, None


def main():
    cfg = load_config()
    bq = bigquery.Client(project=cfg.project_id)

    # Idempotency guard by ingest_id
    if cfg.ingest_id and has_processed_ingest(bq, cfg):
        print(f"Ingest {cfg.ingest_id} already processed for zone {cfg.zone_id}, skipping.")
        return

    torch.manual_seed(cfg.seed)
    np.random.seed(cfg.seed)

    readings = fetch_readings(bq, cfg)
    candles = fetch_candle_events(bq, cfg, hours=6)

    # Use most recent reading as "now"
    now = pd.Timestamp(readings["timestamp"].max()).tz_convert("UTC")

    # Resample to fixed grid for feature building + history checks
    grid = resample_to_grid(readings, cfg.interval_minutes)

    ok, why_not = has_enough_history(grid, cfg)
    if not ok:
        # Not enough history to make a meaningful prediction; log a row and exit
        pred_row = {
            "timestamp": now.to_pydatetime(),
            "zoneId": cfg.zone_id,
            "probability": -1.0,
            "probability_percent": -1.0,
            "model_version": cfg.model_version,
            "features_hash": None,
            "trained_on_label": False,
            "label_frost_observed": None,
            "label_window_start": None,
            "label_window_end": None,
            "skipped_reason": f"insufficient_history:{why_not}",
            "ingest_id": cfg.ingest_id,
            "triggered_at": datetime.now(timezone.utc),
        }
        insert_prediction_row(bq, cfg, pred_row)
        return

    n_steps = int(cfg.lookback_hours * 60 / cfg.interval_minutes)

    # Build "current" feature vector (this is for the NEW prediction we will insert at the end)
    candle_now = latest_candles_on(candles, now)
    x_np, features_hash = build_features(grid.tail(n_steps), candle_now)

    # Model + optimizer
    model = FrostMLP(input_dim=x_np.shape[0])
    opt = torch.optim.AdamW(model.parameters(), lr=cfg.lr, weight_decay=cfg.weight_decay)

    # Load persisted state (weights/optimizer)
    state = load_state(cfg)
    if state:
        try:
            model.load_state_dict(state["model"])
            opt.load_state_dict(state["opt"])
        except Exception as e:
            print(f"WARNING: could not load persisted model/optimizer state (starting fresh): {e}")

    model.train()

    # Learn from any mature prediction not yet trained on
    backlog = fetch_untrained_matured_predictions(bq, cfg, now, limit=50)

    trained_count = 0
    skipped_count = 0

    for _, prev_pred in backlog.iterrows():
        pred_time = pd.Timestamp(prev_pred["timestamp"]).tz_convert("UTC")
        label_start = pred_time
        label_end = pred_time + pd.Timedelta(minutes=cfg.horizon_minutes)

        # If candles were active in the label window -> mark as resolved (FALSE) w/ reason
        if candles_on_during_window(candles, label_start, label_end):
            update_prediction_training_status(
                bq=bq,
                cfg=cfg,
                pred_timestamp_utc=pred_time,
                trained_on_label=False,
                skipped_reason="frost candles deployed",
                label_frost_observed=None,
                label_window_start_utc=label_start,
                label_window_end_utc=label_end,
            )
            skipped_count += 1
            continue

        # Compute label from realized temps in the future window
        label_val = compute_label_frost_in_window(
            readings, label_start, label_end, cfg.frost_temp_threshold
        )
        if label_val is None:
            update_prediction_training_status(
                bq=bq,
                cfg=cfg,
                pred_timestamp_utc=pred_time,
                trained_on_label=False,
                skipped_reason="insufficient_label_data",
                label_frost_observed=None,
                label_window_start_utc=label_start,
                label_window_end_utc=label_end,
            )
            skipped_count += 1
            continue

        # Rebuild features "as of" label_start
        hist = readings[readings["timestamp"] <= label_start].copy()
        hist_grid = resample_to_grid(hist, cfg.interval_minutes)

        ok_hist, why_not_hist = has_enough_history(hist_grid, cfg)
        if not ok_hist:
            update_prediction_training_status(
                bq=bq,
                cfg=cfg,
                pred_timestamp_utc=pred_time,
                trained_on_label=False,
                skipped_reason=f"insufficient_history_for_training:{why_not_hist}",
                label_frost_observed=int(label_val),
                label_window_start_utc=label_start,
                label_window_end_utc=label_end,
            )
            skipped_count += 1
            continue

        candle_at_pred_time = latest_candles_on(candles, label_start)
        x_prev_np, _ = build_features(hist_grid.tail(n_steps), candle_at_pred_time)

        # Ensure float32 tensors (avoids silent float64 usage)
        x_prev = torch.from_numpy(x_prev_np.astype(np.float32)).unsqueeze(0)
        y = torch.tensor([[float(label_val)]], dtype=torch.float32)

        opt.zero_grad()
        logits = model(x_prev)
        loss = F.binary_cross_entropy_with_logits(logits, y)
        loss.backward()
        opt.step()

        # Mark this prediction row as trained successfully
        update_prediction_training_status(
            bq=bq,
            cfg=cfg,
            pred_timestamp_utc=pred_time,
            trained_on_label=True,
            skipped_reason=None,
            label_frost_observed=int(label_val),
            label_window_start_utc=label_start,
            label_window_end_utc=label_end,
        )
        trained_count += 1

    # Make prediction
    model.eval()
    with torch.no_grad():
        x = torch.from_numpy(x_np.astype(np.float32)).unsqueeze(0)
        prob = torch.sigmoid(model(x)).item()

    prob_pct = float(prob * 100.0)

    # Insert a new prediction row that is always unresolved initially
    pred_row = {
        "timestamp": now.to_pydatetime(),
        "zoneId": cfg.zone_id,
        "probability": float(prob),
        "probability_percent": prob_pct,
        "model_version": cfg.model_version,
        "features_hash": features_hash,
        "trained_on_label": None,
        "label_frost_observed": None,
        "label_window_start": None,
        "label_window_end": None,
        "skipped_reason": None,

        "ingest_id": cfg.ingest_id,
        "triggered_at": datetime.now(timezone.utc),
    }

    insert_prediction_row(bq, cfg, pred_row)

    # Save state AFTER training + new prediction, if training occurred.
    if trained_count > 0:
        save_state(cfg, {"model": model.state_dict(), "opt": opt.state_dict(), "version": cfg.model_version})

    print(json.dumps({
        "zoneId": cfg.zone_id,
        "timestamp": now.isoformat(),
        "probability_percent": prob_pct,
        "backlog_trained": trained_count,
        "backlog_skipped": skipped_count,
    }, indent=2))


if __name__ == "__main__":
    main()
