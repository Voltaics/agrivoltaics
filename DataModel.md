## Collections Structure

### 1. **users** (Top-level Collection)
User profiles linked to Firebase Auth. Document ID = Firebase Auth UID.

```javascript
users/{userId}
{
  // Basic Info
  uid: string,                    // Firebase Auth UID (matches document ID)
  email: string,                  // User email
  displayName: string,            // Full name
  photoUrl: string,               // Profile picture URL
  
  // Timestamps
  createdAt: timestamp,
  lastLogin: timestamp,
  
  // User Preferences (migrated from MongoDB settings)
  preferences: {
    theme: string,                // "light" | "dark" | "auto"
    timezone: string,             // "America/New_York"
    language: string,             // "en"
    notificationsEnabled: boolean,
    singleGraphToggle: boolean,   // From MongoDB settings
    returnDataFilter: string,     // "max" | "min" | "mean" (from MongoDB)
  },
  
  // Weather Notification Tracking (from MongoDB)
  lastReadNotification: timestamp, // Track last read notification
}
```

---

### 2. **organizations** (Top-level Collection)
Organizations/companies that own vineyard sites.

```javascript
organizations/{orgId}
{
  // Basic Info
  name: string,                   // "UC Vinovoltaics"
  description: string,
  logoUrl: string,
  
  // Timestamps
  createdAt: timestamp,
  updatedAt: timestamp,
  createdBy: string,              // userId
  
  // Settings
  settings: {
    timezone: string,             // Default timezone for org
    alertsEnabled: boolean,
  }
}
```

#### **Subcollection: organizations/{orgId}/members**
Organization members and their roles.

```javascript
organizations/{orgId}/members/{userId}
{  
  // Role & Permissions
  role: string,                   // "owner" | "admin" | "member" | "viewer"
  permissions: {
    canManageMembers: boolean,
    canManageSites: boolean,
    canManageSensors: boolean,
    canViewData: boolean,
    canExportData: boolean,
  },
  
  // Timestamps
  joinedAt: timestamp,
  invitedBy: string,              // userId
  lastActive: timestamp,
}
```

#### **Subcollection: organizations/{orgId}/sites**
Physical vineyard/farm locations.

```javascript
organizations/{orgId}/sites/{siteId}
{
  // Basic Info
  name: string,                   // "Napa Valley Vineyard" ('nickName' in MongoDB)
  description: string,
  
  // Location
  location: geopoint,             // lat/lng
  address: string,
  timezone: string,               // Site-specific timezone
  
  // Status & Stats
  isActive: boolean,
  lastDataReceived: timestamp,
  
  // Timestamps
  createdAt: timestamp,
  updatedAt: timestamp,
  createdBy: string,              // userId
  
  // Site Settings (migrated from MongoDB)
  siteChecked: boolean,           // From MongoDB settings
}
```

#### **Subcollection: organizations/{orgId}/sites/{siteId}/zones**
Zones within a site (optional subdivision of sites).

```javascript
organizations/{orgId}/sites/{siteId}/zones/{zoneId}
{
  // Basic Info
  name: string,                   // "Zone 1", "Zone 2"
  description: string,
  
  // Location within site
  location: geopoint,
  
  // Settings (migrated from MongoDB)
  zoneChecked: boolean,           // Visibility toggle from MongoDB
  
  // Timestamps
  createdAt: timestamp,
  updatedAt: timestamp,
}
```

#### **Subcollection: organizations/{orgId}/sites/{siteId}/zones/{zoneId}/sensors**
Physical sensors connected to Arduino devices. Multi-output sensors (e.g., DHT22) store all readings in one document.

```javascript
organizations/{orgId}/sites/{siteId}/zones/{zoneId}/sensors/{sensorId}
{
  // Basic Info
  name: string,                   // "DHT22 Weather Sensor" or "Soil Sensor 1"
  model: string,                  // "DHT22" | "VEML7700" | "DFRobot-Soil" | "SGP30"
  
  // Location
  location: geopoint,
  
  // Sensor Fields (multi-output sensors have multiple fields)
  fields: {
    temperature: {                // Field name matches sensor type
      currentValue: number,       // 72.5
      unit: string,               // "°F" or "°C"
      lastUpdated: timestamp,
    },
    humidity: {
      currentValue: number,       // 65.2
      unit: string,               // "%"
      lastUpdated: timestamp,
    },
    // Other possible fields: light, soilMoisture, soilTemperature, soilEC, co2, tvoc
  },
  
  // Status & Health
  status: string,                 // "active" | "inactive" | "maintenance" | "error"
  isOnline: boolean,
  lastReading: timestamp,         // Last time any data was received
  
  // Timestamps
  createdAt: timestamp,
  updatedAt: timestamp,
}
```

**Example Sensors:**
- **DHT22:** Has `fields.temperature` and `fields.humidity`
- **VEML7700:** Has only `fields.light`
- **Soil Sensor:** Has `fields.soilTemperature`, `fields.soilMoisture`, and `fields.soilEC`
- **SGP30:** Has `fields.co2` and `fields.tvoc`

---

### 7. **sensorLookup** (Top-level Collection)
Fast lookup table for sensor metadata. Document ID = sensorId.

