const {
  ALERT_LEVEL,
  WARNING_SUBTYPE,
  updateStreak,
  checkRule2A,
  checkRule2B,
  checkRule3A,
  checkRule3B,
  checkRule3C,
  checkRule4A,
  checkRule4B,
  checkRule4C,
  checkLevel5,
  checkLevel6AllClear,
  evaluateFrostLevel,
} = require('../rules');

/**
 * Builds a "nothing is happening" derived-values fixture, override per test.
 * @param {Object} [overrides]
 * @return {Object}
 */
function buildDerived(overrides) {
  return Object.assign({
    airTempF: null,
    dewPointF: null,
    dewPointSpreadF: null,
    coolingRate60FPerHr: null,
    projectedTemp2hF: null,
    windSpeedMph: null,
    isNightOrLowLight: false,
    leafWetness: {state: 'dry', justTransitionedDryToWet: false},
  }, overrides || {});
}

/**
 * Builds a baseline evaluateFrostLevel input, override per test.
 * @param {Object} [overrides]
 * @return {Object}
 */
function buildInput(overrides) {
  return Object.assign({
    derived: buildDerived(),
    budZoneTempF: null,
    growthStage: 'dormant',
    forecast: null,
    config: {},
    streaksInput: null,
    eventAccumulators: {timeBelowCriticalMinutes: 0, recoveryStableMinutes: 0},
    prevLevel: ALERT_LEVEL.NORMAL,
    dataQualityOk: true,
    nowIso: '2026-01-01T00:00:00.000Z',
  }, overrides || {});
}

describe('updateStreak', () => {
  test('increments from zero on first true tick', () => {
    const result = updateStreak(null, true, 't1');
    expect(result.consecutiveTrue).toBe(1);
    expect(result.lastTrueAt).toBe('t1');
  });

  test('increments across ticks while condition stays true', () => {
    const tick1 = updateStreak(null, true, 't1');
    const tick2 = updateStreak(tick1, true, 't2');
    expect(tick2.consecutiveTrue).toBe(2);
    expect(tick2.lastTrueAt).toBe('t2');
  });

  test('resets to zero and keeps lastTrueAt when condition goes false', () => {
    const tick1 = updateStreak(null, true, 't1');
    const tick2 = updateStreak(tick1, false, 't2');
    expect(tick2.consecutiveTrue).toBe(0);
    expect(tick2.lastTrueAt).toBe('t1');
    expect(tick2.lastEvalAt).toBe('t2');
  });
});

describe('checkRule2A', () => {
  const passingDerived = buildDerived({
    airTempF: 40, coolingRate60FPerHr: -2.5, windSpeedMph: 3, dewPointSpreadF: 6,
  });

  test('fires when all four conditions hold', () => {
    expect(checkRule2A(passingDerived, {})).toBe(true);
  });

  test.each([
    ['airTempF', 43],
    ['coolingRate60FPerHr', -1],
    ['windSpeedMph', 5],
    ['dewPointSpreadF', 5],
  ])('does not fire when %s fails its threshold', (field, value) => {
    const derived = buildDerived(Object.assign({}, passingDerived, {[field]: value}));
    expect(checkRule2A(derived, {})).toBe(false);
  });

  test('does not fire with missing data', () => {
    expect(checkRule2A(buildDerived(), {})).toBe(false);
  });
});

describe('checkRule2B', () => {
  test('omitted (false) when no forecast is available', () => {
    expect(checkRule2B(null, {})).toBe(false);
  });

  test('fires when forecast minimum reaches the reference threshold', () => {
    expect(checkRule2B({minTempNextNHoursF: 35}, {})).toBe(true);
  });

  test('does not fire when forecast minimum stays above the reference threshold', () => {
    expect(checkRule2B({minTempNextNHoursF: 40}, {})).toBe(false);
  });
});

