## Firestore Data Model (Current Implementation)

This document reflects the collections and fields currently used by the app and Cloud Functions code.

## 1) users (top-level)

Document ID: Firebase Auth UID

```javascript
users/{userId}
{
  uid: string,
  email: string,                    // normalized lowercase
  displayName: string,

  createdAt: timestamp,
  lastLogin: timestamp,

  // Legacy single-token path (still referenced in model/service)
  fcmToken?: string | null,
  fcmTokenUpdatedAt?: timestamp,

  // Current multi-device token storage
  fcmTokens?: string[],
}
```

## 2) organizations (top-level)

```javascript
organizations/{orgId}
{
  name: string,
  description: string,
  logoUrl?: string | null,

  createdAt: timestamp,
  updatedAt: timestamp,
  createdBy: string,                // userId
}
```

### 2a) organizations/{orgId}/members

Document ID: userId

```javascript
organizations/{orgId}/members/{userId}
{
  email?: string,                   // normalized email (set for invited/added members)
  role: string,                     // "owner" | "admin" | "member" | "viewer"
  permissions: {
    canManageMembers: boolean,
    canManageSites: boolean,
    canManageSensors: boolean,
  },

  joinedAt: timestamp,
  invitedBy: string | null,         // userId
  lastActive: timestamp | null,
}
```

### 2b) organizations/{orgId}/pendingInvites

Used for invite-by-email before the target user signs in.

Document ID: normalized email (with '/' replaced)

```javascript
organizations/{orgId}/pendingInvites/{inviteDocId}
{
  orgId: string,
  email: string,                    // normalized lowercase
  emailOriginal: string,

  role: string,
  permissions: {
    canManageMembers: boolean,
    canManageSites: boolean,
    canManageSensors: boolean,
  },

  status: string,                   // "pending" | "accepted"
  invitedBy: string,
  createdAt: timestamp,
  updatedAt: timestamp,
  acceptedAt?: timestamp,
}
```

### 2c) organizations/{orgId}/sites

```javascript
organizations/{orgId}/sites/{siteId}
{
  name: string,
  description: string,

  location?: geopoint,
  address: string,
  timezone: string,

  lastDataReceived?: timestamp | null,

  createdAt: timestamp,
  updatedAt: timestamp,
  createdBy: string,

  siteChecked: boolean,
}
```

### 2d) organizations/{orgId}/sites/{siteId}/zones

```javascript
organizations/{orgId}/sites/{siteId}/zones/{zoneId}
{
  name: string,
  description: string,
  location?: geopoint,

  zoneChecked: boolean,

  // Dynamic map: reading field alias -> sensorId
  readings: {
    [readingFieldName: string]: string,
  },

  createdAt: timestamp,
  updatedAt: timestamp,

  // Optional frost settings used by ingest/trigger logic
  frostSettings?: {
    enabled?: boolean,
    predStart?: timestamp,
    predEnd?: timestamp,
    tempThresholdF?: number,
  }
}
```

### 2e) organizations/{orgId}/sites/{siteId}/zones/{zoneId}/sensors

```javascript
organizations/{orgId}/sites/{siteId}/zones/{zoneId}/sensors/{sensorId}
{
  name: string,
  model: string,                    // e.g. DHT22, VEML7700, DFRobot-Soil, SGP30
  location?: geopoint,

  fields: {
    [fieldName: string]: {
      currentValue?: number,
      unit: string,
      lastUpdated?: timestamp,
    }
  },

  lastReading?: timestamp,
  createdAt: timestamp,
  updatedAt: timestamp,
}
```

### 2f) organizations/{orgId}/alertRules

```javascript
organizations/{orgId}/alertRules/{ruleId}
{
  id: string,
  name: string,

  ruleType: string,                 // "threshold" | "frost_warning" | "mold_risk" | "black_rot_risk"
  fieldAlias: string,               // for threshold rules
  operator?: string | null,         // "gt" | "lt" | "gte" | "lte" | "eq"
  threshold?: number | null,

  // Structured conditions for non-threshold rules
  ruleConfig?: map | null,

  // Backward-compat key still written by UI for frost rules
  frostConfig?: map | null,

  enabled: boolean,
  notifyUserIds: string[],

  activeRangeStart?: string | null, // "MM/dd"
  activeRangeEnd?: string | null,   // "MM/dd"
  cooldownMinutes: number,
  lastFiredAt?: timestamp,

  // Function-side optional knobs
  inAppEnabled?: boolean,
  inAppExpiresAfterHours?: number,

  createdBy: string,
  createdAt: timestamp,
  updatedAt: timestamp,
}
```

### 2g) organizations/{orgId}/sites/{siteId}/zones/{zoneId}/frostRunLock

Internal lease document used by Cloud Functions to prevent overlapping frost runs.

```javascript
organizations/{orgId}/sites/{siteId}/zones/{zoneId}/frostRunLock/lease
{
  expiresAt: timestamp,
  updatedAt: timestamp,
}
```

### 2h) frostRuleConfig — the six-level frost alert engine

