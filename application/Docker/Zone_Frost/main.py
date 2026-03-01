import json
from arrow import now
from arrow import now
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

# minimum fraction of real bins required to train
COVERAGE_THRESHOLD = 0.75

# reject if a streak of missing bins exceeds this limit
# 8 bins * 15 minutes = 2 hours of missing data
MAX_GAP_BINS = 8

def required_steps(lookback_hours: int, interval_minutes: int) -> int:
    # Must be integer (your config is compatible: 72h & 15m => 288)
    return int((lookback_hours * 60) / interval_minutes)

def _gap_skip_reason(prefix: str, meta: dict) -> str:
    return (
        f"{prefix}:"
        f"max_gap_{meta['max_gap_bins']}_bins"
        f"({meta['max_gap_minutes']}min)_exceeds_{MAX_GAP_BINS}_bins"
        f"_needed_{meta['needed_points']}"
        f"_real_{meta['real_points']}"
        f"({meta['coverage_pct']:.1f}%)"
    )

def _coverage_skip_reason(prefix: str, meta: dict) -> str:
    # Example: "insufficient_real_points_for_training:real_250_of_288(86.8%)"
    return (
        f"{prefix}:"
        f"real_{meta['real_points']}_of_{meta['needed_points']}"
        f"({meta['coverage_pct']:.1f}%)"
    )


