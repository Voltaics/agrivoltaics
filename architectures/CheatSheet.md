 # Architecture 1A. Component Inventory

This diagram is a high-level map of the system's major components. It separates data producers, client applications, Firebase services, background compute, and specialized Cloud Run services.

## Edge / Hardware

- **ESP32 sensor nodes** collect environmental sensor readings.
- **Raspberry Pi + multispectral camera** captures plant images for image-processing workflows.

## Client

- The **Flutter App** runs on web, iOS, and Android.
- It is used to view live sensor data, historical charts, frost predictions, alerts, and captured images.

## Firebase Data / Messaging

- **Firestore** stores operational and real-time application data.
- **Firebase Storage** stores captured image files.
- **FCM** delivers push notifications to mobile clients.

## GCP Async Compute

- **Cloud Tasks** queues background work.
- The **Zone_Frost Cloud Run Job** performs frost-prediction processing.
- **BigQuery** stores historical sensor readings.
- **GCS checkpoints** stores machine-learning model checkpoints.

## Firebase Cloud Functions

- `ingestSensorData` processes incoming sensor readings.
- `getHistoricalSeries` retrieves historical data for charts.
- `getFrostPredictionSeries` retrieves frost-prediction data.
- `sendTestAlert` sends manually triggered test alerts.
- `setupBigQuery` configures the BigQuery integration.

## Sibling Cloud Run Services

- **Multispectral_Container** processes multispectral imagery.
- **pest_detection_backend** provides pest-detection functionality.
- **notification-api** handles notification-related operations.

## Overall Flow

Hardware produces sensor readings and images. Firebase and BigQuery store the resulting data, while Cloud Functions and asynchronous GCP workloads process it. The Flutter client reads the processed data and receives notifications through Firebase Cloud Messaging.

# Architecture 1B: Sensor Ingest and Frost Trigger

## Sequence

1. An **ESP32** sends sensor readings with `POST sensor readings` to `ingestSensorData`.
2. The function updates the live sensor document in Firestore:
	`sensors/*.fields.*.currentValue`.
3. The function appends the historical reading to BigQuery:
	`sensor_data.readings`.
4. The function checks the Firestore lease document `frostRunLock/lease`.
5. If the lease has expired, it enqueues a task in `frost-trigger-queue`. If the lease is still active, it skips enqueueing.
6. The task runs the **Zone_Frost Cloud Run Job** with `ZONE_ID` and `INGEST_ID`.
7. The job reads recent readings, writes predictions to `sensor_data.frost_predictions`, and loads or saves its model checkpoint in GCS.

## Why Two Data Stores?

- **Firestore `currentValue`** is the latest value used for live dashboard widgets and real-time updates.
- **BigQuery `sensor_data.readings`** is the append-only historical record used for charts, aggregation, and analysis.
- The lease prevents repeated sensor ingests from starting overlapping frost jobs.

# Architecture 1C: Alert Dispatch Path

Alerts can be evaluated after `ingestSensorData` or through the manually authenticated `sendTestAlert` function.

1. `alertHelpers.runAlertChecks(reading, context)` evaluates the configured rules.
2. Rules include **threshold**, **frost_warning**, **mold_risk**, and **black_rot_risk**.
3. When a rule fires and its cooldown has elapsed, the system updates `alertRules.lastFiredAt`.
4. It inserts an alert record into the BigQuery table `sensor_data.alerts`.
5. It creates a Firestore document at `notifications/{id}`.
6. It multicasts the notification to the tokens belonging to `notifyUserIds` through FCM.
7. The Flutter app receives both the push notification and the Firestore real-time notification update.

If no rule fires, the path ends as a **no-op**. Cooldown tracking prevents the same alert from being sent repeatedly.

# Architecture 1D: Client Access Map

The Flutter app calls two Cloud Functions for chart data:

## `getHistoricalSeries`

