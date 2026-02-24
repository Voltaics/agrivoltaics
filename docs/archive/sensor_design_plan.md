# Sensor System Design Plan

## 1. Overview

This document outlines the architecture for the sensor system using
**Firebase-only storage** (no InfluxDB), including Arduino data collection,
cloud ingestion via Firebase Cloud Functions, real-time data in Firestore,
historical data in Cloud Storage, and Flutter visualization.

## 2. Hardware (Sensor Node)

-   **Device:** Arduino (ESP32/ESP8266 recommended)
-   **Connectivity:** WiFi
-   **Multiple Sensors per Arduino:** One Arduino board can have multiple sensors connected
-   **Sensors Supported:**
    -   Temperature/Humidity (DHT22) - outputs 2 readings
    -   Ambient Light (VEML7700) - outputs 1 reading
    -   Soil Temperature/Moisture/EC (DFRobot RS485) - outputs 3 readings
    -   CO₂/TVOC (SGP30) - outputs 2 readings
    -   RGB LED Indicator (KY-016) - status only
-   **Publish Method:** HTTPS POST to Firebase Cloud Function endpoint
-   **Payload Format:** JSON with `deviceId` and array of sensor readings

**Example Payload from Arduino with Multiple Sensors:**

Arduino with DHT22 (temp + humidity) + VEML7700 (light):
```json
{
  "deviceId": "ARDUINO_001",
  "timestamp": 1700000000,
  "readings": {
    "temperature": {
      "value": 72.5,
      "unit": "°F"
    },
    "humidity": {
      "value": 65.2,
      "unit": "%"
    },
    "light": {
      "value": 45000,
      "unit": "lux"
    }
  }
}
```

Arduino with soil sensor (temp + moisture + EC):
```json
{
  "deviceId": "ARDUINO_002",
  "timestamp": 1700000000,
  "readings": {
    "soilTemperature": {
      "value": 68.3,
      "unit": "°F"
    },
    "soilMoisture": {
      "value": 42.5,
      "unit": "%"
    },
    "soilEC": {
      "value": 1250,
      "unit": "µs/cm"
    }
  }
}
```

## 3. Cloud Ingestion

### Firebase Cloud Function (ingestSensorData)

-   **Endpoint:** `https://us-central1-PROJECT.cloudfunctions.net/ingestSensorData`
-   **Method:** POST
-   **Authentication:** Optional bearer token validation

**Function Logic:**
1. Validate request (check deviceId, timestamp, readings object)
2. Lookup sensor document using `sensorLookup/{deviceId}` collection
3. Update all fields in the sensor document (e.g., temperature, humidity, light)
4. Append all readings to sensor's Cloud Storage CSV file
5. Update sensor lookup last seen timestamp
6. Return success/error response

**Performance:**
- Single document read (sensorLookup)
- Single document update (sensor with multiple fields)
- Single Cloud Storage append (one row per field)
- For Arduino with DHT22 (2 fields): ~1 lookup, 1 update, 1 append
- Total: ~50-100ms per ingestion

### Local Testing

-   Use Firebase Emulator Suite for local development
-   Local URL: `http://127.0.0.1:5001/PROJECT/us-central1/ingestSensorData`
-   Test with curl or Postman before deploying to production

## 4. Database Design

### Firestore Structure

#### Sensor Documents
Each **physical sensor** is a single document with multiple fields for multi-output sensors:

```
organizations/{orgId}/sites/{siteId}/zones/{zoneId}/sensors/{sensorId}
{
  name: "DHT22 Weather Sensor",
  model: "DHT22",
  arduinoDeviceId: "ARDUINO_001",
  sensorPin: "D4",
  fields: {
    temperature: {
      currentValue: 72.5,
      unit: "°F",
      lastUpdated: timestamp
    },
    humidity: {
      currentValue: 65.2,
      unit: "%",
      lastUpdated: timestamp
    }
  },
  status: "active",
  isOnline: true,
  lastReading: timestamp,
  ...
}
```

