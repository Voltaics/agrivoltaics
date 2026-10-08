const {
  computeElapsedMinutes,
  updateFieldQuality,
  updateDataQuality,
  createEmptyEventAccumulators,
  updateEventAccumulators,
  updateLeafWetnessTracking,
} = require('../accumulators');

describe('computeElapsedMinutes', () => {
  test('computes minutes between two ISO timestamps', () => {
    expect(computeElapsedMinutes('2026-01-01T00:00:00.000Z', '2026-01-01T00:15:00.000Z')).toBeCloseTo(15, 5);
  });

  test('null when there is no previous timestamp (first-ever tick)', () => {
    expect(computeElapsedMinutes(null, '2026-01-01T00:15:00.000Z')).toBeNull();
  });

  test('null when now is before prev (clock skew guard)', () => {
    expect(computeElapsedMinutes('2026-01-01T00:15:00.000Z', '2026-01-01T00:00:00.000Z')).toBeNull();
  });
});

describe('updateFieldQuality', () => {
  test('a fresh value clears staleness', () => {
    const result = updateFieldQuality(
        {stale: true, lastGoodAt: 't0', missedIntervals: 3},
        {hasFreshValue: true, nowIso: 't1', currentLevel: 'warning'},
    );
    expect(result).toEqual({stale: false, lastGoodAt: 't1', missedIntervals: 0});
  });

  test('goes stale after 2 missed intervals during Normal', () => {
    const miss1 = updateFieldQuality(null, {hasFreshValue: false, nowIso: 't1', currentLevel: 'normal'});
    expect(miss1.stale).toBe(false);

    const miss2 = updateFieldQuality(miss1, {hasFreshValue: false, nowIso: 't2', currentLevel: 'normal'});
    expect(miss2.stale).toBe(true);
  });

  test('goes stale after a single missed interval at Watch or higher', () => {
    const miss1 = updateFieldQuality(null, {hasFreshValue: false, nowIso: 't1', currentLevel: 'watch'});
    expect(miss1.stale).toBe(true);
  });

  test('retains lastGoodAt while missing data', () => {
    const miss1 = updateFieldQuality(
        {stale: false, lastGoodAt: 't0', missedIntervals: 0},
        {hasFreshValue: false, nowIso: 't1', currentLevel: 'normal'},
    );
    expect(miss1.lastGoodAt).toBe('t0');
  });
});

describe('updateDataQuality', () => {
  const allFresh = {temperature: true, humidity: true, windSpeed: true, leafMoisture: true, light: true};

  test('ok when every field is fresh', () => {
    const result = updateDataQuality(null, {freshFields: allFresh, nowIso: 't1', currentLevel: 'normal'});
    expect(result.overallFlag).toBe('ok');
  });

  test('sensor_unavailable specifically when temperature is stale (spec: primary sensor failure)', () => {
    const miss1 = updateDataQuality(null, {
      freshFields: Object.assign({}, allFresh, {temperature: false}),
      nowIso: 't1', currentLevel: 'watch',
    });
    expect(miss1.temperature.stale).toBe(true);
    expect(miss1.overallFlag).toBe('sensor_unavailable');
  });

  test('stale (not sensor_unavailable) when a non-temperature field goes stale', () => {
    const miss1 = updateDataQuality(null, {
      freshFields: Object.assign({}, allFresh, {windSpeed: false}),
      nowIso: 't1', currentLevel: 'watch',
    });
    expect(miss1.overallFlag).toBe('stale');
  });

  test('a dead light sensor is tracked too, not silently ignored', () => {
    // Regression: light was originally excluded from DATA_QUALITY_FIELDS even
    // though derivations.isNightOrLowLight (a Rule 3A input) fails safe to
    // false on a missing reading - a dead light sensor could silently
    // suppress Rule 3A without ever flipping dataQualityOk to false.
    const miss1 = updateDataQuality(null, {
      freshFields: Object.assign({}, allFresh, {light: false}),
      nowIso: 't1', currentLevel: 'watch',
    });
    expect(miss1.light.stale).toBe(true);
    expect(miss1.overallFlag).toBe('stale');
  });
});

