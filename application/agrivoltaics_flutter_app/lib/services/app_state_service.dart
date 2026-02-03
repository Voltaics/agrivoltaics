import 'dart:convert';
import 'package:agrivoltaics_flutter_app/app_constants.dart';
import 'package:agrivoltaics_flutter_app/models/organization.dart';
import 'package:agrivoltaics_flutter_app/models/user.dart';
import 'package:agrivoltaics_flutter_app/models/site.dart' as models;
import 'package:agrivoltaics_flutter_app/models/zone.dart' as models;
import 'package:agrivoltaics_flutter_app/app_state.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;
import 'package:syncfusion_flutter_datepicker/datepicker.dart';

/// Service for managing AppState business logic and operations
/// Handles organization, site, zone, user, and settings management
class AppStateService {
  static final AppStateService _instance = AppStateService._internal();

  factory AppStateService() {
    return _instance;
  }

  AppStateService._internal();

  /// Initialize default state for a new AppState instance
  void initializeDefaultState(AppState appState) {
    // Initialize site selection
    appState.siteSelection = 1;
    appState.singleGraphToggle = false;

    // Initialize date range selection as past week
    var now = DateTime.now();
    var initialDateRange = PickerDateRange(
      DateTime(now.year, now.month, now.day, now.hour - 24, now.minute),
      now,
    );
    appState.dateRangeSelection = initialDateRange;
    appState.timezone = tz.getLocation(AppConstants.timezone);
    appState.returnDataValue = 'min';

    // Initialize default site and zones
    appState.sites = [
      Site(
        name: 'site 1',
        nickName: '',
        zones: [
          LegacyZone(
            name: 'Zone 1',
            nickName: '',
            fields: {
              SensorMeasurement.humidity: true,
              SensorMeasurement.temperature: true,
              SensorMeasurement.light: true,
              SensorMeasurement.frost: true,
              SensorMeasurement.rain: true,
              SensorMeasurement.soil: true
            },
          ),
        ],
      ),
    ];
  }

  /// Set the selected organization and clear related selections
  void setSelectedOrganization(AppState appState, Organization org) {
    appState.selectedOrganization = org;
    appState.selectedSite = null;
    appState.selectedZone = null;
  }

  /// Set the selected site and clear related selections
  void setSelectedSite(AppState appState, models.Site site) {
    appState.selectedSite = site;
    appState.selectedZone = null;
  }

  /// Set the selected zone
  void setSelectedZone(AppState appState, models.Zone zone) {
    appState.selectedZone = zone;
  }

  /// Set the current user
  void setCurrentUser(AppState appState, AppUser user) {
    appState.currentUser = user;
  }

  /// Clear all user-related state (called on logout)
  void clearCurrentUser(AppState appState) {
    appState.currentUser = null;
    appState.selectedOrganization = null;
    appState.selectedSite = null;
    appState.selectedZone = null;
  }

  /// Toggle single graph mode
  void setSingleGraphToggle(AppState appState, bool value) {
    appState.singleGraphToggle = value;
  }

  /// Add a new site with default zone
  void addSite(AppState appState) {
    appState.sites.add(
      Site(
        name: 'site ${appState.sites.length + 1}',
        nickName: '',
        zones: [
          LegacyZone(
            name: 'Zone 1',
            nickName: '',
            fields: {
              SensorMeasurement.humidity: true,
              SensorMeasurement.temperature: true,
              SensorMeasurement.light: true,
              SensorMeasurement.frost: true,
              SensorMeasurement.rain: true,
              SensorMeasurement.soil: true
            },
          ),
        ],
        checked: true,
      ),
    );
  }

  /// Remove a site by index and renumber remaining sites
  void removeSite(AppState appState, int index) {
    appState.sites.removeAt(index);
    for (int i = 0; i < appState.sites.length; i++) {
      appState.sites[i].name = 'Site ${i + 1}';
    }
  }

  /// Add a new zone to a specific site
  void addZone(AppState appState, int siteIndex) {
    appState.sites[siteIndex].zones.add(
      LegacyZone(
        name: 'Zone ${appState.sites[siteIndex].zones.length + 1}',
        nickName: '',
        fields: {
          SensorMeasurement.humidity: true,
          SensorMeasurement.temperature: true,
          SensorMeasurement.light: true,
          SensorMeasurement.rain: true,
          SensorMeasurement.frost: true,
          SensorMeasurement.soil: true,
        },
        checked: true,
      ),
    );
  }

