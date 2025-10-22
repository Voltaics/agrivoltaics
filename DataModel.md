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
  
  // Sensor Toggles (from MongoDB settings)
  sensorToggles: {
    humidity: boolean,
    temperature: boolean,
    light: boolean,
    rain: boolean,
    frost: boolean,
    soil: boolean,
  },
  
  // Timestamps
  createdAt: timestamp,
  updatedAt: timestamp,
}
```

#### **Subcollection: organizations/{orgId}/sites/{siteId}/zones/{zoneId}/sensors**
Fixed/permanent sensors within a zone.

```javascript
organizations/{orgId}/sites/{siteId}/zones/{zoneId}/sensors/{sensorId}
{
  // Basic Info
  name: string,                   // "Temperature Sensor 1"
  type: string,                   // "temperature" | "humidity" | "soil_moisture" | "light" | "rain" | "camera"
  deviceId: string,               // Hardware device identifier (Arduino/ESP32)
  
  // Location
  location: geopoint,
  siteId: string,                 // Denormalized for collection-group queries
  zoneId: string,                 // Denormalized for collection-group queries
  installationNotes: string,
  
  // InfluxDB Integration
  influxMeasurement: string,      // Measurement name in InfluxDB
  influxTags: {                   // Tags to filter InfluxDB queries
    location: string,
    sensor_id: string,
    zone: string,
  },
  influxField: string,            // Field name (e.g., "temperature", "humidity")
  
  // Status & Health
  status: string,                 // "active" | "inactive" | "maintenance" | "error"
  isOnline: boolean,
  lastReading: timestamp,
  lastReadingValue: number,       // Cache last value for quick display
  lastReadingUnit: string,        // "°F", "%", "lux"
  
  // Timestamps
  createdAt: timestamp,
  updatedAt: timestamp,
  createdBy: string,              // userId
}
```

---

### 3. **mobileSensors** (Top-level Collection)
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

### 4. **alerts** (Top-level Collection)
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

### 5. **imageAnalysis** (Top-level Collection)
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

### 6. **notifications** (Top-level Collection)
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