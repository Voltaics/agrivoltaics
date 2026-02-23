import hashlib
import numpy as np
import pandas as pd


# Raw sensors pulled from BigQuery (per timestamp)
RAW_SENSOR_COLS = ["temperature", "humidity", "soilMoisture", "soilTemperature", "light"]

# Derived, per-timestep features we compute locally
DERIVED_COLS = ["frost_index"]

# Columns that participate in delta feature creation + robust scaling
SENSOR_COLS = RAW_SENSOR_COLS + DERIVED_COLS


def resample_to_grid(df: pd.DataFrame, minutes: int) -> pd.DataFrame:
    df = df.set_index("timestamp").sort_index()
    for c in RAW_SENSOR_COLS:
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

def _dewpoint_c_from_temp_f_and_rh(temp_f: pd.Series, rh_pct: pd.Series) -> pd.Series:
    """
    Compute dew point in °C from temperature in °F and relative humidity in %.

    Uses the Magnus approximation (good for typical ambient ranges).
    Returns a pandas Series aligned with inputs.
    """
    # Convert F -> C
    t_c = (temp_f.astype(np.float32) - 32.0) * (5.0 / 9.0)

    # RH clamp to avoid log(0) or >100
    rh = rh_pct.astype(np.float32).clip(lower=1.0, upper=100.0) / 100.0

    # Magnus constants for water vapor over liquid water
    a = 17.27
    b = 237.7  # °C

    gamma = (np.log(rh) + (a * t_c) / (b + t_c)).astype(np.float32)
    dewpoint_c = (b * gamma) / (a - gamma)
    return dewpoint_c.astype(np.float32)


def _add_frost_index_features(grid_df: pd.DataFrame) -> pd.DataFrame:
    """
    Adds a frost_index column in [0,1] as a 'cold × moist' proxy.

    - coldness: higher when temperature is below ~2°C
    - moisture: higher when RH is high AND dewpoint is close to temperature
    """
    df = grid_df.copy()

    # Ensure numeric
    temp = pd.to_numeric(df.get("temperature"), errors="coerce").astype(np.float32)
    rh = pd.to_numeric(df.get("humidity"), errors="coerce").astype(np.float32)

    # If either is missing entirely, fall back to 0s
    if temp is None or rh is None:
        df["frost_index"] = 0.0
        return df

    dew_c = _dewpoint_c_from_temp_f_and_rh(temp, rh)

    # Convert temp to C for easier thresholding
    temp_c = (temp - 32.0) * (5.0 / 9.0)

    # coldness: 2°C -> 0, -4°C -> 1 (linear), clamp to [0,1]
    cold = ((2.0 - temp_c) / 6.0).clip(lower=0.0, upper=1.0)

    # dewpoint spread (°C): smaller spread => "moister" air
    spread = (temp_c - dew_c).astype(np.float32)

    # spread factor: <=0°C spread -> 1, >=3°C spread -> 0 (linear), clamp
    spread_factor = ((3.0 - spread) / 3.0).clip(lower=0.0, upper=1.0)

    # RH factor in [0,1]
    rh_factor = (rh / 100.0).clip(lower=0.0, upper=1.0)

    moist = (rh_factor * spread_factor).astype(np.float32)

    frost_index = (cold * moist).astype(np.float32).fillna(0.0).clip(lower=0.0, upper=1.0)

    df["frost_index"] = frost_index
    return df


def _add_light_daily_cyclic_features(grid_df: pd.DataFrame, eps: float = 1e-6) -> pd.DataFrame:
    """
    Adds light_sin/light_cos based on *daily-normalized* light values.

    For each UTC day:
      light_norm = (light - day_min) / (day_max - day_min)
    Then map to the unit circle:
      angle = 2π * light_norm
      light_sin = sin(angle), light_cos = cos(angle)

    If a day's light range is ~0, we set light_norm = 0.
    """
    df = grid_df.copy()

    if "light" not in df.columns:
        df["light_sin"] = 0.0
        df["light_cos"] = 1.0
        return df

    ts = pd.to_datetime(df["timestamp"], utc=True)
    light = pd.to_numeric(df["light"], errors="coerce").astype(np.float32)

    day_key = ts.dt.floor("D")

    day_min = light.groupby(day_key).transform("min")
    day_max = light.groupby(day_key).transform("max")
    day_rng = (day_max - day_min).astype(np.float32)

    # Avoid division by ~0
    safe_rng = day_rng.where(day_rng > eps, other=np.float32(1.0))
    light_norm = ((light - day_min) / safe_rng).astype(np.float32)

    # If range was tiny, set norm to 0
    light_norm = light_norm.where(day_rng > eps, other=np.float32(0.0))

    angle = (2.0 * np.pi * light_norm).astype(np.float32)
    df["light_sin"] = np.sin(angle).astype(np.float32).fillna(0.0)
    df["light_cos"] = np.cos(angle).astype(np.float32).fillna(1.0)

    return df

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

    # derived features
    df = _add_frost_index_features(df)
    df = _add_light_daily_cyclic_features(df)

    df = _add_delta_features(df)

    feature_cols = (
    SENSOR_COLS
    + [f"d_{c}" for c in SENSOR_COLS]
    + ["tod_sin", "tod_cos", "doy_sin", "doy_cos", "light_sin", "light_cos"]
    )

    # Build matrix (T, F)
    mat = df[feature_cols].to_numpy(dtype=np.float32)

    # Robust scale everything except sin/cos (they are already [-1,1])
    # We’ll scale in two blocks so we don't distort cyclic features.
    raw_and_delta_cols = SENSOR_COLS + [f"d_{c}" for c in SENSOR_COLS]
    cyc_cols = ["tod_sin", "tod_cos", "doy_sin", "doy_cos", "light_sin", "light_cos"]

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