  /// Add a site with database values
  void addSiteFromDB(
    AppState appState,
    bool siteChecked,
    String siteNickName,
    bool zoneChecked,
    String zoneNickName,
    bool humidity,
    bool temperature,
    bool light,
    bool frost,
    bool rain,
    bool soil,
  ) {
    appState.sites.add(
      Site(
        name: 'site ${appState.sites.length + 1}',
        nickName: siteNickName,
        zones: [
          LegacyZone(
            name: 'Zone 1',
            nickName: zoneNickName,
            fields: {
              SensorMeasurement.humidity: humidity,
              SensorMeasurement.temperature: temperature,
              SensorMeasurement.light: light,
              SensorMeasurement.frost: frost,
              SensorMeasurement.rain: rain,
              SensorMeasurement.soil: soil
            },
            checked: zoneChecked,
          ),
        ],
        checked: siteChecked,
      ),
    );
  }

  /// Add a zone to a site with database values
  void addZoneFromDB(
    AppState appState,
    int siteIndex,
    bool zoneChecked,
    String zoneNickName,
    bool humidity,
    bool temperature,
    bool light,
    bool frost,
    bool rain,
    bool soil,
  ) {
    appState.sites[siteIndex].zones.add(
      LegacyZone(
        name: 'Zone ${appState.sites[siteIndex].zones.length + 1}',
        nickName: zoneNickName,
        fields: {
          SensorMeasurement.humidity: humidity,
          SensorMeasurement.temperature: temperature,
          SensorMeasurement.light: light,
          SensorMeasurement.rain: rain,
          SensorMeasurement.frost: frost,
          SensorMeasurement.soil: soil,
        },
        checked: zoneChecked,
      ),
    );
  }

  /// Remove a zone from a site and renumber remaining zones
  void removeZone(AppState appState, int siteIndex, int zoneIndex) {
    appState.sites[siteIndex].zones.removeAt(zoneIndex);
    for (int i = 0; i < appState.sites.length; i++) {
      for (int j = 0; j < appState.sites[i].zones.length; j++) {
        appState.sites[i].zones[j].name = 'Zone ${j + 1}';
      }
    }
  }

  /// Toggle site checked status
  void toggleSiteChecked(AppState appState, int siteIndex) {
    appState.sites[siteIndex].checked = !appState.sites[siteIndex].checked;
  }

  /// Toggle zone checked status
  void toggleZoneChecked(AppState appState, int siteIndex, int zoneIndex) {
    appState.sites[siteIndex].zones[zoneIndex].checked =
        !appState.sites[siteIndex].zones[zoneIndex].checked;
  }

  /// Toggle measurement checked status for a zone
  void toggleMeasurementChecked(
    AppState appState,
    int siteIndex,
    int zoneIndex,
    SensorMeasurement measurement,
  ) {
    appState.sites[siteIndex].zones[zoneIndex].fields[measurement] =
        !appState.sites[siteIndex].zones[zoneIndex].fields[measurement]!;
  }

  /// Update settings in the database
  Future<void> updateSettingsInDB(AppState appState) async {
    try {
      // Convert sites list to Map<String, dynamic>
      Map<String, dynamic> convertedSites = {};

      for (int i = 0; i < appState.sites.length; i++) {
        Site site = appState.sites[i];

        Map<String, dynamic> siteData = {
          'site_checked': site.checked,
          'nickName': site.nickName
        };

        for (int j = 0; j < site.zones.length; j++) {
          LegacyZone zone = site.zones[j];

          Map<String, dynamic> zoneData = {
            'zone_checked': zone.checked,
            'nickName': zone.nickName,
            'humidity': zone.fields.containsKey(SensorMeasurement.humidity)
                ? zone.fields[SensorMeasurement.humidity]
                : false,
            'temperature':
                zone.fields.containsKey(SensorMeasurement.temperature)
                    ? zone.fields[SensorMeasurement.temperature]
                    : false,
            'light': zone.fields.containsKey(SensorMeasurement.light)
                ? zone.fields[SensorMeasurement.light]
                : false,
            'rain': zone.fields.containsKey(SensorMeasurement.rain)
                ? zone.fields[SensorMeasurement.rain]
                : false,
            'frost': zone.fields.containsKey(SensorMeasurement.frost)
                ? zone.fields[SensorMeasurement.frost]
                : false,
            'soil': zone.fields.containsKey(SensorMeasurement.soil)
                ? zone.fields[SensorMeasurement.soil]
                : false,
          };

          siteData['zone${j + 1}'] = zoneData;
        }

        convertedSites['site${i + 1}'] = siteData;
      }

      String? userEmail = FirebaseAuth.instance.currentUser?.email;

      Map<String, dynamic> requestData = {
        "email": userEmail,
        "settings": {
          'singleGraphToggle': appState.singleGraphToggle,
          'returnDataFilter': appState.returnDataValue,
          'timeZone': appState.timezone.toString(),
          ...convertedSites,
        },
      };

      // Encode the requestData as JSON
      String requestBody = json.encode(requestData);

      // Send the Post request
      await http.post(
        Uri.parse(
          'https://vinovoltaics-notification-api-6ajy6wk4ca-ul.a.run.app/updateSettings?settings=$requestBody',
        ),
      );
    } catch (e) {
      print('Error updating settings in DB: $e');
      rethrow;
    }
  }
}
