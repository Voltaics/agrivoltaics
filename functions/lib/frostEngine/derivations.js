/**
 * Pure sensor-derived value calculations for the frost rule engine.
 *
 * No Firestore/BigQuery/network access - every function here takes plain
 * numbers/objects and returns plain numbers/objects, so the whole module is
 * unit-testable with synthetic fixtures.
 */

const {defaultIfNull, toNumberOrNull} = require('./utils');

// Magnus approximation constants from the professor's spec (Alduchov-Eskridge).
// Deliberately different from the constants used by
// application/Docker/Zone_Frost/features.py's own dew-point calc
// (17.27/237.7, standard Magnus-Tetens) - that file serves the separate AI
// model's internal feature engineering and should not be "fixed" to match
// this one.
const MAGNUS_A = 17.625;
const MAGNUS_B = 243.04; // degrees C

const WIND_BUCKET = {
  CALM: 'calm',
  LIGHT: 'light',
  MODERATE: 'moderate',
  STRONG: 'strong',
};

const LEAF_STATE = {
  WET: 'wet',
  DRY: 'dry',
};

/**
 * @param {number} tempF
 * @return {number}
 */
function fToC(tempF) {
  return (tempF - 32) * (5 / 9);
}

/**
 * @param {number} tempC
 * @return {number}
 */
function cToF(tempC) {
  return (tempC * 9 / 5) + 32;
}

/**
 * Dew point via the Magnus approximation. Per spec, the math happens in
 * Celsius internally; only the return value is converted back to Fahrenheit.
 *
 * Returns null (never throws) for invalid inputs - the spec explicitly says
 * "do not calculate dew point from invalid temperature or humidity."
 *
 * @param {number} tempF - Air temperature in degrees F.
 * @param {number} rhPercent - Relative humidity, 0-100.
 * @return {number|null} Dew point in degrees F, or null if inputs are invalid.
 */
function computeDewPointF(tempF, rhPercent) {
  const t = toNumberOrNull(tempF);
  const rh = toNumberOrNull(rhPercent);
  if (t === null || rh === null) return null;
  if (rh <= 0 || rh > 100) return null;

  const tempC = fToC(t);
  const gamma = Math.log(rh / 100) + (MAGNUS_A * tempC) / (MAGNUS_B + tempC);
  const dewC = (MAGNUS_B * gamma) / (MAGNUS_A - gamma);

  if (!Number.isFinite(dewC)) return null;
  return cToF(dewC);
}

/**
 * DewPointSpread = Tair - Tdewpoint. Per spec Appendix A's interpretation
 * table, a spread below 0°F is "likely sensor error or mismatched
 * measurements", so it's surfaced as null rather than fed into rules.
 *
 * @param {number} tempF
 * @param {number} dewPointF
 * @return {number|null}
 */
function computeDewPointSpreadF(tempF, dewPointF) {
  const t = toNumberOrNull(tempF);
  const dp = toNumberOrNull(dewPointF);
  if (t === null || dp === null) return null;

  const spread = t - dp;
  if (spread < 0) return null;
  return spread;
}

/**
 * Cooling rate normalized to degrees F per hour, generalized so it works for
 * any lookback window (15/30/60/120 min), not just the spec's named
 * CoolingRate60. A negative result means the temperature is falling.
 *
 * @param {number} currentTempF
 * @param {number} pastTempF - Temperature `elapsedMinutes` ago.
 * @param {number} elapsedMinutes
 * @return {number|null}
 */
function computeCoolingRateFPerHr(currentTempF, pastTempF, elapsedMinutes) {
  const current = toNumberOrNull(currentTempF);
  const past = toNumberOrNull(pastTempF);
  const minutes = toNumberOrNull(elapsedMinutes);
  if (current === null || past === null || minutes === null || minutes <= 0) {
    return null;
  }
  return (current - past) / (minutes / 60);
}

/**
 * Tprojected,2h = Tnow + 2*CoolingRate60, exactly as specified. Deliberately
 * simple/linear per the spec's own note that it may later be replaced by a
 * locally calibrated regression.
 *
 * @param {number} currentTempF
 * @param {number} coolingRate60FPerHr
 * @return {number|null}
 */