`frostRuleConfig` is a **sibling** map on the zone doc (2d), never overloading `frostSettings`
(2d) — that map is read by `parseFrostSettings`/`shouldTriggerFrostJob` in
`functions/handlers/ingestSensorData.js` to gate the *unrelated* AI-model Cloud Tasks trigger.
`frostRuleConfig` instead drives the independent, stateful engine in
`functions/lib/frostEngine/` (evaluated on ingest, throttled to ~15 min) and is edited from the
Flutter app via `FrostEngineConfigService`/`FrostEngineConfigDialog`. Every threshold below falls
back to a spec-faithful default (`FrostRuleConfig.defaults()` in
`lib/models/frost_rule_config.dart`, mirrored server-side by `defaultIfNull(config.*, ...)` calls
in `functions/lib/frostEngine/{derivations,rules,evaluateZoneFrostEngine}.js`) if unset, so a zone
with no `frostRuleConfig` at all is inert (`enabled` defaults to `false`).

```javascript
organizations/{orgId}/sites/{siteId}/zones/{zoneId}
{
  // ...fields from 2d...

  frostRuleConfig?: {
    enabled: boolean,                  // default false — opt-in per zone
    growthStage: string,               // dormant|swollenBud|budBreak|shoot1to3in|flowering|fruitSet
    cultivar: string,
    criticalTempF: number,
    minExposureDurationMinutes: number,
    eventMarginF: number,
    allClearMarginF: number,
    allClearStableMinutes: number,
    allClearForecastWindowHours: number,
    allClearHoldMinutes: number,
    warningMinConsecutiveReadings: number,

    windCalmMaxMph: number,
    windLightMaxMph: number,
    windModerateMaxMph: number,
    leafWetnessDryMaxPercent: number,
    leafWetnessWetMinPercent: number,

    watch2A_airTempMaxF: number,
    watch2A_coolingRateMinFPerHr: number,
    watch2A_windMaxMph: number,
    watch2A_dewSpreadMinF: number,
    watch2B_forecastHorizonHours: number,
    watch2B_referenceThresholdF: number,

    warn3A_airTempMaxF: number,
    warn3A_windMaxMph: number,
    warn3A_coolingRateMinFPerHr: number,
    warn3A_dewSpreadMaxF: number,
    warn3B_airTempMaxF: number,
    warn3B_windMaxMph: number,
    warn3B_coolingRateMinFPerHr: number,
    warn3B_dewSpreadMinF: number,
    warn3B_projected2hMaxF: number,
    warn3C_airTempMaxF: number,
    warn3C_windMinMph: number,

    imminent4A_airTempMaxF: number,
    imminent4A_minGrowthStage: string,
    imminent4B_airTempMaxF: number,
    imminent4B_dewSpreadMaxF: number,
    imminent4B_windMaxMph: number,

    nightLightMaxLux: number,
    frostSensitiveFromStage: string,

    notifyUserIds: string[],
    updatedAt: timestamp,
    updatedBy: string,
  }
}
```

`leafMoisture` (existing reading alias) is reused as the leaf-wetness sensor's raw reading — no
new `leafWetnessRaw` alias exists. `windGust` is not a registered reading alias; rules that could
use it (gust) simply come back empty.

#### organizations/{orgId}/sites/{siteId}/zones/{zoneId}/frostConfigAudit

One doc per **changed field**, written client-side in the same batched write as the
`frostRuleConfig` merge (no Cloud Function needed — same "direct Firestore write from browser"
pattern already used for sensor creation).

```javascript
organizations/{orgId}/sites/{siteId}/zones/{zoneId}/frostConfigAudit/{autoId}
{
  changedAt: timestamp,
  changedByUid: string,
  fieldKey: string,           // e.g. "criticalTempF", "notifyUserIds"
  previousValue: any,
  newValue: any,
  cultivarAtChange: string,
  growthStageAtChange: string,
}
```

## 3) readings (top-level)

Document ID: reading alias (camelCase)

```javascript
readings/{readingAlias}
{
  alias: string,
  name: string,
  description: string,
  validUnits: string[],
  defaultUnit: string,
}
```

## 4) sensorLookup (top-level)

Document ID: sensorId

```javascript
sensorLookup/{sensorId}
{
  sensorDocPath: string,
  organizationId: string,
  siteId: string,
  zoneId: string,
  sensorId: string,

  sensorModel: string,
  sensorName: string,
  fields: string[],

  lastDataReceived?: timestamp,
  registeredAt: timestamp,
  updatedAt: timestamp,
}
```

## 5) notifications (top-level)

In-app notification queue consumed by the app UI.

```javascript
notifications/{notificationId}
{
  userId: string,
  organizationId: string,

  title: string,
  body: string,
  type: string,                     // "alert" | "system" | etc.

  referenceType?: string,           // currently written as "alert" by functions
  referenceId?: string | null,

  isRead: boolean,
  readAt?: timestamp,

  createdAt: timestamp,
  expiresAt?: timestamp | null,
}
```

## 6) captures (top-level)

Written by Pi/mobile capture pipeline and displayed on the mobile dashboard.

```javascript
captures/{captureId}
{
  timestamp: timestamp,
  url: string[],                    // storage paths or public URLs (pipeline-dependent)
  detected_disease: boolean,

  // Pipeline-dependent metadata
  analysis?: string | number,
  analysis_summary?: string,
}
```

## Legacy or Planned Collections

The following were documented previously but are not currently referenced by the active app/services code in this repository:

- mobileSensors
- alerts (top-level alert records are currently in BigQuery; in-app alerts are in notifications)
- imageAnalysis
