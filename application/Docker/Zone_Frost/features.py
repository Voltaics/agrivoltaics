import hashlib
import numpy as np
import pandas as pd


SENSOR_COLS = ["temperature", "humidity", "soilMoisture", "soilTemperature"]


def resample_to_grid(df: pd.DataFrame, minutes: int) -> pd.DataFrame:
    df = df.set_index("timestamp").sort_index()
    for c in SENSOR_COLS:
        df[c] = pd.to_numeric(df[c], errors="coerce")

    grid = df.resample(f"{minutes}min").mean()
    grid = grid.interpolate(limit_direction="both")
    return grid.reset_index()


def _add_time_cyclic_features(grid_df: pd.DataFrame) -> pd.DataFrame:
    """
    Adds cyclical time features based on the timestamp column (assumed UTC-aware).
    - time of day (sin/cos)
    - day of year (sin/cos)
    """
    ts = pd.to_datetime(grid_df["timestamp"], utc=True)

    # seconds since midnight
    sod = (ts.dt.hour * 3600 + ts.dt.minute * 60 + ts.dt.second).astype(np.float32)
    day_seconds = np.float32(24 * 3600)

    # day-of-year (1..366)
    doy = ts.dt.dayofyear.astype(np.float32)
    year_days = np.float32(366.0)  # fine for cyc encoding

    grid_df = grid_df.copy()
    grid_df["tod_sin"] = np.sin(2.0 * np.pi * sod / day_seconds).astype(np.float32)
    grid_df["tod_cos"] = np.cos(2.0 * np.pi * sod / day_seconds).astype(np.float32)
    grid_df["doy_sin"] = np.sin(2.0 * np.pi * doy / year_days).astype(np.float32)
    grid_df["doy_cos"] = np.cos(2.0 * np.pi * doy / year_days).astype(np.float32)
    return grid_df


def _add_delta_features(grid_df: pd.DataFrame) -> pd.DataFrame:
    """
    Adds first-difference features (delta) for each sensor column.
    Helps the model learn cooling rates and trends.
    """
    grid_df = grid_df.copy()
    for c in SENSOR_COLS:
        grid_df[f"d_{c}"] = grid_df[c].diff().fillna(0.0).astype(np.float32)
    return grid_df


def _robust_scale(mat: np.ndarray, eps: float = 1e-6) -> np.ndarray:
    """
    Robust scaling per column using median and IQR:
      z = (x - median) / (IQR + eps)
    This is stable for online learning and less sensitive to spikes than mean/std.
    """
    med = np.nanmedian(mat, axis=0)
    q25 = np.nanpercentile(mat, 25, axis=0)
    q75 = np.nanpercentile(mat, 75, axis=0)
    iqr = (q75 - q25)
    return (mat - med) / (iqr + eps)


def build_features(
    grid_df: pd.DataFrame,
    candle_now: bool,
) -> tuple[np.ndarray, str]:
    """
    Build a 1D feature vector from a time-grid DataFrame.

    Includes:
      - raw sensors (robust scaled)
      - deltas of sensors (robust scaled)
      - cyclical time features (sin/cos) (already bounded)
      - candle flag

    Returns:
      x: np.ndarray float32 shape (D,)
      h: sha256 hash for debugging
    """
    df = grid_df.copy()
    df = _add_time_cyclic_features(df)
    df = _add_delta_features(df)

    feature_cols = (
        SENSOR_COLS
        + [f"d_{c}" for c in SENSOR_COLS]
        + ["tod_sin", "tod_cos", "doy_sin", "doy_cos"]
    )

    # Build matrix (T, F)
    mat = df[feature_cols].to_numpy(dtype=np.float32)

    # Robust scale everything except sin/cos (they are already [-1,1])
    # We’ll scale in two blocks so we don't distort cyclic features.
    raw_and_delta_cols = SENSOR_COLS + [f"d_{c}" for c in SENSOR_COLS]
    cyc_cols = ["tod_sin", "tod_cos", "doy_sin", "doy_cos"]

    raw_delta = df[raw_and_delta_cols].to_numpy(dtype=np.float32)
    raw_delta_scaled = _robust_scale(raw_delta)

    cyc = df[cyc_cols].to_numpy(dtype=np.float32)

    mat_scaled = np.concatenate([raw_delta_scaled, cyc], axis=1)

    # Flatten time dimension
    x = mat_scaled.reshape(-1).astype(np.float32)

    # Add candle flag
    x = np.concatenate([x, np.array([1.0 if candle_now else 0.0], dtype=np.float32)], axis=0)

    h = hashlib.sha256(x.tobytes()).hexdigest()
    return x, h


def compute_label_frost_in_window(
    readings_df: pd.DataFrame,
    start: pd.Timestamp,
    end: pd.Timestamp,
    threshold: float,
) -> int | None:
    window = readings_df[(readings_df["timestamp"] >= start) & (readings_df["timestamp"] <= end)]
    if window.empty or window["temperature"].isna().all():
        return None
    return 1 if float(window["temperature"].min()) <= threshold else 0