def main():
    cfg = load_config()
    bq = bigquery.Client(project=cfg.project_id)

    # Idempotency guard by ingest_id
    if cfg.ingest_id and has_processed_ingest(bq, cfg):
        print(f"Ingest {cfg.ingest_id} already processed for zone {cfg.zone_id}, skipping.")
        return

    torch.manual_seed(cfg.seed)
    np.random.seed(cfg.seed)

    # 1) Use wall-clock just to discover backlog + decide how far back to query
    wall_now = pd.Timestamp.utcnow().tz_localize("UTC")
    backlog = fetch_untrained_matured_predictions(bq, cfg, wall_now, limit=50)

    # 2) Compute earliest start needed to cover feature windows for backlog
    if not backlog.empty:
        earliest_pred = pd.to_datetime(backlog["timestamp"].min(), utc=True)
        start_utc = (
            earliest_pred
            - pd.Timedelta(hours=cfg.lookback_hours)
            - pd.Timedelta(minutes=cfg.interval_minutes)
        )
    else:
        start_utc = (
            wall_now
            - pd.Timedelta(hours=cfg.lookback_hours)
            - pd.Timedelta(minutes=cfg.interval_minutes)
        )

    # 3) Fetch readings over the correct span (end at wall-clock now for safety)
    readings = fetch_readings(bq, cfg, start_utc=start_utc, end_utc=wall_now)

    # 4) Define model "now" as latest sensor timestamp (this is what you predict forward from)
    now = pd.to_datetime(readings["timestamp"].max(), utc=True)

    # 5) Re-fetch backlog using sensor-time now (maturity should be based on this clock)
    backlog = fetch_untrained_matured_predictions(bq, cfg, now, limit=50)

    # 6) Fetch candles across the same span (start_utc..now), plus buffer
    hours = int(np.ceil((now - start_utc).total_seconds() / 3600.0)) + 2
    candles = fetch_candle_events(bq, cfg, hours=hours)

    n_steps = required_steps(cfg.lookback_hours, cfg.interval_minutes)

    # Build FIXED-LENGTH grid for the new prediction, anchored to sensor-time now
    grid, meta = resample_to_grid(
        readings,
        cfg.interval_minutes,
        end_utc=now,
        required_steps=n_steps,
    )

    # Rule A: coverage threshold
    if meta["coverage"] < COVERAGE_THRESHOLD:
        pred_row = {
            "timestamp": pd.to_datetime(meta["end_utc"]).to_pydatetime(),
            "zoneId": cfg.zone_id,
            "probability": -1.0,
            "probability_percent": -1.0,
            "model_version": cfg.model_version,
            "features_hash": None,
            "trained_on_label": False,
            "label_frost_observed": None,
            "label_window_start": None,
            "label_window_end": None,
            "skipped_reason": _coverage_skip_reason("insufficient_real_points", meta),
            "ingest_id": cfg.ingest_id,
            "triggered_at": datetime.now(timezone.utc),
        }
        insert_prediction_row(bq, cfg, pred_row)
        return

    # Rule B: max-gap threshold
    if meta["max_gap_bins"] > MAX_GAP_BINS:
        pred_row = {
            "timestamp": pd.to_datetime(meta["end_utc"]).to_pydatetime(),
            "zoneId": cfg.zone_id,
            "probability": -1.0,
            "probability_percent": -1.0,
            "model_version": cfg.model_version,
            "features_hash": None,
            "trained_on_label": False,
            "label_frost_observed": None,
            "label_window_start": None,
            "label_window_end": None,
            "skipped_reason": _gap_skip_reason("gap_too_large_for_prediction", meta),
            "ingest_id": cfg.ingest_id,
            "triggered_at": datetime.now(timezone.utc),
        }
        insert_prediction_row(bq, cfg, pred_row)
        return

    # Build "current" feature vector (grid is already exactly n_steps long)
    candle_now = latest_candles_on(candles, pd.to_datetime(meta["end_utc"], utc=True))
    x_np, features_hash = build_features(grid, candle_now)

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

        # If candles were active in the label window -> resolve but DO NOT train
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

        
        # Anchor training and prediction to ingest timestamp
        hist = readings[readings["timestamp"] <= pred_time].copy()

        hist_grid, hist_meta = resample_to_grid(
            hist,
            cfg.interval_minutes,
            end_utc=pred_time,
            required_steps=n_steps,
        )

        # Rule A: coverage check for training window
        if hist_meta["coverage"] < COVERAGE_THRESHOLD:
            update_prediction_training_status(
                bq=bq,
                cfg=cfg,
                pred_timestamp_utc=pred_time,
                trained_on_label=False,
                skipped_reason=_coverage_skip_reason("insufficient_real_points_for_training", hist_meta),
                label_frost_observed=int(label_val),
                label_window_start_utc=label_start,
                label_window_end_utc=label_end,
            )
            skipped_count += 1
            continue

        # Rule B: max-gap check for training window
        if hist_meta["max_gap_bins"] > MAX_GAP_BINS:
            update_prediction_training_status(
                bq=bq,
                cfg=cfg,
                pred_timestamp_utc=pred_time,
                trained_on_label=False,
                skipped_reason=_gap_skip_reason("gap_too_large_for_training", hist_meta),
                label_frost_observed=int(label_val),
                label_window_start_utc=label_start,
                label_window_end_utc=label_end,
            )
            skipped_count += 1
            continue

        candle_at_pred_time = latest_candles_on(candles, pred_time)
        x_prev_np, _ = build_features(hist_grid, candle_at_pred_time)

        x_prev = torch.from_numpy(x_prev_np.astype(np.float32)).unsqueeze(0)
        y = torch.tensor([[float(label_val)]], dtype=torch.float32)

        opt.zero_grad()
        logits = model(x_prev)
        loss = F.binary_cross_entropy_with_logits(logits, y)
        loss.backward()
        opt.step()

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

    # Make prediction for the "current" window
    model.eval()
    with torch.no_grad():
        x = torch.from_numpy(x_np.astype(np.float32)).unsqueeze(0)
        prob = torch.sigmoid(model(x)).item()

    prob_pct = float(prob * 100.0)

    # Insert a new prediction row that is unresolved initially
    pred_row = {
        "timestamp": pd.to_datetime(meta["end_utc"], utc=True).to_pydatetime(),
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
        "timestamp": pd.to_datetime(meta["end_utc"], utc=True).isoformat(),
        "probability_percent": prob_pct,
        "backlog_trained": trained_count,
        "backlog_skipped": skipped_count,
    }, indent=2))


if __name__ == "__main__":
    main()
