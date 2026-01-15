# BigQuery Setup Guide

## Overview

Your sensor data now streams to **BigQuery** for fast, scalable analytics. This replaces the CSV append bottleneck with a proper time-series database.

## Architecture

```
Arduino → Cloud Function → [Firestore + BigQuery]
                              ↓         ↓
                         Real-time   Historical
                         Dashboard   Analytics
```

- **Firestore:** Current sensor state (real-time dashboard)
- **BigQuery:** All historical readings (fast queries, charts, analytics)

## One-Time Setup

### 1. Enable BigQuery API

```bash
# Enable BigQuery API in your project
gcloud services enable bigquery.googleapis.com
```

Or enable it manually:
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Select your project
3. Navigate to "APIs & Services" → "Enable APIs and Services"
4. Search for "BigQuery API" and enable it

### 2. Create Dataset and Table

Deploy the setup function and call it once:

```bash
# Deploy all functions (including setupBigQuery)
cd functions
npm run deploy

# Call the setup function to create dataset and table
curl -X POST https://[REGION]-[PROJECT-ID].cloudfunctions.net/setupBigQuery
```

**PowerShell:**
```powershell
Invoke-RestMethod -Uri "https://us-central1-[PROJECT-ID].cloudfunctions.net/setupBigQuery" -Method POST
```

**Expected Response:**
```json
{
  "success": true,
  "message": "BigQuery setup completed",
  "dataset": "sensor_data",
  "table": "readings",
  "partitioning": "DAY on timestamp field",
  "clustering": "sensorId, field"
}
```

### 3. Verify in BigQuery Console

