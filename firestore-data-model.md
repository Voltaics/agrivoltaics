# Firestore Data Model for Agrivoltaics Project

## Overview
This data model consolidates MongoDB functionality into Firestore while supporting multi-organization collaboration, real-time updates, and your existing InfluxDB time-series data.

---

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
  
  // Organizations (optional cache)
  // NOTE: Source of truth for membership is organizations/{orgId}/members/{userId}.
  // This array is an optional, denormalized cache to speed up "My Orgs" UI.
  // If you prefer to avoid duplication, omit this field and use a collection group
  // query over members instead.
  organizations: string[] | undefined,
  defaultOrganizationId: string | undefined,  // Optional convenience pointer
  
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
    dataRetentionDays: number,    // 180
  },
  
  // Stats (for quick dashboard access)
  memberCount: number,
  siteCount: number,
  activeSensorCount: number,
}
```

#### **Subcollection: organizations/{orgId}/members**
Organization members and their roles.

```javascript
organizations/{orgId}/members/{userId}
{
  // User Info
  email: string,
  displayName: string,
  photoUrl: string,
  
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

Tip: You can list all organizations a user belongs to without duplicating data by
querying the members subcollection as a collection group:

```dart
// Flutter example: get all memberships for current user
final uid = FirebaseAuth.instance.currentUser!.uid;
final snapshots = await FirebaseFirestore.instance
  .collectionGroup('members')
  // If member docs use userId as document ID:
  .where(FieldPath.documentId, isEqualTo: uid)
  .get();

// Each doc's parent chain yields the orgId
final orgIds = snapshots.docs
  .map((d) => d.reference.parent.parent!.id)
  .toList();
```

#### **Subcollection: organizations/{orgId}/sites**
Physical vineyard/farm locations.

```javascript
organizations/{orgId}/sites/{siteId}
{
  // Basic Info
  name: string,                   // "Napa Valley Vineyard"
  nickName: string,               // Custom display name (from MongoDB settings)
  description: string,
  
  // Location
  location: geopoint,             // lat/lng
  address: string,
  timezone: string,               // Site-specific timezone
  
  // Physical Details
  area: {
    value: number,
    unit: string,                 // "acres" | "hectares"
  },
  cropType: string,               // "grapes" | "other"
  
  // Media
  imageUrl: string,               // Firebase Storage path
  images: string[],               // Array of image URLs
  
  // InfluxDB Integration
  influxBucket: string,           // InfluxDB bucket for this site
  influxMeasurement: string,      // Measurement name prefix
  
  // Status & Stats
  isActive: boolean,
  sensorCount: number,
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
  nickName: string,               // Custom display name
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
  
  // Stats
  sensorCount: number,
  
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
  
  // Hardware Details
  manufacturer: string,           // "DHT22", "ESP32"
  model: string,
  firmwareVersion: string,
  macAddress: string,
  
  // Power
  powerSource: string,            // "battery" | "solar" | "wired"
  batteryLevel: number,           // 0-100, null if wired
  batteryLastChecked: timestamp,
  
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
  
  // Calibration
  calibration: {
    offset: number,
    multiplier: number,
    lastCalibrated: timestamp,
    calibratedBy: string,         // userId
  },
  
  // Alert Configuration
  alertThresholds: {
    enabled: boolean,
    min: number,
    max: number,
    criticalMin: number,
    criticalMax: number,
  },
  
  // Timestamps
  installDate: timestamp,
  createdAt: timestamp,
  updatedAt: timestamp,
  createdBy: string,              // userId
  
  // Metadata (flexible for sensor-specific fields)
  metadata: map,
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
  
  // Ownership
  userId: string,                 // Who's using it
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
  
  // Capabilities
  capabilities: string[],         // ["camera", "gps", "accelerometer"]
  
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
  
  // Image Info
  imageUrl: string,               // Firebase Storage path
  thumbnailUrl: string,
  imageSize: number,              // bytes
  
  // Upload Info
  uploadedBy: string,             // userId or mobileSensorId
  uploadedAt: timestamp,
  capturedAt: timestamp,
  location: geopoint,
  
  // ML Model Info
  modelType: string,              // "disease_detection" | "vine_presence"
  modelVersion: string,           // "resnet_aug_v1"
  processingTime: number,         // milliseconds
  
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
  
  // Actions Taken
  alertGenerated: boolean,
  notificationSent: boolean,
  
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

---

## Indexes Required

### Firestore Composite Indexes

```javascript
// For querying user's organizations
users/{userId}
  - organizations (Array)

// For querying organization members by role
organizations/{orgId}/members
  - role (Ascending)
  - joinedAt (Descending)

// For querying active sensors at a site (collection group)
// Create a collection group index on 'sensors' and filter by denormalized siteId
sensors (collection group)
  - siteId (Ascending)
  - status (Ascending)
  - lastReading (Descending)

// For querying active sensors in a specific zone (collection group)
sensors (collection group)
  - zoneId (Ascending)
  - status (Ascending)
  - lastReading (Descending)

// For querying unread notifications
notifications
  - userId (Ascending)
  - isRead (Ascending)
  - createdAt (Descending)

// For querying weather alerts by severity
alerts
  - organizationId (Ascending)
  - severity (Ascending)
  - createdAt (Descending)
  - isRead (Ascending)

// For querying recent image analysis
imageAnalysis
  - organizationId (Ascending)
  - siteId (Ascending)
  - processedAt (Descending)
```

---

## Security Rules Template

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper Functions
    function isAuthenticated() {
      return request.auth != null;
    }
    
    function isOwner(userId) {
      return isAuthenticated() && request.auth.uid == userId;
    }
    
    function isMemberOf(orgId) {
      return isAuthenticated() &&
             exists(/databases/$(database)/documents/organizations/$(orgId)/members/$(request.auth.uid));
    }
    
    function getMemberRole(orgId) {
      return get(/databases/$(database)/documents/organizations/$(orgId)/members/$(request.auth.uid)).data.role;
    }
    
    function hasPermission(orgId, permission) {
      let member = get(/databases/$(database)/documents/organizations/$(orgId)/members/$(request.auth.uid)).data;
      return member.permissions[permission] == true;
    }
    
    // Users Collection
    match /users/{userId} {
      allow read: if isOwner(userId);
      allow create: if isOwner(userId);
      allow update: if isOwner(userId);
      allow delete: if false; // Never delete users
    }
    
    // Organizations Collection
    match /organizations/{orgId} {
      allow read: if isMemberOf(orgId);
      allow create: if isAuthenticated();
      allow update: if getMemberRole(orgId) in ['owner', 'admin'];
      allow delete: if getMemberRole(orgId) == 'owner';
      
      // Members Subcollection
      match /members/{userId} {
        allow read: if isMemberOf(orgId);
        allow write: if hasPermission(orgId, 'canManageMembers');
      }
      
      // Sites Subcollection
      match /sites/{siteId} {
        allow read: if isMemberOf(orgId);
        allow write: if hasPermission(orgId, 'canManageSites');
        
        // Zones Subcollection
        match /zones/{zoneId} {
          allow read: if isMemberOf(orgId);
          allow write: if hasPermission(orgId, 'canManageSites');

          // Sensors Subcollection (sensors belong to zones)
          match /sensors/{sensorId} {
            allow read: if isMemberOf(orgId);
            allow write: if hasPermission(orgId, 'canManageSensors');
          }
        }
      }
    }
    
    // Mobile Sensors Collection
    match /mobileSensors/{sensorId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update: if resource.data.userId == request.auth.uid;
      allow delete: if resource.data.userId == request.auth.uid;
    }
    
    // Alerts Collection
    match /alerts/{alertId} {
      allow read: if isMemberOf(resource.data.organizationId);
      allow create: if isAuthenticated(); // Allow system to create
      allow update: if isMemberOf(resource.data.organizationId); // For acknowledging
      allow delete: if hasPermission(resource.data.organizationId, 'canManageAlerts');
    }
    
    // Image Analysis Collection
    match /imageAnalysis/{analysisId} {
      allow read: if isMemberOf(resource.data.organizationId);
      allow create: if isAuthenticated();
      allow update: if false; // Immutable after creation
      allow delete: if hasPermission(resource.data.organizationId, 'canManageSites');
    }
    
    // Notifications Collection
    match /notifications/{notificationId} {
      allow read: if isOwner(resource.data.userId);
      allow create: if isAuthenticated(); // System creates
      allow update: if isOwner(resource.data.userId); // For marking as read
      allow delete: if isOwner(resource.data.userId);
    }
  }
}
```

---

## Migration Notes

### From MongoDB to Firestore

1. **User Settings Migration:**
   ```
   MongoDB: users.settings → Firestore: users/{userId}.preferences
   ```

2. **Weather Notifications:**
   ```
   MongoDB: notifications → Firestore: alerts (type: "weather")
   ```

3. **Last Read Tracking:**
   ```
   MongoDB: users.last_read → Firestore: users/{userId}.lastReadNotification
   ```

4. **Site/Zone Settings:**
   ```
   MongoDB: users.settings.site1.zone1 → Firestore: organizations/{orgId}/sites/{siteId}/zones/{zoneId}
   ```

---

## Integration with Existing Systems

### InfluxDB Bridge
Each sensor document contains:
- `influxMeasurement`: Measurement name in InfluxDB
- `influxTags`: Tags for filtering queries
- `influxField`: Field name to query

Example query generation:
```dart
String measurement = sensor.influxMeasurement;
Map<String, String> tags = sensor.influxTags;
String field = sensor.influxField;

String query = '''
  from(bucket: "${bucket}")
    |> range(start: ${start})
    |> filter(fn: (r) => r["_measurement"] == "${measurement}")
    |> filter(fn: (r) => r["location"] == "${tags['location']}")
    |> filter(fn: (r) => r["_field"] == "${field}")
''';
```

### Firebase Storage
Images stored in Firebase Storage with paths:
```
organizations/{orgId}/sites/{siteId}/images/{timestamp}_{imageName}
organizations/{orgId}/sites/{siteId}/ml-analysis/{analysisId}.jpg
```

---

## Summary

This data model:
- ✅ Consolidates MongoDB notifications + settings into Firestore
- ✅ Supports multi-organization collaboration
- ✅ Maintains InfluxDB integration for time-series data
- ✅ Enables real-time updates via Firestore listeners
- ✅ Includes security rules for proper access control
- ✅ Preserves all existing MongoDB functionality
- ✅ Adds new features: organizations, sites, zones, ML analysis
- ✅ Optimized for mobile/web with offline support
