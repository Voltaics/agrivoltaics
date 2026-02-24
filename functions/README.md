# Agrivoltaics Firebase Cloud Functions

Firebase Cloud Functions for ingesting sensor data from Arduino devices into Firestore and Cloud Storage.

## Functions

### 1. ingestSensorData (HTTPS)
Receives sensor data from Arduino devices via HTTPS POST.

**Endpoint:** `https://[REGION]-[PROJECT-ID].cloudfunctions.net/ingestSensorData`

**Request Format:**
```json
{
  "deviceId": "ARDUINO_001",
  "timestamp": 1700000000,
  "readings": {
    "temperature": { "value": 72.5, "unit": "°F" },
    "humidity": { "value": 65.2, "unit": "%" }
  }
}
```

**Response (Success):**
```json
{
  "success": true,
  "message": "Data ingestion completed",
  "timestamp": "2025-11-18T14:23:45.000Z",
  "sensorId": "sensor1",
  "fieldsUpdated": ["temperature", "humidity"]
}
```

### 2. syncSensorLookup (Firestore Trigger)
Automatically maintains the `sensorLookup` collection when sensors are created, updated, or deleted.

### 3. checkSensorStatus (Scheduled)
Runs every 15 minutes to mark sensors offline if no data received in 30 minutes.

### 4. getHistoricalSeries (HTTPS)
Returns multi-graph time-series data from BigQuery for charting in the Flutter app.

**Endpoint:** `https://[REGION]-[PROJECT-ID].cloudfunctions.net/getHistoricalSeries`

**Auth:** Requires Firebase ID token in `Authorization: Bearer <token>` header.

**Request Format:**
```json
{
  "organizationId": "org1",
  "siteId": "site1",
  "zoneIds": ["zoneA", "zoneB"],
  "readings": ["temperature", "humidity"],
  "start": "2026-02-01T00:00:00Z",
  "end": "2026-02-05T00:00:00Z",
  "interval": "HOUR",
  "sensorId": "sensor123"
}
```

**Notes:**
- `interval` is optional; the function selects a sensible default based on the time range.
- If `sensorId` is omitted, the function uses the primary sensor (`primarySensor = true`).

**Response (Success):**
```json
{
  "success": true,
  "interval": "HOUR",
  "graphs": [
    {
      "field": "temperature",
      "unit": "°F",
      "series": [
        {
          "zoneId": "zoneA",
          "points": [
            {"t": "2026-02-01T01:00:00.000Z", "v": 71.8},
            {"t": "2026-02-01T02:00:00.000Z", "v": 72.1}
          ]
        },
        {
          "zoneId": "zoneB",
          "points": [
            {"t": "2026-02-01T01:00:00.000Z", "v": 70.5}
          ]
        }
      ]
    },
    {
      "field": "humidity",
      "unit": "%",
      "series": [
        {
          "zoneId": "zoneA",
          "points": [
            {"t": "2026-02-01T01:00:00.000Z", "v": 64.2}
          ]
        }
      ]
    }
  ]
}
```

## Setup

### Prerequisites
- Node.js 18 or higher
- Firebase CLI: `npm install -g firebase-tools`
- Firebase project with Firestore and Cloud Storage enabled

### Installation

1. **Navigate to functions directory:**
   ```bash
   cd functions
   ```

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Login to Firebase:**
   ```bash
   firebase login
   ```

4. **Initialize Firebase project (if not already done):**
   ```bash
   firebase init
   ```
   Select:
   - Firestore
   - Functions
   - Storage
   - Emulators (optional but recommended)

5. **Set your Firebase project:**
   ```bash
   firebase use --add
   ```
   Select your project and give it an alias (e.g., `production`)

## Local Development

### Start Firebase Emulators
Run functions locally with the Firebase Emulator Suite:

```bash
npm run serve
```

This starts:
- Functions emulator on `http://localhost:5001`
- Firestore emulator on `http://localhost:8080`
- Emulator UI on `http://localhost:4000`

### Test the ingestSensorData Function Locally

**Using curl:**
```bash
curl -X POST http://localhost:5001/[PROJECT-ID]/us-central1/ingestSensorData \
  -H "Content-Type: application/json" \
  -d '{
    "deviceId": "ARDUINO_001",
    "timestamp": 1700000000,
    "readings": {
      "temperature": { "value": 72.5, "unit": "°F" },
      "humidity": { "value": 65.2, "unit": "%" }
    }
  }'
```