function computeProjectedTemp2hF(currentTempF, coolingRate60FPerHr) {
  const current = toNumberOrNull(currentTempF);
  const rate = toNumberOrNull(coolingRate60FPerHr);
  if (current === null || rate === null) return null;
  return current + 2 * rate;
}

/**
 * Classifies wind speed per spec Appendix B's four bands.
 *
 * @param {number} windSpeedMph
 * @param {Object} config - frostRuleConfig (windCalmMaxMph/windLightMaxMph/windModerateMaxMph).
 * @return {{bucket: (string|null), label: string}}
 */
function classifyWind(windSpeedMph, config) {
  const speed = toNumberOrNull(windSpeedMph);
  if (speed === null) return {bucket: null, label: 'Unknown'};

  const calmMax = defaultIfNull(config.windCalmMaxMph, 2);
  const lightMax = defaultIfNull(config.windLightMaxMph, 5);
  const moderateMax = defaultIfNull(config.windModerateMaxMph, 10);

  if (speed < calmMax) {
    return {bucket: WIND_BUCKET.CALM, label: 'Calm - strong radiation-frost potential'};
  }
  if (speed <= lightMax) {
    return {bucket: WIND_BUCKET.LIGHT, label: 'Light - radiation frost still possible'};
  }
  if (speed <= moderateMax) {
    return {bucket: WIND_BUCKET.MODERATE, label: 'Moderate - possible advective/mixed freeze'};
  }
  return {bucket: WIND_BUCKET.STRONG, label: 'Strong - likely advective freeze'};
}

/**
 * Derives a stable wet/dry state from a raw leaf-wetness percentage
 * (`leafMoisture` reading), with a hysteresis band between the dry and wet
 * cutoffs to avoid flapping. Inside the band, the previous state is retained
 * (falls back to 'dry' if there is no previous state, e.g. the first-ever
 * reading).
 *
 * @param {number} rawPercent
 * @param {string|null} prevState - 'wet' | 'dry' | null.
 * @param {Object} config - frostRuleConfig (leafWetnessDryMaxPercent/leafWetnessWetMinPercent).
 * @return {{rawPercent: (number|null), state: string, justTransitionedDryToWet: boolean}}
 */
function deriveLeafWetnessState(rawPercent, prevState, config) {
  const raw = toNumberOrNull(rawPercent);

  if (raw === null) {
    return {
      rawPercent: null,
      state: defaultIfNull(prevState, LEAF_STATE.DRY),
      justTransitionedDryToWet: false,
    };
  }

  const dryMax = defaultIfNull(config.leafWetnessDryMaxPercent, 20);
  const wetMin = defaultIfNull(config.leafWetnessWetMinPercent, 30);

  let state;
  if (raw <= dryMax) {
    state = LEAF_STATE.DRY;
  } else if (raw >= wetMin) {
    state = LEAF_STATE.WET;
  } else {
    state = defaultIfNull(prevState, LEAF_STATE.DRY);
  }

  return {
    rawPercent: raw,
    state,
    justTransitionedDryToWet: prevState === LEAF_STATE.DRY && state === LEAF_STATE.WET,
  };
}

/**
 * Coarse night/low-light proxy from a lux reading. A basic light sensor
 * can't distinguish a clear night from a cloudy one (spec Appendix B) - true
 * cloud cover comes from the forecast module; this only answers "is it dark
 * enough that daytime warming isn't a factor right now."
 *
 * @param {number} lightLux
 * @param {Object} config - frostRuleConfig (nightLightMaxLux).
 * @return {boolean}
 */
function isNightOrLowLight(lightLux, config) {
  const lux = toNumberOrNull(lightLux);
  if (lux === null) return false; // fail safe: don't assume dark without data
  const maxLux = defaultIfNull(config.nightLightMaxLux, 5000);
  return lux <= maxLux;
}

module.exports = {
  MAGNUS_A,
  MAGNUS_B,
  WIND_BUCKET,
  LEAF_STATE,
  fToC,
  cToF,
  computeDewPointF,
  computeDewPointSpreadF,
  computeCoolingRateFPerHr,
  computeProjectedTemp2hF,
  classifyWind,
  deriveLeafWetnessState,
  isNightOrLowLight,
};
