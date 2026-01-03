# UI Features

## Description
This document lays out the features that the application must enable.

## Compatibility
Each feature must be implemented for desktop and mobile-sized screens. The Flutter application should be supported on the web for both small and large screens, as well as iOS and Android devices.

## Authentication
The application uses Google authentication for user login, managed through Firebase.

## Organizations
After logging in, users are directed to an organization selection page displaying only organizations they have access to. Users can switch or manage organizations at any time while logged in.

**Available Actions:**
* Sign out
* Select organization
* Create new organization
* Edit organization
  * Change organization data
  * Manage organization members
    * Add member
    * Change member permissions
    * Remove member
  * Delete organization

## Sites
Once an organization is selected, users can choose a site to view stationary sensor data. Only sites belonging to the selected organization are displayed.

**Available Actions:**
* Select site
* Add site
* Edit site
  * Change site data
  * Delete site

## Zones
Each site can have multiple zones assigned to it. Sites must have at least one zone to track sensors, as zones manage sensor assignments. Zones are nested under sites in the UI since each zone belongs to only one site.

**Data Filtering:**
* Selecting a site displays data from all its zones
* Selecting a specific zone filters data to show only that zone's information

**Available Actions:**
* Select zone
* Add zone
* Edit zone
  * Change zone data
  * Delete zone

## Stationary Sensors
Stationary sensors are assigned to zones. Users who prefer not to manage multiple zones must still create at least one zone to represent the entire site.

**Data Display:**
* Sensors are filtered based on the selected site or zone
* Site-level selection shows all sensors across all zones
* Zone-level selection shows only sensors for that specific zone
* Individual readings are displayed to maintain sensor-agnostic historical data
* Some sensors generate multiple readings; each reading maps back to its originating sensor

**Sensor Management:**
* Add sensor
* Edit sensor
* Delete sensor (with constraints)

**Deletion Rules:**
* Sensors with stored readings cannot be permanently deleted to maintain data integrity
* Such sensors can be soft-deleted (marked as offline and hidden from UI)
* This ensures historical readings remain traceable to their source sensors

### Sensor Data Visualization
Sensor data can be viewed in multiple ways:

**Display Options:**
* **Most Recent Reading:** Stored with the entity for quick access
* **Historical Data:** Displayed as interactive graphs
  * Filterable by timeframe and other attributes
  * Stored separately from real-time data (may have longer retrieval times)
  * Enables trend analysis over specified periods

## Mobile Imaging
**Status:** To Be Determined