**Using PowerShell:**
```powershell
$body = @{
    deviceId = "ARDUINO_001"
    timestamp = 1700000000
    readings = @{
        temperature = @{ value = 72.5; unit = "°F" }
        humidity = @{ value = 65.2; unit = "%" }
    }
} | ConvertTo-Json -Depth 3

Invoke-RestMethod -Uri "http://localhost:5001/[PROJECT-ID]/us-central1/ingestSensorData" `
  -Method POST `
  -Body $body `
  -ContentType "application/json"
```

## Deployment

### Deploy All Functions
```bash
npm run deploy
```

### Deploy Specific Function
```bash
firebase deploy --only functions:ingestSensorData
```

### Deploy with Different Project
```bash
firebase use production
npm run deploy
```

## Environment Variables

Set environment variables using Firebase CLI:

```bash
firebase functions:config:set storage.bucket="your-bucket-name"
```

Get current config:
```bash
firebase functions:config:get
```

## Monitoring

### View Logs
```bash
npm run logs
```

### View Specific Function Logs
```bash
firebase functions:log --only ingestSensorData
```

### Real-time Logs
```bash
firebase functions:log --only ingestSensorData --follow
```

## Database Setup

### Required Firestore Collections

#### sensorLookup Collection
Create manually or via Firestore trigger when sensors are registered:

```javascript
// Document ID: ARDUINO_001
{
  arduinoDeviceId: "ARDUINO_001",
  sensorDocPath: "organizations/org1/sites/site1/zones/zone1/sensors/sensor1",
  organizationId: "org1",
  siteId: "site1",
  zoneId: "zone1",
  sensorId: "sensor1",
  sensorModel: "DHT22",
  sensorName: "Weather Sensor",
  fields: ["temperature", "humidity"],
  registeredAt: Timestamp,
  lastDataReceived: Timestamp
}
```

#### Sensor Document Structure
```javascript
// organizations/{orgId}/sites/{siteId}/zones/{zoneId}/sensors/{sensorId}
{
  name: "DHT22 Weather Sensor",
  model: "DHT22",
  arduinoDeviceId: "ARDUINO_001",
  sensorPin: "D4",
  lastReading: Timestamp,
  fields: {
    temperature: {
      currentValue: 72.5,
      unit: "°F",
      lastUpdated: Timestamp
    },
    humidity: {
      currentValue: 65.2,
      unit: "%",
      lastUpdated: Timestamp
    }
  }
}
```

## Security Rules

### Firestore Rules
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Only Cloud Functions can write to sensorLookup
    match /sensorLookup/{deviceId} {
      allow read: if request.auth != null;
      allow write: if false; // Only Cloud Functions
    }
    
    // Sensor documents
    match /organizations/{orgId}/sites/{siteId}/zones/{zoneId}/sensors/{sensorId} {
      allow read: if request.auth != null;
      allow write: if false; // Only Cloud Functions
    }
  }
}
```

### Storage Rules
```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /sensor-data/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if false; // Only Cloud Functions
    }
  }
}
```

## Testing

### Manual Test Checklist
- [ ] Deploy functions to staging
- [ ] Create test sensor document in Firestore
- [ ] Verify sensorLookup document created by syncSensorLookup trigger
- [ ] Send test POST request to ingestSensorData
- [ ] Verify Firestore sensor document updated
- [ ] Verify CSV file created in Cloud Storage
- [ ] Send multiple requests with different fields
- [ ] Test error cases (missing deviceId, invalid timestamp, etc.)
- [ ] Verify checkSensorStatus marks offline sensors

## Troubleshooting

### Function Not Receiving Data
1. Check Firebase Functions logs: `npm run logs`
2. Verify Arduino device is registered in sensorLookup
3. Verify sensor status is "active"
4. Check CORS headers if calling from browser

### Storage Write Failures
1. Verify Cloud Storage bucket exists
2. Check Functions service account has Storage Admin role
3. Verify bucket name in environment config

### Firestore Permission Denied
1. Verify Functions service account has Firestore permissions
2. Check security rules allow Cloud Functions to write

## Cost Optimization

- **Functions:** Free tier: 2M invocations/month
- **Firestore:** Free tier: 50K reads, 20K writes/day
- **Cloud Storage:** $0.026/GB/month
- **Bandwidth:** First 5GB/month free

Expected monthly costs for 100 sensors reporting every 5 minutes:
- Functions: ~8.6M invocations = ~$1.72
- Firestore: ~50K writes/day = ~$9.00
- Storage: ~1GB historical data = ~$0.03
- **Total:** ~$10.75/month

## Next Steps

1. Set up CI/CD pipeline for automated deployments
2. Add authentication/API keys for Arduino devices
3. Implement data aggregation functions
4. Add alerting for sensor thresholds
5. Set up monitoring dashboard

## Support

For issues or questions, see the main project README or contact the development team.
