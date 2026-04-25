# Agrivoltaics Developer Handoff Guide

Last updated: 2026-04-21

## LEGACY NOTICE (READ FIRST)

Anything labeled Legacy in this document is not part of the primary development path for the next team.

Use only the active paths and canonical software references for day-to-day development.

## 1. Purpose

This document is the primary handoff guide for the next team maintaining the Agrivoltaics codebase. It covers:

- repository layout and ownership boundaries
- local development and runtime setup
- Firebase, Firestore, and BigQuery architecture
- Cloud Functions APIs and data flow
- Flutter app architecture and service layer design
- auxiliary Python services (weather, pest detection, Pi pipeline)
- deployment, operations, troubleshooting, and known issues

If this guide conflicts with code, the code is authoritative.

## 2. System Summary

The system is a multi-component platform for vineyard monitoring and analytics:

- Flutter app for organization/site/zone/sensor management, dashboards, and alerts
- Firebase Auth + Firestore for identity, app state, and metadata
- Firebase Cloud Functions for ingestion, alert processing, and analytics APIs
- BigQuery as historical and analytical storage
- Pi-side pipeline and ML services for image capture and disease/pest workflows

High-level data flow:

1. Sensors send readings to Cloud Function ingest endpoint.
2. Function updates Firestore current state and writes historical points to BigQuery.
3. Alert rules are evaluated; in-app notifications and FCM pushes are generated.
4. Flutter app renders real-time Firestore data + historical/frost timelines from BigQuery-backed APIs.

## 3. Repository Map

Top-level repository includes active code plus historical/legacy artifacts. Use this map when deciding where to work.

### 3.1 Core active paths

- application/agrivoltaics_flutter_app: main Flutter client
- functions: Firebase Cloud Functions (Node.js)
- docs: architecture and data model docs
- application/pi_code: Raspberry Pi capture and upload pipeline
- application/pest_detection_backend: FastAPI pest classifier service

### 3.2 Additional paths (Legacy/Support)

- Legacy: application/microservices/py-weather-api
- Legacy: application/microservices/py-weather-microservice
- Support: application/model_training
- Legacy: application/flutter_demo_app, application/flutter_sample_app, migration_temp_app
- Legacy: docker_app
- Support: assignments

## 4. Source of Truth and Documentation Policy

### 4.1 Current data model

Primary Firestore source of truth is:

- docs/DataModel.md

This was updated to reflect current collections and fields actually used by app/functions.

### 4.2 Existing docs with caveats

- functions/README.md contains useful setup guidance, but parts are outdated (references functions not in current handlers).
- docs/UIFeatures.md describes intended UX/features and is partially aspirational.

Recommendation: treat code + docs/DataModel.md as canonical for implementation decisions.

## 5. Runtime Architecture

## 5.1 Flutter client

Main app lives in application/agrivoltaics_flutter_app.

Key architecture:

- Entry: lib/main.dart
- Global state: Provider + ChangeNotifier in lib/app_state.dart
- Domain services: lib/services/* (Firestore access, alert APIs, historical APIs)
- Models: lib/models/*
- UI pages: lib/pages/*

Major app domains:

- Authentication and organization selection
- Stationary dashboard (site/zone/sensor management)
- Historical dashboard (multi-series BigQuery-backed chart data)
- Alerts page (alert rule CRUD + notifications)
- Mobile dashboard (capture listing/details from captures collection)

## 5.2 Firebase/Functions

Functions live in functions and export from functions/index.js:

- ingestSensorData
- setupBigQuery
- getHistoricalSeries
- sendTestAlert
- getFrostPredictionSeries

Infra config:

- firebase.json defines functions source and emulator ports
  - functions: 5001
  - firestore: 8080
  - emulator UI: 4000

## 5.3 Data stores

- Firestore: operational state, metadata, app collections
- BigQuery dataset sensor_data:
  - readings table (historical sensor time series)
  - alerts table (rule trigger records)
  - frost_predictions table (read by frost timeline endpoint)

## 5.4 Auxiliary services

- Pi pipeline uploads captures and ML output to Firebase (application/pi_code)
- Pest detection backend (FastAPI, Torch) exposes /pests_predict
- Legacy weather services are Legacy

## 6. Development Environment Setup

## 6.1 Prerequisites

Install:

- Flutter SDK (matching repository app constraints; Dart >=3.0.0 <4.0.0 in pubspec)
- Node.js 20 for functions
- Firebase CLI
- Python 3.10 for Python services
- Google Cloud SDK (for some BigQuery/admin workflows)

## 6.2 Firebase access

You need project access for:

- Firebase Auth
- Firestore
- Cloud Functions
- BigQuery
- Cloud Storage
- Cloud Tasks (for frost trigger queue flow)

## 6.3 Flutter setup

From application/agrivoltaics_flutter_app:

```bash
flutter pub get
flutter run -d chrome
```

Optional quality checks:

```bash
flutter analyze
flutter test
```

## 6.4 Functions setup

From functions:

```bash
npm install
npm run lint
npm run serve
```

Deploy:

```bash
npm run deploy
```

## 6.5 Python services setup

### Pest detection backend

From application/pest_detection_backend:

```bash
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8080
```

### Weather microservice (legacy)

Legacy. Do not use as part of the primary development workflow.

### Pi pipeline

From application/pi_code, run pipeline entry script:

```bash
python start_pipeline.py --mode single
# or
python start_pipeline.py --mode continuous
```

Note: script path assumptions are hardcoded for specific filesystem locations; adjust before production use on new hardware.

## 7. Configuration and Secrets

## 7.1 Flutter runtime environment variables

Defined through String.fromEnvironment in lib/app_constants.dart:

- INFLUXDB_URL (legacy)
- INFLUXDB_TOKEN (legacy)
- INFLUXDB_ORG (legacy)
- INFLUXDB_BUCKET (legacy)
- INFLUXDB_DEBUG (legacy)
- AUTHORIZED_EMAILS (used for whitelist)
- TIMEZONE
- HISTORICAL_SERIES_ENDPOINT
- FROST_PREDICTION_SERIES_ENDPOINT

Example:

```bash
flutter run -d chrome \
  --dart-define=HISTORICAL_SERIES_ENDPOINT=https://.../getHistoricalSeries \
  --dart-define=FROST_PREDICTION_SERIES_ENDPOINT=https://.../getFrostPredictionSeries
```

## 7.2 Firebase options

Client Firebase project settings are generated in lib/firebase_options.dart.

Regenerate with FlutterFire CLI when project config changes.

## 7.3 Organization creation gate

Current app logic restricts org creation to a specific UID/email pair in lib/app_constants.dart.

If this is no longer desired, remove or redesign this gate.

## 7.4 Functions environment

No extensive runtime config is currently required for core handlers, but ensure service account permissions for:

- Firestore read/write
- BigQuery read/write
- Cloud Tasks enqueue
- FCM send (Firebase Messaging)

## 8. Firestore and BigQuery Data Model

## 8.1 Firestore

Use docs/DataModel.md for canonical collection structures.

Key active collections:

- users
- organizations
  - members
  - pendingInvites
  - sites
    - zones
      - sensors
      - frostRunLock/lease
  - alertRules
- readings
- sensorLookup
- notifications
- captures

## 8.2 BigQuery

Managed by setupBigQuery and function code.

Dataset:

- sensor_data

Tables:

- readings
  - partitioned by timestamp (day)
  - clustered by sensorId, field
- alerts
  - partitioned by triggeredAt
  - clustered by organizationId, ruleId
- frost_predictions
  - consumed by getFrostPredictionSeries
  - creation/population is external to current setupBigQuery implementation

## 9. Cloud Function APIs and Behavior

## 9.1 ingestSensorData

Purpose:

- validate incoming sensor payload
- update sensor field values in Firestore
- write rows to BigQuery readings table
- decide whether to enqueue frost trigger task (with per-zone lease lock)
- evaluate alert rules and dispatch notifications

Important behavior:

- validates sensor and reading structure
- checks reading aliases against Firestore readings collection
- computes primarySensor flag using zone readings map
- uses Cloud Tasks for frost job orchestration
- runs alert checks non-fatally (ingest succeeds even if alerts fail)

## 9.2 setupBigQuery

Purpose:

- one-time or repeat-safe setup of dataset/tables and schema checks

Creates/verifies:

- sensor_data.readings
- sensor_data.alerts

## 9.3 getHistoricalSeries

Purpose:

- return aggregated historical graph-ready data

Request fields include:

- organizationId, siteId, zoneIds, readings, start, end
- optional interval, sensorId, timezone, aggregation

Notes:

- authentication check is currently commented out (explicit TODO in code)
- supports dynamic interval selection and aggregation (AVG/MIN/MAX)

## 9.4 getFrostPredictionSeries

Purpose:

- return a bucketed timeline for a single zone including sensor context and predictedChance

Depends on:

- readings table
- frost_predictions table

## 9.5 sendTestAlert

Purpose:

- trigger a synthetic alert notification for a specific rule for verification

Notes:

- requires Firebase ID token
- builds synthetic payloads by rule type (threshold, frost_warning, mold_risk, black_rot_risk)

## 10. Flutter App Internals

## 10.1 State management

Global state in AppState includes:

- selected organization, site, zone
- user profile snapshot
- date ranges and selections for historical and frost timelines
- loaded historical/frost responses and loading/error flags
- some legacy structures retained for migration compatibility

## 10.2 Service layer

Core services and responsibilities:

- user_service.dart: user doc lifecycle + pending invite acceptance
- organization_service.dart: org CRUD, membership, invite workflow
- site_service.dart: site CRUD, nested deletion handling
- zone_service.dart: zone CRUD, primary sensor mapping
- sensor_service.dart: sensor CRUD + field updates + lookup sync
- sensor_lookup_service.dart: sensorLookup maintenance
- readings_service.dart: reading definitions cache
- alert_service.dart: alert rule CRUD under org
- historical_series_service.dart: client for historical API
- frost_prediction_series_service.dart: client for frost timeline API
- fcm_service.dart: token registration and refresh handling

## 10.3 Notifications path

- In-app notifications are stored in Firestore notifications collection.
- UI stream is in pages/home/notifications.dart.
- Read action sets isRead true and readAt server timestamp.

## 10.4 Alerts flow

- Alert rules are created in organizations/{orgId}/alertRules.
- Background alert checks run in ingest path.
- When triggered:
  - rule lastFiredAt is updated
  - BigQuery alerts event written
  - in-app notifications created
  - FCM multicast attempted for each token
  - invalid tokens pruned from user docs

## 11. Pi Imaging and ML Paths

## 11.1 Pi pipeline

Pipeline stages in application/pi_code:

- capture images
- align images
- process images
- run inference
- upload metadata and assets to Firebase

Current scripts include absolute/hardcoded paths and should be normalized for portability.

## 11.2 Captures collection

Mobile dashboard reads from captures, including:

- timestamp
- url list
- detected_disease
- optional analysis fields

## 11.3 Pest detection backend

FastAPI app loads ResNet18-based model from pest_presence_resnet.pth and returns prediction + confidence at /pests_predict.

## 12. Local Development Workflows

## 12.1 Recommended day-to-day loop

1. Start Firebase emulators for functions/firestore where needed.
2. Run Flutter app locally (usually web target for quick UI iteration).
3. Use test payloads/scripts for ingestion and historical endpoints.
4. Use sendTestAlert to validate rule notification behavior.

## 12.2 Mock data for analytics UI

Use functions/utils/load_mock_data.py to seed historical BigQuery data. This is valuable for frontend chart development without hardware dependencies.

## 12.3 API smoke test commands

Ingest example shape:

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

Historical endpoint example shape:

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

## 13. Deployment and Operations

## 13.1 Firebase functions deployment

From functions:

```bash
npm run deploy
```

Predeploy lint is configured in firebase.json.

## 13.2 BigQuery setup runbook

After first deploy or infra reset:

1. Deploy functions.
2. Call setupBigQuery endpoint.
3. Verify dataset/tables in BigQuery console.

## 13.3 Monitoring and logs

Use Firebase functions log commands:

```bash
firebase functions:log
firebase functions:log --only ingestSensorData
```

Also monitor:

- BigQuery job errors and quota
- Firestore write/read costs
- Cloud Tasks queue health for frost job flow
- FCM send failures and token churn

## 14. Security and Access Notes

## 14.1 Current risk: historical endpoint auth

getHistoricalSeries has auth verification intentionally disabled in current code. This should be prioritized before production hardening.

## 14.2 Token handling

Users may have both legacy fcmToken and active fcmTokens patterns. Standardize around array-based multi-device tokens.

## 14.3 Legacy Mongo services

Legacy. Not part of the primary development workflow.

## 15. Known Issues and Technical Debt

- Functions README references handlers that are not currently exported.
- Mixed legacy/new data patterns exist in app state and model fields.
- Absolute paths in Pi pipeline reduce portability.
- Multiple app folders can confuse onboarding; only one Flutter app is primary.
- Historical auth TODO should be addressed.
- Some endpoint contracts differ from older docs.

## 16. Suggested Next-Team Priorities

1. Normalize docs and remove drift (especially Functions docs and API references).
2. Re-enable and enforce auth on analytics endpoints.
3. Consolidate FCM token schema and remove legacy writes.
4. Add automated integration tests for ingest to alerts flow.
5. Externalize Pi pipeline paths and secrets.
6. Add CI for Flutter analyze/test and functions lint/test.
7. Clarify active vs archived subprojects in repository root docs.

## 17. Handoff Checklist

Use this checklist when onboarding a new engineer:

- [ ] Access granted to Firebase project and BigQuery dataset
- [ ] Flutter app runs locally
- [ ] setupBigQuery verified in target project
- [ ] ingestSensorData tested with sample payload
- [ ] getHistoricalSeries tested with seeded BigQuery data
- [ ] sendTestAlert tested with valid Firebase auth token
- [ ] Firestore DataModel doc reviewed
- [ ] Secrets and environment variables documented in local env notes
- [ ] Legacy modules identified and intentionally included/excluded from active scope

## 18. Quick Reference Commands

### Flutter

```bash
cd application/agrivoltaics_flutter_app
flutter pub get
flutter run -d chrome
flutter analyze
flutter test
```

### Functions

```bash
cd functions
npm install
npm run lint
npm run serve
npm run deploy
firebase functions:log
```

### Pest backend

```bash
cd application/pest_detection_backend
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8080
```

### Weather worker (legacy)

Legacy. Not part of the primary development workflow.

### Pi pipeline

```bash
cd application/pi_code
python start_pipeline.py --mode single
```

## 19. Ownership Boundaries (Recommended)

For continuity, assign explicit maintainers:

- Mobile/Web app team: application/agrivoltaics_flutter_app
- Backend/data team: functions + BigQuery schema and operations
- Edge/vision team: application/pi_code + application/pest_detection_backend + model_training
- Documentation/integration owner: docs and API contracts

This reduces regression risk during multi-team handoff.

## 20. Final Notes

- Keep docs/DataModel.md synchronized with any schema changes.
- Treat this file as living documentation; update date and change notes each sprint.
- Prefer additive, backward-compatible schema/API changes unless there is a coordinated migration plan.