**Example Sensors:**
- **DHT22 Weather Sensor:** Has `fields.temperature` and `fields.humidity`
- **VEML7700 Light Sensor:** Has only `fields.light`
- **Soil Sensor:** Has `fields.soilTemperature`, `fields.soilMoisture`, and `fields.soilEC`

**Benefits:**
- User sees one sensor in the app (not confusing split entries)
- Matches physical hardware reality
- Single lookup per Arduino device

#### Lookup Table (for fast ingestion)
Maps Arduino device ID directly to sensor document path:

```
sensorLookup/{arduinoDeviceId}         // Key: Arduino device ID
{
  arduinoDeviceId: "ARDUINO_001",
  sensorDocPath: "organizations/org1/sites/site1/zones/zone1/sensors/sensor1",
  organizationId: "org1",
  siteId: "site1",
  zoneId: "zone1",
  sensorId: "sensor1",
  sensorModel: "DHT22",
  sensorName: "DHT22 Weather Sensor",
  fields: ["temperature", "humidity"],  // What fields this sensor outputs
  isActive: true,
  lastDataReceived: timestamp,
  ...
}
```

**Example Lookup Keys:**
- `ARDUINO_001` → DHT22 sensor with temperature + humidity fields
- `ARDUINO_002` → Soil sensor with soilTemperature + soilMoisture + soilEC fields
- `ARDUINO_003` → VEML7700 light sensor with light field

### Cloud Storage Structure (Historical Data)

Daily CSV files organized by sensor (one CSV per sensor, contains all fields):

```
sensor-data/
  {orgId}/
    {siteId}/
      {zoneId}/
        {sensorId}/              // Physical sensor (e.g., DHT22)
          2025/
            11/
              2025-11-18.csv
              2025-11-19.csv
```

**CSV Format (multi-column for multi-output sensors):**

DHT22 Weather Sensor CSV:
```csv
timestamp,field,value,unit
2025-11-18T14:23:45Z,temperature,72.5,°F
2025-11-18T14:23:45Z,humidity,65.2,%
2025-11-18T14:28:45Z,temperature,72.7,°F
2025-11-18T14:28:45Z,humidity,64.8,%
2025-11-18T14:33:45Z,temperature,72.3,°F
2025-11-18T14:33:45Z,humidity,65.5,%
```

VEML7700 Light Sensor CSV:
```csv
timestamp,field,value,unit
2025-11-18T14:23:45Z,light,45000,lux
2025-11-18T14:28:45Z,light,46200,lux
2025-11-18T14:33:45Z,light,44800,lux
```

Soil Sensor CSV:
```csv
timestamp,field,value,unit
2025-11-18T14:23:45Z,soilTemperature,68.3,°F
2025-11-18T14:23:45Z,soilMoisture,42.5,%
2025-11-18T14:23:45Z,soilEC,1250,µs/cm
2025-11-18T14:28:45Z,soilTemperature,68.5,°F
2025-11-18T14:28:45Z,soilMoisture,42.3,%
2025-11-18T14:28:45Z,soilEC,1248,µs/cm
```

