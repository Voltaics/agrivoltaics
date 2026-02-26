/**
 * Firebase Cloud Functions for Agrivoltaics
 *
 * Entry point for all Cloud Functions. Each function is implemented
 * in its own module under ./handlers.
 */

const {ingestSensorData} = require('./handlers/ingestSensorData');
const {setupBigQuery} = require('./handlers/setupBigQuery');
const {getHistoricalSeries} = require('./handlers/getHistoricalSeries');
const {checkAlerts} = require('./handlers/checkAlerts');

exports.ingestSensorData = ingestSensorData;
exports.setupBigQuery = setupBigQuery;
exports.getHistoricalSeries = getHistoricalSeries;
exports.checkAlerts = checkAlerts;
