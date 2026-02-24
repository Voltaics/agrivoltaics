const admin = require('firebase-admin');
const {BigQuery} = require('@google-cloud/bigquery');

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();
const bigquery = new BigQuery();

const DATASET_ID = 'sensor_data';
const TABLE_ID = 'readings';

module.exports = {
  admin,
  db,
  bigquery,
  DATASET_ID,
  TABLE_ID,
};
