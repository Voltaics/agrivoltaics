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
    fetch_candle_events,
    latest_candles_on,
    candles_on_during_window,
    fetch_prediction_near_time,
    insert_prediction_row,
    has_processed_ingest,
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
    if cfg.ingest_id and has_processed_ingest(bq, cfg):
        print(f"Ingest {cfg.ingest_id} already processed for zone {cfg.zone_id}, skipping.")
        return
    torch.manual_seed(cfg.seed)
    np.random.seed(cfg.seed)
    readings = fetch_readings(bq, cfg)
    candles = fetch_candle_events(bq, cfg, hours=6)

    now = pd.Timestamp(readings["timestamp"].max()).tz_convert("UTC")

    grid = resample_to_grid(readings, cfg.interval_minutes)

    ok, why_not = has_enough_history(grid, cfg)
    if not ok:
        pred_row = {
            "timestamp": now.to_pydatetime(),
            "zoneId": cfg.zone_id,
            "probability": 0.0,
            "probability_percent": 0.0,
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

    candle_now = latest_candles_on(candles, now)
    x_np, features_hash = build_features(grid.tail(n_steps), candle_now)

    model = FrostMLP(input_dim=x_np.shape[0])
    opt = torch.optim.AdamW(model.parameters(), lr=cfg.lr, weight_decay=cfg.weight_decay)

    # Load persisted state
    state = load_state(cfg)
    if state:
        model.load_state_dict(state["model"])
        opt.load_state_dict(state["opt"])

    model.train()

    # Predict "next 2h frost observed" (in this single-head version)
    x = torch.from_numpy(x_np).unsqueeze(0)
    prob = torch.sigmoid(model(x)).item()
    prob_pct = float(prob * 100.0)

    pred_row = {
        "timestamp": now.to_pydatetime(),
        "zoneId": cfg.zone_id,
        "probability": float(prob),
        "probability_percent": prob_pct,
        "model_version": cfg.model_version,
        "features_hash": features_hash,
        "trained_on_label": False,
        "label_frost_observed": None,
        "label_window_start": None,
        "label_window_end": None,
        "skipped_reason": None,
        "ingest_id": cfg.ingest_id,
        "triggered_at": datetime.now(timezone.utc),
    }

    # Online update using prediction from ~2h ago
    trained = False
    skipped_reason = None
    label_val = None
    label_start = None
    label_end = None

    target_pred_time = now - pd.Timedelta(minutes=cfg.horizon_minutes)
    prev_pred = fetch_prediction_near_time(bq, cfg, target_pred_time, tolerance_minutes=20)

    if prev_pred:
        label_start = pd.Timestamp(prev_pred["timestamp"]).tz_convert("UTC")
        label_end = label_start + pd.Timedelta(minutes=cfg.horizon_minutes)

        if candles_on_during_window(candles, label_start, label_end):
            skipped_reason = "candles_on"
        else:
            label_val = compute_label_frost_in_window(readings, label_start, label_end, cfg.frost_temp_threshold)

            if label_val is None:
                skipped_reason = "insufficient_label_data"
            else:
                # rebuild features as-of label_start
                hist = readings[readings["timestamp"] <= label_start].copy()
                hist_grid = resample_to_grid(hist, cfg.interval_minutes)

                ok, why_not = has_enough_history(hist_grid, cfg)
                if not ok:
                    skipped_reason = f"insufficient_history_for_training:{why_not}"
                else:
                    candle_at_pred_time = latest_candles_on(candles, label_start)
                    x_prev_np, _ = build_features(hist_grid.tail(n_steps), candle_at_pred_time)

                    x_prev = torch.from_numpy(x_prev_np).unsqueeze(0)
                    y = torch.tensor([[float(label_val)]], dtype=torch.float32)

                    opt.zero_grad()
                    loss = F.binary_cross_entropy_with_logits(model(x_prev), y)
                    loss.backward()
                    opt.step()
                    trained = True


    pred_row["trained_on_label"] = trained
    pred_row["label_frost_observed"] = int(label_val) if label_val is not None else None
    pred_row["label_window_start"] = label_start.to_pydatetime() if label_start is not None else None
    pred_row["label_window_end"] = label_end.to_pydatetime() if label_end is not None else None
    pred_row["skipped_reason"] = skipped_reason

    insert_prediction_row(bq, cfg, pred_row)

    # Save state
    save_state(cfg, {"model": model.state_dict(), "opt": opt.state_dict(), "version": cfg.model_version})

    print(json.dumps({
        "zoneId": cfg.zone_id,
        "timestamp": now.isoformat(),
        "probability_percent": prob_pct,
        "trained": trained,
        "skipped_reason": skipped_reason,
        "label": label_val,
    }, indent=2))


if __name__ == "__main__":
    main()