1. Go to [BigQuery Console](https://console.cloud.google.com/bigquery)
2. Look for dataset `sensor_data`
3. Check table `readings` exists
4. Verify schema has 11 columns (timestamp, organizationId, siteId, etc.)

## Table Schema

```sql
CREATE TABLE sensor_data.readings (
  timestamp TIMESTAMP NOT NULL,
  organizationId STRING NOT NULL,
  siteId STRING NOT NULL,
  zoneId STRING NOT NULL,
  sensorId STRING NOT NULL,
  arduinoDeviceId STRING NOT NULL,
  sensorModel STRING,
  sensorName STRING,
  field STRING NOT NULL,       -- 'temperature', 'humidity', etc.
  value FLOAT NOT NULL,
  unit STRING NOT NULL
)
PARTITION BY DATE(timestamp)
CLUSTER BY sensorId, field;
```

## Configuration Options

### CSV Backup (Optional)

By default, CSV backups are **disabled**. To enable:

```bash
firebase functions:config:set csv.backup="true"
firebase deploy --only functions
```

When enabled, individual CSV files are stored per reading (no append bottleneck):
```
sensor-data/{org}/{site}/{zone}/{sensor}/{year}/{month}/{day}/{timestamp}.csv
```

### Data Retention

Default: Keep data forever (`expirationMs: null`)

To auto-delete old data after 1 year, modify [index.js](index.js#L335):
```javascript
timePartitioning: {
  type: 'DAY',
  field: 'timestamp',
  expirationMs: '31536000000', // 365 days in milliseconds
},
```

## Querying BigQuery

### From Flutter App

Add BigQuery dependency to Flutter:
```yaml
# pubspec.yaml
dependencies:
  googleapis: ^13.0.0
  googleapis_auth: ^1.6.0
```

Example query function:
```dart
import 'package:googleapis/bigquery/v2.dart';
import 'package:googleapis_auth/auth_io.dart';

Future<List<SensorReading>> getHistoricalData(
  String sensorId,
  String field,
  DateTime startDate,
  DateTime endDate,
) async {
  final credentials = await obtainCredentials(); // Use Firebase Auth
  final client = authenticatedClient(http.Client(), credentials);
  final bigquery = BigQueryApi(client);
  
  final query = '''
    SELECT timestamp, value, unit
    FROM sensor_data.readings
    WHERE sensorId = @sensorId
      AND field = @field
      AND timestamp BETWEEN @startDate AND @endDate
    ORDER BY timestamp ASC
  ''';
  
  final request = QueryRequest()
    ..query = query
    ..useLegacySql = false
    ..parameterMode = 'NAMED'
    ..queryParameters = [
      QueryParameter()
        ..name = 'sensorId'
        ..parameterType = (QueryParameterType()..type = 'STRING')
        ..parameterValue = (QueryParameterValue()..value = sensorId),
      // ... add other parameters
    ];
  
  final response = await bigquery.jobs.query(request, 'PROJECT_ID');
  
  // Parse response.rows into SensorReading objects
  return parseRows(response.rows);
}
```

### Useful SQL Queries

**Get sensor data for last 7 days:**
```sql
SELECT 
  timestamp,
  field,
  value,
  unit
FROM sensor_data.readings
WHERE sensorId = 'sensor1'
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
ORDER BY timestamp ASC;
```

**Hourly averages:**
```sql
SELECT 
  TIMESTAMP_TRUNC(timestamp, HOUR) as hour,
  field,
  AVG(value) as avg_value,
  MIN(value) as min_value,
  MAX(value) as max_value,
  ANY_VALUE(unit) as unit
FROM sensor_data.readings
WHERE sensorId = 'sensor1'
  AND field = 'temperature'
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY hour, field
ORDER BY hour ASC;
```

**Compare all sensors in a zone:**
```sql
SELECT 
  sensorId,
  sensorName,
  field,
  AVG(value) as avg_value,
  ANY_VALUE(unit) as unit
FROM sensor_data.readings
WHERE zoneId = 'zone1'
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
GROUP BY sensorId, sensorName, field
ORDER BY sensorId, field;
```

**Find anomalies (temperature > 100°F):**
```sql
SELECT 
  timestamp,
  sensorId,
  sensorName,
  value,
  unit
FROM sensor_data.readings
WHERE field = 'temperature'
  AND value > 100
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
ORDER BY timestamp DESC;
```

**Daily aggregations:**
```sql
SELECT 
  DATE(timestamp) as date,
  field,
  AVG(value) as avg_value,
  MIN(value) as min_value,
  MAX(value) as max_value,
  COUNT(*) as reading_count
FROM sensor_data.readings
WHERE sensorId = 'sensor1'
  AND field = 'temperature'
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY date, field
ORDER BY date ASC;
```

## Cost Monitoring

### View BigQuery Usage

```bash
# Get query costs for last 30 days
bq ls --jobs --all --max_results=1000 --min_creation_time=$(date -d '30 days ago' +%s)000
```

Or in [BigQuery Console](https://console.cloud.google.com/bigquery):
1. Click "Job History"
2. Filter by "Last 30 days"
3. Check "Bytes Processed" column

### Set Up Budget Alerts

1. Go to [Billing → Budgets & alerts](https://console.cloud.google.com/billing/budgets)
2. Create budget: $10/month
3. Set alert at 50%, 90%, 100%
4. Add email notification

### Cost Optimization Checklist

- [x] **Partitioning enabled** (only scan relevant days)
- [x] **Clustering enabled** (only scan relevant sensors)
- [ ] **Use `SELECT` specific columns** (not `SELECT *`)
- [ ] **Cache common queries** in Firestore
- [ ] **Use materialized views** for pre-aggregated data (future)

## Troubleshooting

### "Table not found" error

Run the setup function:
```bash
curl -X POST https://[REGION]-[PROJECT-ID].cloudfunctions.net/setupBigQuery
```

### "Permission denied" error

Grant BigQuery permissions to Functions service account:
```bash
PROJECT_ID=$(gcloud config get-value project)
SERVICE_ACCOUNT="${PROJECT_ID}@appspot.gserviceaccount.com"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/bigquery.dataEditor"
```

### Data not appearing in BigQuery

1. Check Cloud Functions logs: `firebase functions:log`
2. Verify sensor is registered in `sensorLookup` collection
3. Test with curl:
```bash
curl -X POST http://localhost:5001/[PROJECT]/us-central1/ingestSensorData \
  -H "Content-Type: application/json" \
  -d '{
    "deviceId": "ARDUINO_001",
    "timestamp": 1700000000,
    "readings": {
      "temperature": { "value": 72.5, "unit": "°F" }
    }
  }'
```
4. Query BigQuery to verify:
```sql
SELECT * FROM sensor_data.readings ORDER BY timestamp DESC LIMIT 10;
```

### High query costs

Use query validator before running:
```sql
-- Check bytes to be scanned (dry run)
-- In BigQuery Console, click "Query Validator" before running
```

Add `WHERE` clauses with partitioning field:
```sql
-- ❌ Expensive: Scans entire table
SELECT * FROM sensor_data.readings WHERE sensorId = 'sensor1';

-- ✅ Cheap: Only scans last 7 days
SELECT * FROM sensor_data.readings 
WHERE sensorId = 'sensor1' 
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY);
```

## Migration from CSV

If you have existing CSV data to import:

```bash
# Load CSV file to BigQuery
bq load \
  --source_format=CSV \
  --skip_leading_rows=1 \
  sensor_data.readings \
  gs://YOUR-BUCKET/sensor-data/org1/site1/zone1/sensor1/2025/11/*.csv \
  timestamp:TIMESTAMP,field:STRING,value:FLOAT,unit:STRING
```

## Next Steps

1. ✅ Deploy functions with BigQuery integration
2. ✅ Run setupBigQuery function once
3. ✅ Test data ingestion from Arduino
4. ⏳ Update Flutter app to query BigQuery
5. ⏳ Create common query functions
6. ⏳ Set up budget alerts

## Support

For more information:
- [BigQuery Documentation](https://cloud.google.com/bigquery/docs)
- [BigQuery Pricing](https://cloud.google.com/bigquery/pricing)
- [Query Reference](https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax)
