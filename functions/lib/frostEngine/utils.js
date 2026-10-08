/**
 * Shared utilities for the frost rule engine.
 *
 * Deliberately avoids `??`/`?.` for consistency with functions/lib/alertHelpers.js,
 * which targets an ESLint/parser config (ecmaVersion 2018) that predates those operators.
 */

/**
 * Return value unless it is null/undefined, else fallback.
 * @param {*} value
 * @param {*} fallback
 * @return {*}
 */
function defaultIfNull(value, fallback) {
  return value !== null && value !== undefined ? value : fallback;
}

/**
 * Convert to a finite number or null.
 * @param {*} value
 * @return {number|null}
 */
function toNumberOrNull(value) {
  if (value === null || value === undefined) return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/** Ordered grapevine growth stages, dormant (least sensitive) to fruit set. */
const GROWTH_STAGES = [
  'dormant',
  'swollenBud',
  'budBreak',
  'shoot1to3in',
  'flowering',
  'fruitSet',
];

/**
 * True when `stage` is at or after `thresholdStage` in vine development.
 * Unknown stages are treated as NOT meeting the threshold (fail safe: don't
 * suppress frost concern for a stage the engine doesn't recognize).
 *
 * @param {string} stage
 * @param {string} thresholdStage
 * @return {boolean}
 */
function isGrowthStageAtLeast(stage, thresholdStage) {
  const stageIdx = GROWTH_STAGES.indexOf(stage);
  const thresholdIdx = GROWTH_STAGES.indexOf(thresholdStage);
  if (stageIdx === -1 || thresholdIdx === -1) return false;
  return stageIdx >= thresholdIdx;
}

module.exports = {
  defaultIfNull,
  toNumberOrNull,
  GROWTH_STAGES,
  isGrowthStageAtLeast,
};
