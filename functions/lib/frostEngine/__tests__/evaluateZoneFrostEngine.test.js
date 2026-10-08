jest.mock('../../firebase', () => ({
  db: {doc: jest.fn()},
}));
jest.mock('../context', () => ({
  fetchRecentEngineContext: jest.fn(),
}));
jest.mock('../stateStore', () => ({
  loadEngineState: jest.fn(),
  saveEngineState: jest.fn(),
}));

const {db} = require('../../firebase');
const {fetchRecentEngineContext} = require('../context');
const {loadEngineState, saveEngineState} = require('../stateStore');
const {evaluateZoneFrostEngine, MIN_EVAL_INTERVAL_MINUTES} = require('../evaluateZoneFrostEngine');

const ORG = 'org1';
const SITE = 'site1';
const ZONE = 'zone1';
const NOW = new Date('2026-01-01T00:30:00.000Z');

/**
 * @param {boolean} exists
 * @param {Object} [data]
 * @return {Object} A fake Firestore DocumentSnapshot.
 */
function fakeSnapshot(exists, data) {
  return {exists, data: () => data};
}

/**
 * @param {Object} [overrides]
 * @return {Object} A default engine state with no throttling concerns.
 */
function baselineState(overrides) {
  return Object.assign({
    currentLevel: 'normal',
    previousLevel: null,
    activeSubWarning: null,
    levelEnteredAt: '2026-01-01T00:00:00.000Z',
    lastNotifiedLevel: null,
    ruleStreaks: {
      rule3A: {consecutiveTrue: 0, lastTrueAt: null, lastEvalAt: null},
      rule3B: {consecutiveTrue: 0, lastTrueAt: null, lastEvalAt: null},
      rule3C: {consecutiveTrue: 0, lastTrueAt: null, lastEvalAt: null},
    },
    leafWetness: {
      rawValue: null, state: 'dry', stateSince: null,
      continuousWetnessMinutes: 0, justTransitionedDryToWet: false,
    },
    eventAccumulators: {
      minTempF: null, timeBelowCriticalMinutes: 0, timeBelow32Minutes: 0, timeBelow30Minutes: 0,
      maxCoolingRateFPerHr: null, firstBelowCriticalAt: null, recoveryStableMinutes: 0,
    },
    postEventLog: null,
    dataQuality: {
      temperature: {stale: false, lastGoodAt: null, missedIntervals: 0},
      humidity: {stale: false, lastGoodAt: null, missedIntervals: 0},
      windSpeed: {stale: false, lastGoodAt: null, missedIntervals: 0},
      leafMoisture: {stale: false, lastGoodAt: null, missedIntervals: 0},
      light: {stale: false, lastGoodAt: null, missedIntervals: 0},
      overallFlag: 'ok',
    },
    derivedSnapshot: {},
    // 15 min before NOW - clear of the throttle window, matches the spec's reporting cadence.
    lastEvalIso: '2026-01-01T00:15:00.000Z',
  }, overrides || {});
}

/** @return {Object} A "nothing interesting is happening" BigQuery context. */
function baselineContext() {
  return {current: {}, temperatureAt: {15: null, 30: null, 60: null, 120: null}};
}

beforeEach(() => {
  jest.clearAllMocks();
});