describe('checkRule3A', () => {
  const base = {
    airTempF: 35, windSpeedMph: 2, coolingRate60FPerHr: -1.5, isNightOrLowLight: true,
  };

  test('fires via the dew-point-spread branch', () => {
    const derived = buildDerived(Object.assign({}, base, {dewPointSpreadF: 3}));
    expect(checkRule3A(derived, {})).toBe(true);
  });

  test('fires via the dry-to-wet leaf transition branch even with a wide dew spread', () => {
    const derived = buildDerived(Object.assign({}, base, {
      dewPointSpreadF: 6,
      leafWetness: {state: 'wet', justTransitionedDryToWet: true},
    }));
    expect(checkRule3A(derived, {})).toBe(true);
  });

  test('does not fire during daylight/high light', () => {
    const derived = buildDerived(Object.assign({}, base, {
      isNightOrLowLight: false, dewPointSpreadF: 3,
    }));
    expect(checkRule3A(derived, {})).toBe(false);
  });
});

describe('checkRule3B', () => {
  test('fires when all conditions hold', () => {
    const derived = buildDerived({
      airTempF: 36, windSpeedMph: 4, coolingRate60FPerHr: -2.5,
      dewPointSpreadF: 5, projectedTemp2hF: 31,
    });
    expect(checkRule3B(derived, {})).toBe(true);
  });

  test('does not fire when projected temp stays above 32F', () => {
    const derived = buildDerived({
      airTempF: 36, windSpeedMph: 4, coolingRate60FPerHr: -2.5,
      dewPointSpreadF: 5, projectedTemp2hF: 33,
    });
    expect(checkRule3B(derived, {})).toBe(false);
  });
});

describe('checkRule3C', () => {
  const base = {airTempF: 34, windSpeedMph: 6, coolingRate60FPerHr: -1};

  test('fires when wind is sustained, temp falling, and forecast confirms freezing air', () => {
    const derived = buildDerived(base);
    expect(checkRule3C(derived, {regionalFreezingAirIncoming: true}, {})).toBe(true);
  });

  test('does not fire without forecast confirmation', () => {
    const derived = buildDerived(base);
    expect(checkRule3C(derived, null, {})).toBe(false);
    expect(checkRule3C(derived, {regionalFreezingAirIncoming: false}, {})).toBe(false);
  });

  test('does not fire when wind is at/below the calm-side threshold', () => {
    const derived = buildDerived(Object.assign({}, base, {windSpeedMph: 5}));
    expect(checkRule3C(derived, {regionalFreezingAirIncoming: true}, {})).toBe(false);
  });
});

describe('checkRule4A', () => {
  const derived = buildDerived({airTempF: 32, coolingRate60FPerHr: -0.5});

  test('fires at bud-break or later', () => {
    expect(checkRule4A(derived, null, 'budBreak', {})).toBe(true);
    expect(checkRule4A(derived, null, 'flowering', {})).toBe(true);
  });

  test('does not fire before the configured growth-stage floor', () => {
    expect(checkRule4A(derived, null, 'dormant', {})).toBe(false);
    expect(checkRule4A(derived, null, 'swollenBud', {})).toBe(false);
  });
});

