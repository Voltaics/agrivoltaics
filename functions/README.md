# Agrivoltaics Firebase Cloud Functions

This folder contains the active Firebase Cloud Functions for ingestion, analytics APIs, and alert operations.

## Active Handlers

Exported from index.js:

- ingestSensorData
- setupBigQuery
- getHistoricalSeries
- getFrostPredictionSeries
- sendTestAlert

## Local Setup

### Prerequisites

- Node.js 20
- Firebase CLI
- Access to Firebase project agrivoltaics-flutter-firebase

### Install and run

```bash
cd functions
npm install
npm run lint
npm run serve
```

Emulator defaults:

- Functions: http://localhost:5001
- Firestore: http://localhost:8080
- Emulator UI: http://localhost:4000

## Deploy

```bash
npm run deploy
```

## Core API Contracts

### ingestSensorData (POST)

Purpose:

- validate incoming sensor payload
- update current sensor fields in Firestore
- append historical rows to BigQuery
- run alert checks

Request shape:

```json
{
  "organizationId": "ORG",
  "siteId": "SITE",
  "zoneId": "ZONE",
  "sensors": [
    {
      "sensorId": "SENSOR",
      "timestamp": 1710000000,
      "readings": {
        "temperature": {"value": 72.5, "unit": "F"}
      }
    }
  ]
}
```

### getHistoricalSeries (POST)

Purpose: return chart-ready historical time series by reading and zone.

Request shape:

```json
{
  "organizationId": "ORG",
  "siteId": "SITE",
  "zoneIds": ["ZONE"],
  "readings": ["temperature"],
  "start": "2026-04-01T00:00:00Z",
  "end": "2026-04-08T00:00:00Z",
  "aggregation": "AVG"
}
```

Note: auth verification is currently disabled in handler code and should be re-enabled for production hardening.

### getFrostPredictionSeries (POST)

Purpose: return a bucketed frost timeline for one zone.

### setupBigQuery (POST)

Purpose: create/verify BigQuery dataset and required tables.

### sendTestAlert (POST)

Purpose: send synthetic notifications for a specific alert rule.

Requires Firebase ID token in Authorization header.

## BigQuery Tables

Managed under dataset sensor_data:

- readings
- alerts
- frost_predictions (consumed by frost timeline flow)

## Monitoring

```bash
npm run logs
firebase functions:log --only ingestSensorData
```

## Canonical References

- ../docs/Developer-Handoff.md
- ../docs/DataModel.md
- ../docs/Applicable-Software.md