describe('updateEventAccumulators', () => {
  const config = {criticalTempF: 32, allClearMarginF: 2};

  test('accumulates timeBelowCriticalMinutes while continuously below critical', () => {
    const tick1 = updateEventAccumulators(null, {
      budZoneTempF: 30, prevBudZoneTempF: null, coolingRate60FPerHr: -2, config,
      elapsedMinutes: 15, nowIso: 't1',
    });
    expect(tick1.timeBelowCriticalMinutes).toBe(15);
    expect(tick1.firstBelowCriticalAt).toBe('t1');

    const tick2 = updateEventAccumulators(tick1, {
      budZoneTempF: 29, prevBudZoneTempF: 30, coolingRate60FPerHr: -1, config,
      elapsedMinutes: 15, nowIso: 't2',
    });
    expect(tick2.timeBelowCriticalMinutes).toBe(30);
    expect(tick2.firstBelowCriticalAt).toBe('t1'); // unchanged across the same episode
    expect(tick2.minTempF).toBe(29);
  });

  test('resets timeBelowCriticalMinutes the moment temp rises back above critical', () => {
    const tick1 = updateEventAccumulators(null, {
      budZoneTempF: 30, prevBudZoneTempF: null, coolingRate60FPerHr: -2, config,
      elapsedMinutes: 15, nowIso: 't1',
    });
    const tick2 = updateEventAccumulators(tick1, {
      budZoneTempF: 33, prevBudZoneTempF: 30, coolingRate60FPerHr: 1, config,
      elapsedMinutes: 15, nowIso: 't2',
    });
    expect(tick2.timeBelowCriticalMinutes).toBe(0);
    expect(tick2.firstBelowCriticalAt).toBeNull();
  });

  test('tracks the fastest (most negative) cooling rate seen', () => {
    const tick1 = updateEventAccumulators(null, {
      budZoneTempF: 30, prevBudZoneTempF: null, coolingRate60FPerHr: -1, config,
      elapsedMinutes: 15, nowIso: 't1',
    });
    const tick2 = updateEventAccumulators(tick1, {
      budZoneTempF: 28, prevBudZoneTempF: 30, coolingRate60FPerHr: -3, config,
      elapsedMinutes: 15, nowIso: 't2',
    });
    expect(tick2.maxCoolingRateFPerHr).toBe(-3);
  });

  test('accumulates recoveryStableMinutes only when at/above the All-Clear margin and non-decreasing', () => {
    const tick1 = updateEventAccumulators(createEmptyEventAccumulators(), {
      budZoneTempF: 35, prevBudZoneTempF: 33, coolingRate60FPerHr: 1, config,
      elapsedMinutes: 15, nowIso: 't1',
    });
    expect(tick1.recoveryStableMinutes).toBe(15);

    const tick2 = updateEventAccumulators(tick1, {
      budZoneTempF: 34, prevBudZoneTempF: 35, coolingRate60FPerHr: -1, config,
      elapsedMinutes: 15, nowIso: 't2',
    });
    expect(tick2.recoveryStableMinutes).toBe(0); // temp fell - resets
  });

  test('holds prior accumulators unchanged when there is no reading this tick', () => {
    const prev = updateEventAccumulators(null, {
      budZoneTempF: 30, prevBudZoneTempF: null, coolingRate60FPerHr: -2, config,
      elapsedMinutes: 15, nowIso: 't1',
    });
    const held = updateEventAccumulators(prev, {
      budZoneTempF: null, prevBudZoneTempF: 30, coolingRate60FPerHr: null, config,
      elapsedMinutes: 15, nowIso: 't2',
    });
    expect(held).toEqual(prev);
  });
});

describe('updateLeafWetnessTracking', () => {
  test('accumulates continuousWetnessMinutes while continuously wet', () => {
    const tick1 = updateLeafWetnessTracking(null, {
      rawPercent: 40, state: 'wet', justTransitionedDryToWet: true, elapsedMinutes: 15, nowIso: 't1',
    });
    expect(tick1.continuousWetnessMinutes).toBe(0); // just transitioned this tick, nothing elapsed in this state yet
    expect(tick1.stateSince).toBe('t1');

    const tick2 = updateLeafWetnessTracking(tick1, {
      rawPercent: 45, state: 'wet', justTransitionedDryToWet: false, elapsedMinutes: 15, nowIso: 't2',
    });
    expect(tick2.continuousWetnessMinutes).toBe(15);
    expect(tick2.stateSince).toBe('t1');
  });

  test('resets continuousWetnessMinutes to zero once dry', () => {
    const tick1 = updateLeafWetnessTracking(null, {
      rawPercent: 40, state: 'wet', justTransitionedDryToWet: true, elapsedMinutes: 15, nowIso: 't1',
    });
    const tick2 = updateLeafWetnessTracking(tick1, {
      rawPercent: 10, state: 'dry', justTransitionedDryToWet: false, elapsedMinutes: 15, nowIso: 't2',
    });
    expect(tick2.continuousWetnessMinutes).toBe(0);
    expect(tick2.state).toBe('dry');
    expect(tick2.stateSince).toBe('t2');
  });
});