**Benefits:**
- One CSV file per physical sensor (matches user's mental model)
- Easy to filter by field when loading data
- All related measurements in one place
- Minimal storage cost (~$0.026/GB/month)
- Compressible for long-term archival

## 5. Frontend (Flutter App)

### Real-time Dashboard
-   Firestore listener on sensor documents for live updates
-   Display current readings, status, and 24h statistics
-   Real-time charts using `stats24h` data
-   Connection status indicators (isOnline field)

### Historical Graphs
-   Fetch CSV files from Cloud Storage for selected date range
-   Parse CSV and generate charts using:
    -   `syncfusion_flutter_charts` (recommended - professional charts)
    -   `fl_chart` (alternative - open source)
-   Support date range selection (day, week, month, custom)
-   Export/download CSV data option

### Flutter Implementation Example

**Listen to current sensor data:**
```dart
// Listen to a specific sensor (e.g., temperature)
StreamBuilder<DocumentSnapshot>(
  stream: FirebaseFirestore.instance
    .doc('organizations/$orgId/sites/$siteId/zones/$zoneId/sensors/$tempSensorId')
    .snapshots(),
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      final sensor = Sensor.fromFirestore(snapshot.data!);
      
      return SensorCard(
        name: sensor.name,
        model: sensor.model,
        currentValue: sensor.currentValue,
        unit: sensor.unit,
        isOnline: sensor.isOnline,
        lastUpdated: sensor.lastUpdated,
      );
    }
    return CircularProgressIndicator();
  },
)

// Or query all sensors for an Arduino device
StreamBuilder<QuerySnapshot>(
  stream: FirebaseFirestore.instance
    .collection('organizations/$orgId/sites/$siteId/zones/$zoneId/sensors')
    .where('arduinoDeviceId', isEqualTo: 'ARDUINO_001')
    .snapshots(),
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      final sensors = snapshot.docs
        .map((doc) => Sensor.fromFirestore(doc))
        .toList();
      
      return Column(
        children: sensors.map((sensor) => SensorCard(sensor)).toList(),
      );
    }
    return CircularProgressIndicator();
  },
)
```

**Load historical data from Cloud Storage:**
```dart
Future<List<SensorReading>> loadHistoricalData(
  String orgId, 
  String siteId, 
  String zoneId, 
  String sensorId, 
  DateTime date
) async {
  final storage = FirebaseStorage.instance;
  final dateStr = DateFormat('yyyy-MM-dd').format(date);
  final year = date.year;
  final month = date.month.toString().padLeft(2, '0');
  
  final ref = storage.ref(
    'sensor-data/$orgId/$siteId/$zoneId/$sensorId/$year/$month/$dateStr.csv'
  );
  
  try {
    final csvData = await ref.getData();
    final csvString = utf8.decode(csvData!);
    
    // Parse CSV (skip header: timestamp,value,unit)
    final lines = csvString.split('\n').skip(1);
    return lines.where((line) => line.isNotEmpty).map((line) {
      final parts = line.split(',');
      return SensorReading(
        timestamp: DateTime.parse(parts[0]),
        value: double.parse(parts[1]),
        unit: parts[2],
      );
    }).toList();
  } catch (e) {
    print('No data for $dateStr: $e');
    return [];
  }
}
```

## 6. Benefits of This Architecture

-   **Low Cost:** 
    -   Firestore: Only stores current state + 24h stats (minimal reads/writes)
    -   Cloud Storage: ~10x cheaper than Firestore for historical data
    -   No third-party database costs (no InfluxDB)
-   **Scalable:** 
    -   Supports hundreds of sensors
    -   High-frequency readings (every 5 min = 288/day) sustainable
-   **Real-time:** 
    -   Instant dashboard updates via Firestore listeners
    -   No polling required
-   **Simple:** 
    -   All Firebase - unified authentication, security rules
    -   Local development via Firebase Emulator
    -   Easy Flutter integration
-   **Reliable:**
    -   Firestore automatic scaling and replication
    -   Cloud Storage durability (99.999999999%)
    -   Automatic retry in Cloud Functions

## 7. Cloud Function Implementation

### Main Ingestion Function

```javascript
const admin = require('firebase-admin');
const {Storage} = require('@google-cloud/storage');

admin.initializeApp();
const db = admin.firestore();
const storage = new Storage();

exports.ingestSensorData = functions.https.onRequest(async (req, res) => {
  // CORS headers
  res.set('Access-Control-Allow-Origin', '*');
  
  if (req.method !== 'POST') {
    return res.status(405).send('Method Not Allowed');
  }
  
  try {
    const {deviceId, timestamp, readings} = req.body;
    
    // Validate input
    if (!deviceId || !timestamp || !readings || typeof readings !== 'object') {
      return res.status(400).send('Missing required fields or invalid format');
    }
    
    const timestampObj = admin.firestore.Timestamp.fromMillis(timestamp * 1000);
    
    // 1. Lookup sensor document path
    const lookupDoc = await db.doc(`sensorLookup/${deviceId}`).get();
    
    if (!lookupDoc.exists || !lookupDoc.data().isActive) {
      return res.status(404).json({
        success: false,
        error: 'Sensor not registered or inactive'
      });
    }
    
    const {
      sensorDocPath,
      organizationId,
      siteId,
      zoneId,
      sensorId
    } = lookupDoc.data();
    
    // 2. Update all fields in the sensor document
    const fieldUpdates = {};
    for (const [fieldName, reading] of Object.entries(readings)) {
      fieldUpdates[`fields.${fieldName}.currentValue`] = reading.value;
      fieldUpdates[`fields.${fieldName}.unit`] = reading.unit;
      fieldUpdates[`fields.${fieldName}.lastUpdated`] = timestampObj;
    }
    
    await db.doc(sensorDocPath).update({
      ...fieldUpdates,
      lastReading: timestampObj,
      isOnline: true,
    });
    
    // 3. Update sensorLookup last data received
    await lookupDoc.ref.update({
      lastDataReceived: timestampObj,
    });
    
    // 4. Append to Cloud Storage CSV (one row per field)
    const date = new Date(timestamp * 1000);
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const dateStr = date.toISOString().split('T')[0];
    const isoTimestamp = date.toISOString();
    
    const bucket = storage.bucket(process.env.STORAGE_BUCKET);
    const filePath = `sensor-data/${organizationId}/${siteId}/${zoneId}/${sensorId}/${year}/${month}/${dateStr}.csv`;
    const file = bucket.file(filePath);
    
    // Build CSV rows (one per field)
    const csvRows = Object.entries(readings)
      .map(([field, reading]) => `${isoTimestamp},${field},${reading.value},${reading.unit}`)
      .join('\n') + '\n';
    
    // Check if file exists, if not create with header
    const [exists] = await file.exists();
    if (!exists) {
      await file.save('timestamp,field,value,unit\n' + csvRows);
    } else {
      // Append to existing file
      const [fileContents] = await file.download();
      const newContents = fileContents.toString() + csvRows;
      await file.save(newContents);
    }
    
    return res.status(200).json({
      success: true,
      message: 'Data ingestion completed',
      timestamp: isoTimestamp,
      sensorId: sensorId,
      fieldsUpdated: Object.keys(readings),
    });
    
  } catch (error) {
    console.error('Ingestion error:', error);
    return res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});
```

### Sensor Sync Trigger

Automatically maintains sensorLookup table when sensors are created/updated/deleted:

```javascript
exports.syncSensorLookup = functions.firestore
  .document('organizations/{orgId}/sites/{siteId}/zones/{zoneId}/sensors/{sensorId}')
  .onWrite(async (change, context) => {
    const {orgId, siteId, zoneId, sensorId} = context.params;
    
    // Sensor deleted
    if (!change.after.exists) {
      const sensorData = change.before.data();
      await db.doc(`sensorLookup/${sensorData.arduinoDeviceId}`).delete();
      return;
    }
    
    const sensorData = change.after.data();
    const {arduinoDeviceId, model, name, fields} = sensorData;
    
    if (!arduinoDeviceId) return; // No Arduino assigned yet
    
    // Extract field names from sensor's fields object
    const fieldNames = fields ? Object.keys(fields) : [];
    
    // Update or create lookup entry
    await db.doc(`sensorLookup/${arduinoDeviceId}`).set({
      arduinoDeviceId: arduinoDeviceId,
      sensorDocPath: change.after.ref.path,
      organizationId: orgId,
      siteId: siteId,
      zoneId: zoneId,
      sensorId: sensorId,
      sensorModel: model,
      sensorName: name,
      fields: fieldNames,
      isActive: sensorData.status === 'active',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      registeredAt: change.before.exists 
        ? change.before.data().registeredAt 
        : admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });
```
```

## 8. Future Extensions

-   **Authentication:** JWT tokens for Arduino devices
-   **Data Aggregation:** Scheduled function to compute hourly/daily summaries
-   **Alerts:** Threshold monitoring in Cloud Functions
-   **BigQuery Export:** Archive old CSV files to BigQuery for analysis
-   **Data Quality:** Anomaly detection and outlier filtering
-   **Compression:** Automatically compress CSV files older than 30 days
-   **Multi-sensor Support:** Batch ingestion endpoint for multiple readings
-   **Offline Buffering:** Arduino stores readings locally when offline
