/**
 * Firebase Cloud Functions for Agrivoltaics
 *
 * Entry point for all Cloud Functions. Each function is implemented
 * in its own module under ./handlers or ./lib.
 */

const {ingestSensorData} = require('./handlers/ingestSensorData');
const {setupBigQuery} = require('./handlers/setupBigQuery');
const {getHistoricalSeries} = require('./handlers/getHistoricalSeries');
const {sendTestAlert} = require('./handlers/sendTestAlert');
const {getFrostPredictionSeries} = require('./handlers/getFrostPredictionSeries');

// Staleness sweep (scheduled) and test-trigger (HTTP)
// for the frost alert engine.
const {sweepFrostStaleness} = require('./lib/frostEngine/sweepFrostStaleness');
const {testTriggerFrostAlert} = require('./lib/frostEngine/testTriggerFrostAlert');

exports.ingestSensorData = ingestSensorData;
exports.setupBigQuery = setupBigQuery;
exports.getHistoricalSeries = getHistoricalSeries;
exports.sendTestAlert = sendTestAlert;
exports.getFrostPredictionSeries = getFrostPredictionSeries;

// New Cloud Functions for frost alert production readiness.
// sweepFrostStaleness: runs every 15 min to detect dead sensors and flag stale data.
// testTriggerFrostAlert: authenticated endpoint to simulate frost conditions for QA/demo.
exports.sweepFrostStaleness = sweepFrostStaleness;
exports.testTriggerFrostAlert = testTriggerFrostAlert;

