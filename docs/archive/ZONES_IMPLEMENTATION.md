# Zones Feature Implementation

## Overview
Implemented a complete zones management system with dual UI approach:
- **Desktop**: Sidebar panel below Sites for zone selection and management
- **Mobile**: Space-efficient breadcrumb dropdown combining Site and Zone selection

## Architecture

### Data Model (`lib/models/zone.dart`)
```dart
class Zone {
  final String id;
  final String name;
  final String description;
  final GeoPoint? location;
  final bool zoneChecked;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

**Firestore Path**: `organizations/{orgId}/sites/{siteId}/zones/{zoneId}`

### Service Layer (`lib/services/zone_service.dart`)
Full CRUD operations with business logic:
- `getZones()` - Real-time stream of zones (sorted alphabetically)
- `getZone()` - Fetch single zone
- `createZone()` - Create with validation
- `updateZone()` - Update with auto timestamp
- `deleteZone()` - **Cascading delete** (removes all sensors in zone)
- `toggleZoneChecked()` - Visibility toggle
- `getZoneCount()` - Count zones in site
- `createZones()` - Batch creation helper

### State Management (`lib/app_state.dart`)
Added zone selection tracking with **cascading clears**:
- Select organization → clears site AND zone
- Select site → clears zone
- `selectedZone: models.Zone?`
- `setSelectedZone(models.Zone zone)`

**Legacy Code**: Renamed old MongoDB `Zone` class to `LegacyZone` to avoid naming conflicts

## UI Components

### Desktop UI

#### ZonesPanel (`lib/pages/home/zones_panel.dart`)
Sidebar panel integrated below SitesPanel:
- **Empty State**: Icon + "No zones yet" message + "Click + to add zone" hint
- **Zone List**: 
  - Scrollable ListView
  - Alphabetically sorted
  - Highlights selected zone
  - Real-time updates via StreamBuilder
- **Actions**:
  - Add (+) button in header
  - Edit/Delete menu per zone (3-dot menu)
  - Delete confirmation dialog with cascade warning

**Integration**: Added to `home.dart` desktop sidebar with 200px fixed height

### Mobile UI

#### SiteZoneBreadcrumb (`lib/pages/home/site_zone_breadcrumb.dart`)
Compact breadcrumb selector for small screens:
- **Display**: Tappable card showing "Site Name › Zone Name"
- **Modal Sheet**: Draggable bottom sheet (60% initial, 40-90% range)
- **Site List**: Each site is an expansion tile
- **Zone Expansion**: Tap site to reveal its zones
- **Selection**: 
  - Tap site → sets site, closes modal
  - Tap zone → sets site AND zone, closes modal
- **Visual Feedback**:
  - Selected site/zone highlighted in primary color
  - Icons: Business icon for sites, location pin for zones
  - Site addresses shown as subtitle

**Integration**: Added to `mobile_dashboard.dart` at top of SafeArea

### Dialogs

#### CreateZoneDialog (`lib/pages/create_zone_dialog.dart`)
Material Design modal for zone creation:
- Required: Name (validated, autofocused)
- Optional: Description (multiline, 3 rows)
- Loading state during creation
- Error handling with SnackBar
- FilledButton for primary action

#### EditZoneDialog (`lib/pages/edit_zone_dialog.dart`)
Material Design modal for zone editing:
- Pre-populated from existing zone data
- Same validation as create
- Auto-updates `updatedAt` timestamp
- Success/error feedback via SnackBar

## Files Created/Modified

### New Files
1. `lib/models/zone.dart` - Zone data model (66 lines)
2. `lib/services/zone_service.dart` - Zone CRUD service (132 lines)
3. `lib/pages/home/zones_panel.dart` - Desktop sidebar panel (265 lines)
4. `lib/pages/home/site_zone_breadcrumb.dart` - Mobile breadcrumb selector (298 lines)
5. `lib/pages/create_zone_dialog.dart` - Zone creation dialog (119 lines)
6. `lib/pages/edit_zone_dialog.dart` - Zone editing dialog (127 lines)

### Modified Files
1. `lib/app_state.dart`:
   - Added `selectedZone` property
   - Added `setSelectedZone()` method
   - Cascading clears in `setSelectedOrganization()` and `setSelectedSite()`
   - Renamed legacy `Zone` → `LegacyZone`

2. `lib/pages/home/home.dart`:
   - Imported `zones_panel.dart`
   - Added ZonesPanel below SitesPanel in desktop sidebar (200px height)

3. `lib/pages/mobile_dashboard/mobile_dashboard.dart`:
   - Imported `site_zone_breadcrumb.dart`
   - Added SiteZoneBreadcrumb at top of mobile view

## Design Patterns

### Naming Conflict Resolution
- Used `import 'package:xxx/models/zone.dart' as models;`
- Reference new Zone as `models.Zone` throughout
- Renamed legacy MongoDB class to `LegacyZone` (marked for removal)

### Consistency with Sites
All zone components follow the same patterns as site components:
- Model structure (fromFirestore/toFirestore/copyWith)
- Service methods (get/create/update/delete)
- Panel layout (header + StreamBuilder + empty state + list)
- Dialog structure (form + validation + loading states)

### Real-time Updates
All UI components use `StreamBuilder` for live Firestore updates:
- Zone list updates instantly when zones are created/edited/deleted
- Selection state synced across components via Provider/AppState

### Cascading Operations
Proper hierarchy maintained:
- Delete zone → deletes all sensors in zone
- Change site → clears zone selection
- Change organization → clears site and zone selection

## Mobile UX Optimization
**Problem**: Mobile screens too crowded with separate panels  
**Solution**: Combined Site + Zone selection in single breadcrumb dropdown
- Saves vertical space
- Logical hierarchy (Site contains Zones)
- Expandable drill-down pattern
- Clear visual breadcrumb: "Napa Valley › Zone 1"

## Testing Checklist
- [ ] Create zone (desktop + mobile)
- [ ] Edit zone name/description
- [ ] Delete zone (verify cascade warning)
- [ ] Toggle zoneChecked visibility
- [ ] Select zone (desktop sidebar)
- [ ] Select zone (mobile breadcrumb)
- [ ] Real-time updates when zones change
- [ ] Empty state display
- [ ] Cascading selection clears (org → site → zone)
- [ ] Validation (empty name rejected)

## Next Steps
1. **Sensor Implementation**:
   - Create `lib/models/sensor.dart` following DataModel.md spec
   - Create `lib/services/sensor_service.dart` with multi-output fields
   - Build sensor panels/lists in zone context

2. **Cloud Functions**:
   - Implement cascading deletes server-side
   - Add validation rules for zone creation
   - Security rules for zone access

3. **Enhanced Features**:
   - Zone location picker (map integration)
   - Zone statistics dashboard
   - Bulk zone operations
   - Zone templates/presets

## Notes
- All components compile without errors
- No unused imports or dead code
- Follows Material Design 3 guidelines
- Responsive design (desktop + mobile)
- Legacy code marked for cleanup after migration complete
