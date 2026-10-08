const {
  computeDewPointF,
  computeDewPointSpreadF,
  computeCoolingRateFPerHr,
  computeProjectedTemp2hF,
  classifyWind,
  deriveLeafWetnessState,
  isNightOrLowLight,
  WIND_BUCKET,
  LEAF_STATE,
} = require('../derivations');

const DEFAULT_CONFIG = {
  windCalmMaxMph: 2,
  windLightMaxMph: 5,
  windModerateMaxMph: 10,
  leafWetnessDryMaxPercent: 20,
  leafWetnessWetMinPercent: 30,
  nightLightMaxLux: 5000,
};

describe('computeDewPointF', () => {
  test('matches known reference value (20C/50%RH ~9.3C dew point)', () => {
    // 20C = 68F; reference dew point ~9.3C = ~48.7F.
    const result = computeDewPointF(68, 50);
    expect(result).not.toBeNull();
    expect(result).toBeCloseTo(48.7, 0);
  });

  test('dew point rises toward air temp as humidity approaches 100%', () => {
    const result = computeDewPointF(68, 99);
    expect(result).toBeGreaterThan(60);
    expect(result).toBeLessThanOrEqual(68);
  });

  test('returns null for invalid humidity (spec: do not compute from invalid RH)', () => {
    expect(computeDewPointF(50, 0)).toBeNull();
    expect(computeDewPointF(50, -5)).toBeNull();
    expect(computeDewPointF(50, 101)).toBeNull();
  });

  test('returns null for non-numeric inputs', () => {
    expect(computeDewPointF(null, 50)).toBeNull();
    expect(computeDewPointF(50, undefined)).toBeNull();
    expect(computeDewPointF('not a number', 50)).toBeNull();
  });
});

describe('computeDewPointSpreadF', () => {
  test('air temp minus dew point', () => {
    expect(computeDewPointSpreadF(34.8, 34.1)).toBeCloseTo(0.7, 5);
  });

  test('flags any negative spread as invalid (sensor error, spec Appendix A)', () => {
    expect(computeDewPointSpreadF(30, 34)).toBeNull();
    expect(computeDewPointSpreadF(34, 34.2)).toBeNull();
  });

  test('zero spread is valid (air essentially saturated)', () => {
    expect(computeDewPointSpreadF(34, 34)).toBe(0);
  });

  test('returns null when an input is missing', () => {
    expect(computeDewPointSpreadF(null, 34)).toBeNull();
  });
});

describe('computeCoolingRateFPerHr', () => {
  test('CoolingRate60 matches spec formula directly', () => {
    // Tnow=39, T60min=41 -> falling 2F over 60 minutes = -2F/hour.
    expect(computeCoolingRateFPerHr(39, 41, 60)).toBeCloseTo(-2, 5);
  });

  test('normalizes a 30-minute window to a per-hour rate', () => {
    // Fell 1F in 30 minutes -> -2F/hour equivalent.
    expect(computeCoolingRateFPerHr(39, 40, 30)).toBeCloseTo(-2, 5);
  });

  test('positive when warming', () => {
    expect(computeCoolingRateFPerHr(45, 40, 60)).toBeCloseTo(5, 5);
  });

  test('returns null for zero/negative elapsed minutes', () => {
    expect(computeCoolingRateFPerHr(39, 41, 0)).toBeNull();
    expect(computeCoolingRateFPerHr(39, 41, -10)).toBeNull();
  });
});

describe('computeProjectedTemp2hF', () => {
  test('matches spec formula: Tnow + 2*CoolingRate60', () => {
    expect(computeProjectedTemp2hF(37, -2.5)).toBeCloseTo(32, 5);
  });

  test('returns null when cooling rate is unavailable', () => {
    expect(computeProjectedTemp2hF(37, null)).toBeNull();
  });
});

describe('classifyWind', () => {
  test.each([
    [1.9, WIND_BUCKET.CALM],
    [2, WIND_BUCKET.LIGHT],
    [5, WIND_BUCKET.LIGHT],
    [5.1, WIND_BUCKET.MODERATE],
    [10, WIND_BUCKET.MODERATE],
    [10.1, WIND_BUCKET.STRONG],
  ])('%dmph classifies as %s', (mph, expectedBucket) => {
    expect(classifyWind(mph, DEFAULT_CONFIG).bucket).toBe(expectedBucket);
  });

  test('unknown when wind speed is missing', () => {
    expect(classifyWind(null, DEFAULT_CONFIG).bucket).toBeNull();
  });

  test('honors farmer-configured band overrides', () => {
    const customConfig = {windCalmMaxMph: 1, windLightMaxMph: 3, windModerateMaxMph: 6};
    expect(classifyWind(2, customConfig).bucket).toBe(WIND_BUCKET.LIGHT);
  });
});

describe('deriveLeafWetnessState', () => {
  test('dry below the dry cutoff', () => {
    const result = deriveLeafWetnessState(15, null, DEFAULT_CONFIG);
    expect(result.state).toBe(LEAF_STATE.DRY);
    expect(result.justTransitionedDryToWet).toBe(false);
  });

  test('wet above the wet cutoff', () => {
    const result = deriveLeafWetnessState(35, LEAF_STATE.DRY, DEFAULT_CONFIG);
    expect(result.state).toBe(LEAF_STATE.WET);
    expect(result.justTransitionedDryToWet).toBe(true);
  });

  test('holds previous state inside the hysteresis band', () => {
    const fromDry = deriveLeafWetnessState(25, LEAF_STATE.DRY, DEFAULT_CONFIG);
    expect(fromDry.state).toBe(LEAF_STATE.DRY);

    const fromWet = deriveLeafWetnessState(25, LEAF_STATE.WET, DEFAULT_CONFIG);
    expect(fromWet.state).toBe(LEAF_STATE.WET);
  });

  test('defaults to dry in the hysteresis band with no prior state', () => {
    expect(deriveLeafWetnessState(25, null, DEFAULT_CONFIG).state).toBe(LEAF_STATE.DRY);
  });

  test('does not flag a transition when already wet', () => {
    const result = deriveLeafWetnessState(35, LEAF_STATE.WET, DEFAULT_CONFIG);
    expect(result.justTransitionedDryToWet).toBe(false);
  });

  test('missing raw value falls back to previous state, no transition', () => {
    const result = deriveLeafWetnessState(null, LEAF_STATE.WET, DEFAULT_CONFIG);
    expect(result.state).toBe(LEAF_STATE.WET);
    expect(result.rawPercent).toBeNull();
    expect(result.justTransitionedDryToWet).toBe(false);
  });
});

describe('isNightOrLowLight', () => {
  test('true at/below the configured lux ceiling', () => {
    expect(isNightOrLowLight(100, DEFAULT_CONFIG)).toBe(true);
    expect(isNightOrLowLight(5000, DEFAULT_CONFIG)).toBe(true);
  });

  test('false above the configured lux ceiling', () => {
    expect(isNightOrLowLight(20000, DEFAULT_CONFIG)).toBe(false);
  });

  test('fails safe (false) when light reading is missing', () => {
    expect(isNightOrLowLight(null, DEFAULT_CONFIG)).toBe(false);
  });
});