- Request fields: `organizationId`, `siteId`, `zoneIds`, `readings`, `start`, `end`, and `aggregation`.
- `pickInterval()` selects a time bucket such as `MINUTE_30`, `HOUR`, `DAY`, or `MONTH`.
- Parameterized BigQuery SQL calculates `AVG`, `MIN`, and `MAX`, grouped by the selected time bucket.
- The response contains `graphs[]` for each requested reading and zone.
- The app renders the results with Syncfusion charts.

## `getFrostPredictionSeries`

- Request fields: `organizationId`, `siteId`, `zoneId`, `start`, and `end`.
- A parameterized multi-CTE query joins readings with `frost_predictions`.
- The response is a bucketed timeline containing sensor context and `predictedChance`.
- The Flutter app renders the result as a frost probability timeline.

## Security Note

The diagram marks `getHistoricalSeries` with an authentication check commented out as a TODO and marks `getFrostPredictionSeries` as having no authentication check. These endpoints should verify the caller's identity and organization/site/zone permissions before returning data.

# Architecture 1E: Imaging Producer Path

1. A **MicaSense camera** is controlled by Raspberry Pi code such as `camera_data.py` and `pi_capture_and_upload.py`.
2. The Pi sends the capture to `Multispectral_Container` through `/process-capture`.
3. `align_images.py` aligns the multispectral bands.
4. `process_images_new.py` calculates vegetation indices including **NDVI** and **NDRE**.
5. `run_inference.py` runs vine-presence and disease models using **ResNet** and produces **Grad-CAM** explanations.
6. `firebase_upload.py` uploads the processed image outputs to Firebase Storage.
7. Metadata is written to Firestore at `captures/{id}`.
8. The Mobile Dashboard reads the capture metadata and displays the imaging results.

# Architecture 1F: Firestore Data Model

## Organization Hierarchy

- `organizations/{orgId}` is the top-level tenant.
- `organizations/{orgId}/members/{userId}` stores organization membership.
- `organizations/{orgId}/pendingInvites/{email}` stores invitations.
- `organizations/{orgId}/sites/{siteId}` stores sites belonging to an organization.
- `organizations/{orgId}/sites/{siteId}/alertRules/{ruleId}` stores alert configuration.
- `organizations/{orgId}/sites/{siteId}/zones/{zoneId}` stores zones belonging to a site.
- `organizations/{orgId}/sites/{siteId}/zones/{zoneId}/sensors/{sensorId}` stores sensors belonging to a zone.

## Cross-References and Shared Collections

- `users/{uid}` stores user records.
- `notifications/{id}` stores notification records delivered to clients.
- `frostRunLock/lease` coordinates frost-job execution.
- `sensorLookup/{sensorId}` provides a lookup from a sensor ID to its related location or hierarchy.
- `readings/{alias}` is a standalone reading-type catalog.
- `captures/{id}` is standalone metadata written by `Multispectral_Container`.

The hierarchy provides tenant and location ownership, while lookup documents and catalogs support efficient access without repeatedly traversing the full hierarchy.

# Architecture 1G: Flutter App Internal Architecture

- `main.dart` bootstraps the application.
- `AppState`, implemented with `ChangeNotifier`, holds shared application state and notifies pages when it changes.
- Pages include **Login**, **Dashboards**, **Alerts**, and **Analytics**.
- Firestore-backed services handle organizations, sites, zones, sensors, users, alerts, lookups, and reading types.
- HTTP API clients call the historical-series, frost-series, and `sendTestAlert` endpoints.
- `fcm_service` handles Firebase Cloud Messaging and push-notification registration.

## End-to-End Summary

ESP32 nodes provide live and historical sensor data. Cloud Functions persist that data, evaluate alerts, and coordinate frost jobs. Cloud Run and BigQuery handle asynchronous prediction and analytics workloads. The Raspberry Pi imaging path sends multispectral captures to a processing container, which stores results in Firebase. The Flutter app combines Firestore real-time data, HTTP query responses, and FCM notifications into the user-facing dashboards.