```javascript
sensorLookup/{sensorId}
{
  // Sensor Document Path
  sensorDocPath: string,         // Full Firestore path to sensor document
  organizationId: string,
  siteId: string,
  zoneId: string,
  sensorId: string,              // Matches document ID
  
  // Sensor Metadata
  sensorModel: string,           // "DHT22" | "VEML7700" | "DFRobot-Soil" | "SGP30"
  sensorName: string,            // "DHT22 Weather Sensor"
  
  // Field Mapping (what fields this sensor outputs)
  fields: [                      // Array of field names this sensor provides
    "temperature",
    "humidity"
  ],
  
  // Status
  isActive: boolean,
  lastDataReceived: timestamp,
  
  // Timestamps
  registeredAt: timestamp,
  updatedAt: timestamp,
}
```

**Purpose:** Quick lookup of sensor metadata by sensor ID.

**Note:** This collection is automatically maintained by SensorService when sensors are created/updated/deleted. All sensor CRUD operations in SensorService automatically update the corresponding sensorLookup entry to keep them in sync.

---

### 8. **mobileSensors** (Top-level Collection)
Temporary/mobile sensing devices (smartphones, portable sensors).

```javascript
mobileSensors/{mobileSensorId}
{
  // Basic Info
  name: string,                   // "Eli's iPhone"
  type: string,                   // "smartphone" | "portable_device"
  ipAddress: string,
  
  // Ownership
  organizationId: string,
  currentSiteId: string,          // Current location (nullable)
  currentZoneId: string,          // Current zone (nullable)
  
  // Device Info
  deviceInfo: {
    platform: string,             // "iOS" | "Android" | "Web"
    model: string,
    osVersion: string,
    appVersion: string,
  },
  
  // Status
  isActive: boolean,
  lastActivity: timestamp,
  
  // Current Session
  sessionData: {
    sessionId: string,
    startTime: timestamp,
    dataPointsCollected: number,
  },
  
  // Timestamps
  registeredAt: timestamp,
  lastSyncedAt: timestamp,
}
```

---

### 9. **alerts** (Top-level Collection)
Weather alerts and sensor threshold alerts.

```javascript
alerts/{alertId}
{
  // Reference
  organizationId: string,
  siteId: string,                 // nullable for weather alerts
  sensorId: string,               // nullable for weather alerts
  
  // Alert Type
  type: string,                   // "weather" | "threshold_exceeded" | "sensor_offline" | "battery_low"
  category: string,               // For weather: "frost" | "heat" | "storm" | etc.
  
  // Content (for weather alerts from MongoDB/NOAA API)
  phenomenon: string,             // "Frost", "Blizzard", "Heat"
  significance: string,           // "Warning" | "Watch" | "Advisory" | "Statement"
  message: string,                // Full alert message
  
  // Severity
  severity: string,               // "info" | "warning" | "critical"
  priority: number,               // 1-5 for sorting
  
  // Status
  isRead: boolean,
  acknowledgedAt: timestamp,
  acknowledgedBy: string,         // userId
  resolved: boolean,
  resolvedAt: timestamp,
  resolvedBy: string,             // userId
  
  // Timestamps
  createdAt: timestamp,
  validFrom: timestamp,           // For weather alerts
  validUntil: timestamp,          // For weather alerts
  
  // Additional Data (from MongoDB weather body)
  metadata: map,
}
```

---

### 10. **imageAnalysis** (Top-level Collection)
ML model results for disease detection and vine presence.

```javascript
imageAnalysis/{analysisId}
{
  // Reference
  organizationId: string,
  siteId: string,
  zoneId: string,                 // nullable
  
  // Upload Info
  uploadedBy: string,             // userId or mobileSensorId
  uploadedAt: timestamp,
  capturedAt: timestamp,
  location: geopoint,
  
  // Results: Vine Presence
  vinePresence: {
    detected: boolean,
    confidence: number,           // 0-1
  },
  
  // Results: Disease Detection
  disease: {
    detected: boolean,
    diseaseType: string,          // "powdery_mildew" | "downy_mildew" | etc.
    confidence: number,           // 0-1
    affectedArea: number,         // percentage 0-100
    severity: string,             // "low" | "medium" | "high"
  },
  
  // Processing Status
  status: string,                 // "pending" | "processing" | "completed" | "failed"
  errorMessage: string,           // If failed
  
  // Timestamps
  createdAt: timestamp,
  processedAt: timestamp,
}
```

---

### 11. **notifications** (Top-level Collection)
User-specific notification queue (replaces MongoDB notifications + user tracking).

```javascript
notifications/{notificationId}
{
  // Recipient
  userId: string,                 // Who should see this
  organizationId: string,
  
  // Content
  title: string,
  body: string,
  type: string,                   // "weather" | "alert" | "sensor" | "system"
  
  // Reference
  referenceType: string,          // "alert" | "sensor" | "imageAnalysis"
  referenceId: string,            // Document ID of the referenced item
  
  // Status
  isRead: boolean,
  readAt: timestamp,
  
  // Action
  actionUrl: string,              // Deep link to relevant page
  actionLabel: string,            // "View Alert", "Check Sensor"
  
  // Timestamps
  createdAt: timestamp,
  expiresAt: timestamp,           // Auto-delete old notifications
}
```