describe('checkRule4B', () => {
  test('fires when wet tissue and near-saturated, calm conditions reach critical temp', () => {
    const derived = buildDerived({
      airTempF: 32, dewPointSpreadF: 0.5, windSpeedMph: 2,
      leafWetness: {state: 'wet', justTransitionedDryToWet: false},
    });
    expect(checkRule4B(derived, 31, {})).toBe(true);
  });

  test('does not fire when leaf wetness is dry', () => {
    const derived = buildDerived({
      airTempF: 32, dewPointSpreadF: 0.5, windSpeedMph: 2,
      leafWetness: {state: 'dry', justTransitionedDryToWet: false},
    });
    expect(checkRule4B(derived, 31, {})).toBe(false);
  });

  test('does not fire above the configured critical temperature', () => {
    const derived = buildDerived({
      airTempF: 32, dewPointSpreadF: 0.5, windSpeedMph: 2,
      leafWetness: {state: 'wet', justTransitionedDryToWet: false},
    });
    expect(checkRule4B(derived, 33, {})).toBe(false);
  });

  test('does not fire above the configured air-temperature bullet, even if bud-zone temp is at critical', () => {
    // Regression: checkRule4B originally omitted the spec's "Air
    // temperature <= 33F" bullet entirely (config.imminent4B_airTempMaxF
    // was wired into the schema/UI but never read by this function).
    const derived = buildDerived({
      airTempF: 34, dewPointSpreadF: 0.5, windSpeedMph: 2,
      leafWetness: {state: 'wet', justTransitionedDryToWet: false},
    });
    expect(checkRule4B(derived, 31, {})).toBe(false);
  });

  test('honors a farmer-configured air-temperature bullet', () => {
    const derived = buildDerived({
      airTempF: 34, dewPointSpreadF: 0.5, windSpeedMph: 2,
      leafWetness: {state: 'wet', justTransitionedDryToWet: false},
    });
    expect(checkRule4B(derived, 31, {imminent4B_airTempMaxF: 35})).toBe(true);
  });
});

describe('checkRule4C', () => {
  test('fires at or below the configured critical temperature', () => {
    expect(checkRule4C(32, {})).toBe(true);
    expect(checkRule4C(31, {})).toBe(true);
  });

  test('does not fire above it', () => {
    expect(checkRule4C(33, {})).toBe(false);
  });
});

describe('checkLevel5', () => {
  test('fires on sustained exposure at/below critical for the minimum duration', () => {
    expect(checkLevel5(31, {}, {timeBelowCriticalMinutes: 30})).toBe(true);
  });

  test('fires on a single-reading drop past the margin, even if just entering', () => {
    expect(checkLevel5(29, {}, {timeBelowCriticalMinutes: 0})).toBe(true);
  });

  test('does not fire when neither condition is met', () => {
    expect(checkLevel5(31, {}, {timeBelowCriticalMinutes: 10})).toBe(false);
  });
});

describe('checkLevel6AllClear', () => {
  const recovered = {recoveryStableMinutes: 35};

  test('fires when temp margin and stability are met, no forecast available', () => {
    expect(checkLevel6AllClear(36, {}, recovered, null)).toBe(true);
  });

  test('does not fire when temp margin is not yet met', () => {
    expect(checkLevel6AllClear(33, {}, recovered, null)).toBe(false);
  });

  test('does not fire when stability duration is not yet met', () => {
    expect(checkLevel6AllClear(36, {}, {recoveryStableMinutes: 5}, null)).toBe(false);
  });

  test('blocked by a forecasted decline back below critical', () => {
    expect(checkLevel6AllClear(36, {}, recovered, {minTempNextNHoursF: 30})).toBe(false);
  });

  test('not blocked when forecast stays at/above critical', () => {
    expect(checkLevel6AllClear(36, {}, recovered, {minTempNextNHoursF: 36})).toBe(true);
  });
});