describe('evaluateZoneFrostEngine', () => {
  test('skips when the zone doc does not exist', async () => {
    db.doc.mockReturnValue({get: jest.fn().mockResolvedValue(fakeSnapshot(false))});

    const result = await evaluateZoneFrostEngine({organizationId: ORG, siteId: SITE, zoneId: ZONE, now: NOW});
    expect(result).toEqual({skipped: true, reason: 'zone_not_found'});
    expect(loadEngineState).not.toHaveBeenCalled();
  });

  test('skips when frostRuleConfig.enabled is not true', async () => {
    db.doc.mockReturnValue({
      get: jest.fn().mockResolvedValue(fakeSnapshot(true, {frostRuleConfig: {enabled: false}})),
    });

    const result = await evaluateZoneFrostEngine({organizationId: ORG, siteId: SITE, zoneId: ZONE, now: NOW});
    expect(result).toEqual({skipped: true, reason: 'disabled'});
    expect(loadEngineState).not.toHaveBeenCalled();
  });

  test('skips as throttled when the last evaluation was too recent', async () => {
    db.doc.mockReturnValue({
      get: jest.fn().mockResolvedValue(fakeSnapshot(true, {frostRuleConfig: {enabled: true}})),
    });
    loadEngineState.mockResolvedValue(baselineState({
      lastEvalIso: new Date(NOW.getTime() - (MIN_EVAL_INTERVAL_MINUTES - 1) * 60000).toISOString(),
    }));

    const result = await evaluateZoneFrostEngine({organizationId: ORG, siteId: SITE, zoneId: ZONE, now: NOW});
    expect(result.skipped).toBe(true);
    expect(result.reason).toBe('throttled');
    expect(fetchRecentEngineContext).not.toHaveBeenCalled();
    expect(saveEngineState).not.toHaveBeenCalled();
  });

  test('runs on the very first evaluation (lastEvalIso null) regardless of MIN_EVAL_INTERVAL_MINUTES', async () => {
    db.doc.mockReturnValue({
      get: jest.fn().mockResolvedValue(fakeSnapshot(true, {frostRuleConfig: {enabled: true}})),
    });
    loadEngineState.mockResolvedValue(baselineState({lastEvalIso: null}));
    fetchRecentEngineContext.mockResolvedValue(baselineContext());
    saveEngineState.mockResolvedValue();

    const result = await evaluateZoneFrostEngine({organizationId: ORG, siteId: SITE, zoneId: ZONE, now: NOW});
    expect(result.skipped).toBe(false);
    expect(saveEngineState).toHaveBeenCalledTimes(1);
  });

  test('reaches Imminent from a cold bud-zone reading and persists it', async () => {
    db.doc.mockReturnValue({
      get: jest.fn().mockResolvedValue(fakeSnapshot(true, {frostRuleConfig: {enabled: true, criticalTempF: 32}})),
    });
    loadEngineState.mockResolvedValue(baselineState());
    fetchRecentEngineContext.mockResolvedValue({
      current: {
        temperature: {value: 31, unit: 'F', sensorId: 's1', timestamp: NOW.toISOString(), primarySensor: true},
      },
      temperatureAt: {15: null, 30: null, 60: null, 120: null},
    });
    saveEngineState.mockResolvedValue();

    const result = await evaluateZoneFrostEngine({organizationId: ORG, siteId: SITE, zoneId: ZONE, now: NOW});

    expect(result).toEqual({
      skipped: false, level: 'imminent', levelChanged: true, matchedRuleIds: ['rule4C'],
    });
    expect(saveEngineState).toHaveBeenCalledWith(expect.objectContaining({
      organizationId: ORG, siteId: SITE, zoneId: ZONE,
      nextState: expect.objectContaining({currentLevel: 'imminent', previousLevel: 'normal'}),
    }));
  });

  test('holds at All Clear when the hold period has not yet elapsed', async () => {
    db.doc.mockReturnValue({
      get: jest.fn().mockResolvedValue(fakeSnapshot(true, {frostRuleConfig: {enabled: true, criticalTempF: 32}})),
    });
    loadEngineState.mockResolvedValue(baselineState({
      currentLevel: 'allClear',
      levelEnteredAt: new Date(NOW.getTime() - 20 * 60000).toISOString(), // 20 min ago, default hold is 60 min
      eventAccumulators: {
        minTempF: 29, timeBelowCriticalMinutes: 0, timeBelow32Minutes: 0, timeBelow30Minutes: 0,
        maxCoolingRateFPerHr: -3, firstBelowCriticalAt: null, recoveryStableMinutes: 30,
      },
    }));
    fetchRecentEngineContext.mockResolvedValue({
      current: {
        temperature: {value: 50, unit: 'F', sensorId: 's1', timestamp: NOW.toISOString(), primarySensor: true},
      },
      temperatureAt: {15: null, 30: null, 60: null, 120: null},
    });
    saveEngineState.mockResolvedValue();

    await evaluateZoneFrostEngine({organizationId: ORG, siteId: SITE, zoneId: ZONE, now: NOW});

    const savedArgs = saveEngineState.mock.calls[0][0];
    expect(savedArgs.nextState.currentLevel).toBe('allClear');
    expect(savedArgs.nextState.eventAccumulators.minTempF).not.toBeNull(); // not reset yet
  });

  test('reverts to Normal and resets episode accumulators once the All-Clear hold period elapses', async () => {
    db.doc.mockReturnValue({
      get: jest.fn().mockResolvedValue(fakeSnapshot(true, {frostRuleConfig: {enabled: true, criticalTempF: 32}})),
    });
    loadEngineState.mockResolvedValue(baselineState({
      currentLevel: 'allClear',
      levelEnteredAt: new Date(NOW.getTime() - 90 * 60000).toISOString(), // 90 min ago, past the 60-min default hold
      eventAccumulators: {
        minTempF: 29, timeBelowCriticalMinutes: 0, timeBelow32Minutes: 0, timeBelow30Minutes: 0,
        maxCoolingRateFPerHr: -3, firstBelowCriticalAt: null, recoveryStableMinutes: 30,
      },
      postEventLog: {
        minTempF: 29, timeBelowCriticalMinutes: 45, timeBelow32Minutes: 45, timeBelow30Minutes: 0,
        maxCoolingRateFPerHr: -3, firstBelowCriticalAt: null, recoveryStableMinutes: 0,
      },
    }));
    fetchRecentEngineContext.mockResolvedValue({
      current: {
        temperature: {value: 50, unit: 'F', sensorId: 's1', timestamp: NOW.toISOString(), primarySensor: true},
      },
      temperatureAt: {15: null, 30: null, 60: null, 120: null},
    });
    saveEngineState.mockResolvedValue();

    await evaluateZoneFrostEngine({organizationId: ORG, siteId: SITE, zoneId: ZONE, now: NOW});

    const savedArgs = saveEngineState.mock.calls[0][0];
    expect(savedArgs.nextState.currentLevel).toBe('normal');
    expect(savedArgs.nextState.eventAccumulators).toEqual({
      minTempF: null, timeBelowCriticalMinutes: 0, timeBelow32Minutes: 0, timeBelow30Minutes: 0,
      maxCoolingRateFPerHr: null, firstBelowCriticalAt: null, recoveryStableMinutes: 0,
    });
    expect(savedArgs.nextState.postEventLog).toBeNull();
  });

  test('a dead light sensor does not silently drop an active radiation Warning', async () => {
    // Regression: light wasn't tracked by dataQuality, so isNightOrLowLight
    // failing safe to `false` on a missing reading could reset Rule 3A's
    // streak and let the level fall - without dataQualityOk ever going
    // false to trigger the never-downgrade guard.
    db.doc.mockReturnValue({
      get: jest.fn().mockResolvedValue(fakeSnapshot(true, {
        frostRuleConfig: {enabled: true, criticalTempF: 32, growthStage: 'budBreak'},
      })),
    });
    loadEngineState.mockResolvedValue(baselineState({
      currentLevel: 'warning',
      activeSubWarning: 'radiation',
      ruleStreaks: {
        rule3A: {consecutiveTrue: 2, lastTrueAt: '2026-01-01T00:15:00.000Z', lastEvalAt: '2026-01-01T00:15:00.000Z'},
        rule3B: {consecutiveTrue: 0, lastTrueAt: null, lastEvalAt: null},
        rule3C: {consecutiveTrue: 0, lastTrueAt: null, lastEvalAt: null},
      },
    }));
    fetchRecentEngineContext.mockResolvedValue({
      current: {
        temperature: {value: 34, unit: 'F', sensorId: 's1', timestamp: NOW.toISOString(), primarySensor: true},
        humidity: {value: 80, unit: '%', sensorId: 's1', timestamp: NOW.toISOString(), primarySensor: true},
        windSpeed: {value: 2, unit: 'mph', sensorId: 's1', timestamp: NOW.toISOString(), primarySensor: true},
        leafMoisture: {value: 35, unit: '%', sensorId: 's1', timestamp: NOW.toISOString(), primarySensor: true},
        // no `light` entry - simulates a dead/unreporting light sensor.
      },
      temperatureAt: {
        15: null, 30: null,
        60: {value: 35.5, unit: 'F', sensorId: 's1', timestamp: NOW.toISOString(), primarySensor: true},
        120: null,
      },
    });
    saveEngineState.mockResolvedValue();

    const result = await evaluateZoneFrostEngine({organizationId: ORG, siteId: SITE, zoneId: ZONE, now: NOW});

    // Raw conditions this tick no longer satisfy Rule 3A (isNightOrLowLight
    // fails safe to false without a light reading), so without the fix this
    // would silently compute down to 'normal'.
    expect(result.level).toBe('warning');
    const savedArgs = saveEngineState.mock.calls[0][0];
    expect(savedArgs.nextState.dataQuality.light.stale).toBe(true);
    expect(savedArgs.nextState.dataQuality.overallFlag).toBe('stale');
  });
});