describe('evaluateFrostLevel', () => {
  test('normal when nothing triggers', () => {
    const result = evaluateFrostLevel(buildInput());
    expect(result.level).toBe(ALERT_LEVEL.NORMAL);
    expect(result.subType).toBeNull();
  });

  test('watch fires immediately (no persistence requirement) for a frost-sensitive stage', () => {
    const result = evaluateFrostLevel(buildInput({
      growthStage: 'swollenBud',
      derived: buildDerived({
        airTempF: 40, coolingRate60FPerHr: -2.5, windSpeedMph: 3, dewPointSpreadF: 6,
      }),
    }));
    expect(result.level).toBe(ALERT_LEVEL.WATCH);
    expect(result.matchedRuleIds).toContain('rule2A');
  });

  test('watch suppressed for a dormant vine even if rule 2A conditions hold', () => {
    const result = evaluateFrostLevel(buildInput({
      growthStage: 'dormant',
      derived: buildDerived({
        airTempF: 40, coolingRate60FPerHr: -2.5, windSpeedMph: 3, dewPointSpreadF: 6,
      }),
    }));
    expect(result.level).toBe(ALERT_LEVEL.NORMAL);
  });

  test('warning requires the condition to persist across two consecutive readings', () => {
    const rule3ADerived = buildDerived({
      airTempF: 35, windSpeedMph: 2, coolingRate60FPerHr: -1.5,
      isNightOrLowLight: true, dewPointSpreadF: 3,
    });

    const tick1 = evaluateFrostLevel(buildInput({
      growthStage: 'budBreak', derived: rule3ADerived, nowIso: 't1',
    }));
    expect(tick1.level).not.toBe(ALERT_LEVEL.WARNING);

    const tick2 = evaluateFrostLevel(buildInput({
      growthStage: 'budBreak', derived: rule3ADerived,
      streaksInput: tick1.streaks, prevLevel: tick1.level, nowIso: 't2',
    }));
    expect(tick2.level).toBe(ALERT_LEVEL.WARNING);
    expect(tick2.subType).toBe(WARNING_SUBTYPE.RADIATION);
  });

  test('advective warning after persistence, subType advective', () => {
    const rule3CDerived = buildDerived({airTempF: 34, windSpeedMph: 6, coolingRate60FPerHr: -1});
    const forecast = {regionalFreezingAirIncoming: true};

    const tick1 = evaluateFrostLevel(buildInput({
      growthStage: 'budBreak', derived: rule3CDerived, forecast, nowIso: 't1',
    }));
    const tick2 = evaluateFrostLevel(buildInput({
      growthStage: 'budBreak', derived: rule3CDerived, forecast,
      streaksInput: tick1.streaks, prevLevel: tick1.level, nowIso: 't2',
    }));

    expect(tick2.level).toBe(ALERT_LEVEL.WARNING);
    expect(tick2.subType).toBe(WARNING_SUBTYPE.ADVECTIVE);
  });

  test('mixed subtype when a farmer-configured wind overlap lets 3A and 3C both hold', () => {
    const config = {warn3C_windMinMph: 1};
    const derived = buildDerived({
      airTempF: 35, windSpeedMph: 2, coolingRate60FPerHr: -1.5,
      isNightOrLowLight: true, dewPointSpreadF: 3,
    });
    const forecast = {regionalFreezingAirIncoming: true};

    const tick1 = evaluateFrostLevel(buildInput({
      growthStage: 'budBreak', derived, forecast, config, nowIso: 't1',
    }));
    const tick2 = evaluateFrostLevel(buildInput({
      growthStage: 'budBreak', derived, forecast, config,
      streaksInput: tick1.streaks, prevLevel: tick1.level, nowIso: 't2',
    }));

    expect(tick2.level).toBe(ALERT_LEVEL.WARNING);
    expect(tick2.subType).toBe(WARNING_SUBTYPE.MIXED);
    expect(tick2.matchedRuleIds).toEqual(expect.arrayContaining(['rule3A', 'rule3C']));
  });

  test('imminent via rule 4C', () => {
    const result = evaluateFrostLevel(buildInput({budZoneTempF: 31}));
    expect(result.level).toBe(ALERT_LEVEL.IMMINENT);
    expect(result.matchedRuleIds).toContain('rule4C');
  });

  test('event via level 5 sustained exposure', () => {
    const result = evaluateFrostLevel(buildInput({
      budZoneTempF: 30,
      eventAccumulators: {timeBelowCriticalMinutes: 35, recoveryStableMinutes: 0},
    }));
    expect(result.level).toBe(ALERT_LEVEL.EVENT);
  });

  test('recovery gating: holds at Event instead of silently dropping when All-Clear is not yet met', () => {
    const result = evaluateFrostLevel(buildInput({
      budZoneTempF: 35,
      prevLevel: ALERT_LEVEL.EVENT,
      eventAccumulators: {timeBelowCriticalMinutes: 0, recoveryStableMinutes: 10},
    }));
    expect(result.level).toBe(ALERT_LEVEL.EVENT);
  });

  test('holds at Imminent instead of dropping straight to Warning when All-Clear is not met', () => {
    // Regression: the recovery gate originally only intercepted a raw
    // computed level of exactly 'normal', so a partial recovery that still
    // satisfied a Warning rule (3A) skipped the All-Clear check entirely.
    const derived = buildDerived({
      airTempF: 34, dewPointSpreadF: 3, coolingRate60FPerHr: -1.5,
      windSpeedMph: 2, isNightOrLowLight: true,
      leafWetness: {state: 'dry', justTransitionedDryToWet: false},
    });
    const streaksInput = {
      rule3A: {consecutiveTrue: 2, lastTrueAt: 't0', lastEvalAt: 't0'},
      rule3B: {consecutiveTrue: 0, lastTrueAt: null, lastEvalAt: 't0'},
      rule3C: {consecutiveTrue: 0, lastTrueAt: null, lastEvalAt: 't0'},
    };
    const result = evaluateFrostLevel(buildInput({
      derived, budZoneTempF: 34, growthStage: 'budBreak', streaksInput,
      prevLevel: ALERT_LEVEL.IMMINENT,
      eventAccumulators: {timeBelowCriticalMinutes: 0, recoveryStableMinutes: 0},
    }));
    expect(result.level).toBe(ALERT_LEVEL.IMMINENT);
  });

  test('reaches All Clear once the recovery gate is fully satisfied', () => {
    const result = evaluateFrostLevel(buildInput({
      budZoneTempF: 36,
      prevLevel: ALERT_LEVEL.EVENT,
      eventAccumulators: {timeBelowCriticalMinutes: 0, recoveryStableMinutes: 35},
    }));
    expect(result.level).toBe(ALERT_LEVEL.ALL_CLEAR);
    expect(result.matchedRuleIds).toContain('level6AllClear');
  });

  test('holds at All Clear when the hold period has not yet elapsed', () => {
    const result = evaluateFrostLevel(buildInput({
      budZoneTempF: 36,
      prevLevel: ALERT_LEVEL.ALL_CLEAR,
      minutesInCurrentLevel: 20, // default allClearHoldMinutes is 60
      eventAccumulators: {timeBelowCriticalMinutes: 0, recoveryStableMinutes: 35},
    }));
    expect(result.level).toBe(ALERT_LEVEL.ALL_CLEAR);
  });

  test('reverts All Clear to Normal once the hold period elapses', () => {
    const result = evaluateFrostLevel(buildInput({
      budZoneTempF: 36,
      prevLevel: ALERT_LEVEL.ALL_CLEAR,
      minutesInCurrentLevel: 90,
      eventAccumulators: {timeBelowCriticalMinutes: 0, recoveryStableMinutes: 35},
    }));
    expect(result.level).toBe(ALERT_LEVEL.NORMAL);
  });

  test('a fresh escalation during the All-Clear hold period is not suppressed', () => {
    const result = evaluateFrostLevel(buildInput({
      budZoneTempF: 31,
      prevLevel: ALERT_LEVEL.ALL_CLEAR,
      minutesInCurrentLevel: 20,
      eventAccumulators: {timeBelowCriticalMinutes: 0, recoveryStableMinutes: 0},
    }));
    expect(result.level).toBe(ALERT_LEVEL.IMMINENT);
  });

  test('never downgrades on stale/missing data', () => {
    const held = evaluateFrostLevel(buildInput({
      prevLevel: ALERT_LEVEL.WARNING,
      dataQualityOk: false,
    }));
    expect(held.level).toBe(ALERT_LEVEL.WARNING);

    const droppedWhenDataIsGood = evaluateFrostLevel(buildInput({
      prevLevel: ALERT_LEVEL.WARNING,
      dataQualityOk: true,
    }));
    expect(droppedWhenDataIsGood.level).toBe(ALERT_LEVEL.NORMAL);
  });
});
