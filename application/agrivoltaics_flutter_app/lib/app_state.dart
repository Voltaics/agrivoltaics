import 'dart:convert';

import 'package:agrivoltaics_flutter_app/app_constants.dart';
import 'package:agrivoltaics_flutter_app/models/organization.dart';
import 'package:agrivoltaics_flutter_app/models/user.dart';
import 'package:agrivoltaics_flutter_app/models/site.dart' as models;
import 'package:agrivoltaics_flutter_app/models/zone.dart' as models;
import 'package:agrivoltaics_flutter_app/pages/home/notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:http/http.dart' as http;
import 'package:agrivoltaics_flutter_app/services/historical_series_service.dart';
import 'package:agrivoltaics_flutter_app/services/frost_prediction_series_service.dart';

// Legacy class for old MongoDB settings - will be removed after migration
class LegacyZone {
  String name;
  String nickName;
  Map<SensorMeasurement, bool> fields;
  bool checked;
  
  LegacyZone({
    required this.name,
    required this.nickName,
    required this.fields,
    this.checked = true
  });
}

// Legacy class for old MongoDB settings - will be removed after migration
class Site {
  String name;
  String nickName;
  List<LegacyZone> zones;
  bool checked;

  Site({
    required this.name,
    required this.nickName,
    required this.zones,
    this.checked = true,
  });
}

class AppState with ChangeNotifier {
  AppState() {
    // Initialize site selection
    this.siteSelection = 1;

    this.singleGraphToggle = false;

    // Initialize date range selection as past week
    var now = DateTime.now();
    var initialDateRange = PickerDateRange(DateTime(now.year, now.month, now.day, now.hour - 24, now.minute), now);
    this.dateRangeSelection = initialDateRange;

    this.timezone = tz.getLocation(AppConstants.timezone);

    this.returnDataValue = 'min';
    
    this.sites = [
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

  late PickerDateRange dateRangeSelection;
  TimeInterval timeInterval = TimeInterval(TimeUnit.hour, 1);
  Map<int, bool> zoneSelection = <int, bool>{};
  Map<SensorMeasurement, bool> fieldSelection = <SensorMeasurement, bool>{};

  // keeping temporarily for the chart name.
  late int siteSelection;

  late bool singleGraphToggle;

  // Settings
  late tz.Location timezone;

  // Sites and Zones
  List<Site> sites = [];

  late String returnDataValue;

  // Notifications
  List<AppNotification> notifications = [];

  // Selected Organization
  Organization? selectedOrganization;

  // Selected Site
  models.Site? selectedSite;

  // Selected Zone
  models.Zone? selectedZone;

  // Current User
  AppUser? currentUser;

  // Historical dashboard persistent state
  models.Site? historicalSelectedSite;
  PickerDateRange? historicalDateRange;
  final Set<String> historicalSelectedZoneIds = <String>{};
  final Set<String> historicalSelectedReadings = <String>{};
  String historicalSelectedAggregation = 'avg';

  // Analytics dashboard persistent state
  String? analyticsSelectedModelId;
  int analyticsModelSession = 0;

  // Frost timeline persistent state
  models.Site? frostTimelineSelectedSite;
  models.Zone? frostTimelineSelectedZone;
  PickerDateRange? frostTimelineDateRange;

  // Historical dashboard loaded result state
  HistoricalResponse? historicalResponse;
  bool historicalIsLoading = false;
  String? historicalErrorMessage;

  // Frost timeline loaded result state
  FrostTimelineResponse? frostTimelineResponse;
  bool frostTimelineIsLoading = false;
  String? frostTimelineErrorMessage;

  void setHistoricalSelectedSite(models.Site? site) {
    historicalSelectedSite = site;
    notifyListeners();
  }

  void setHistoricalDateRange(PickerDateRange range) {
    historicalDateRange = range;
    notifyListeners();
  }

  void setHistoricalSelectedZoneIds(Set<String> zoneIds) {
    historicalSelectedZoneIds
      ..clear()
      ..addAll(zoneIds);
    notifyListeners();
  }

  void setHistoricalSelectedReadings(Set<String> readings) {
    historicalSelectedReadings
      ..clear()
      ..addAll(readings);
    notifyListeners();
  }

  void setHistoricalSelectedAggregation(String aggregation) {
    historicalSelectedAggregation = aggregation;
    notifyListeners();
  }

  void clearHistoricalDashboardState() {
    historicalSelectedSite = null;
    historicalDateRange = null;
    historicalSelectedZoneIds.clear();
    historicalSelectedReadings.clear();
    historicalSelectedAggregation = 'avg';

    historicalResponse = null;
    historicalIsLoading = false;
    historicalErrorMessage = null;

    notifyListeners();
  }

  void setAnalyticsSelectedModelId(String? modelId) {
    analyticsSelectedModelId = modelId;
    analyticsModelSession++;
    notifyListeners();
  }

  void clearAnalyticsDashboardState() {
    analyticsSelectedModelId = null;
    analyticsModelSession = 0;
    notifyListeners();
  }

  void setFrostTimelineSelectedSite(models.Site? site) {
    frostTimelineSelectedSite = site;
    frostTimelineSelectedZone = null;
    frostTimelineResponse = null;
    frostTimelineIsLoading = false;
    frostTimelineErrorMessage = null;
    notifyListeners();
  }

  void setFrostTimelineSelectedZone(models.Zone? zone) {
    frostTimelineSelectedZone = zone;
    frostTimelineResponse = null;
    frostTimelineIsLoading = false;
    frostTimelineErrorMessage = null;
    notifyListeners();
  }

  void setFrostTimelineDateRange(PickerDateRange range) {
    frostTimelineDateRange = range;
    frostTimelineResponse = null;
    frostTimelineIsLoading = false;
    frostTimelineErrorMessage = null;
    notifyListeners();
  }

  void clearFrostTimelineState() {
    frostTimelineSelectedSite = null;
    frostTimelineSelectedZone = null;
    frostTimelineDateRange = null;

    frostTimelineResponse = null;
    frostTimelineIsLoading = false;
    frostTimelineErrorMessage = null;

    notifyListeners();
  }

  void startHistoricalLoad() {
    historicalIsLoading = true;
    historicalErrorMessage = null;
    notifyListeners();
  }

  void setHistoricalResponse(HistoricalResponse response) {
    historicalResponse = response;
    historicalIsLoading = false;
    historicalErrorMessage = null;
    notifyListeners();
  }

  void setHistoricalError(String message) {
    historicalIsLoading = false;
    historicalErrorMessage = message;
    notifyListeners();
  }

  void clearHistoricalResults() {
    historicalResponse = null;
    historicalIsLoading = false;
    historicalErrorMessage = null;
    notifyListeners();
  }

  void startFrostTimelineLoad() {
    frostTimelineIsLoading = true;
    frostTimelineErrorMessage = null;
    notifyListeners();
  }

  void setFrostTimelineResponse(FrostTimelineResponse response) {
    frostTimelineResponse = response;
    frostTimelineIsLoading = false;
    frostTimelineErrorMessage = null;
    notifyListeners();
  }

  void setFrostTimelineError(String message) {
    frostTimelineIsLoading = false;
    frostTimelineErrorMessage = message;
    notifyListeners();
  }

  void clearFrostTimelineResults() {
    frostTimelineResponse = null;
    frostTimelineIsLoading = false;
    frostTimelineErrorMessage = null;
    notifyListeners();
  }

  void setSelectedOrganization(Organization org) {
    selectedOrganization = org;
    selectedSite = null;
    selectedZone = null;

    historicalSelectedSite = null;
    historicalDateRange = null;
    historicalSelectedZoneIds.clear();
    historicalSelectedReadings.clear();
    historicalSelectedAggregation = 'avg';

    analyticsSelectedModelId = null;
    analyticsModelSession = 0;

    frostTimelineSelectedSite = null;
    frostTimelineSelectedZone = null;
    frostTimelineDateRange = null;

    notifyListeners();
  }

  void setSelectedSite(models.Site site) {
    selectedSite = site;
    // Clear zone when site changes
    selectedZone = null;
    notifyListeners();
  }

  void clearSelectedSite() {
    selectedSite = null;
    selectedZone = null;
    notifyListeners();
  }

  void setSelectedZone(models.Zone zone) {
    selectedZone = zone;
    notifyListeners();
  }

  void clearSelectedZone() {
    selectedZone = null;
    notifyListeners();
  }

  void setCurrentUser(AppUser user) {
    currentUser = user;
    notifyListeners();
  }

  void clearCurrentUser() {
    currentUser = null;
    selectedOrganization = null;
    selectedSite = null;
    selectedZone = null;

    historicalSelectedSite = null;
    historicalDateRange = null;
    historicalSelectedZoneIds.clear();
    historicalSelectedReadings.clear();
    historicalSelectedAggregation = 'avg';

    analyticsSelectedModelId = null;
    analyticsModelSession = 0;

    frostTimelineSelectedSite = null;
    frostTimelineSelectedZone = null;
    frostTimelineDateRange = null;

    notifyListeners();
  }

  void setSingleGraphToggle(bool value) {
      singleGraphToggle = value;
      notifyListeners();
  }

  void addSite() {
      sites.add(
        Site(name: 'site ${sites.length + 1}',         
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
        ], checked: true),
      );
      notifyListeners();
  }

  void removeSite(int index) {

      sites.removeAt(index);
      for (int i = 0; i < sites.length; i++) { 
        sites[i].name = 'Site ${i + 1}';
      }
      notifyListeners();
  }

  void addZone(int siteIndex) {
      sites[siteIndex].zones.add(
        LegacyZone(
          name: 'Zone ${sites[siteIndex].zones.length + 1}',
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
      notifyListeners();
  }

     void addSiteFromDB(bool siteChecked, String siteNickName, bool zoneChecked, String zoneNickName, bool humidity, bool temperature, bool light, bool frost, bool rain, bool soil) {
      sites.add(
        Site(name: 'site ${sites.length + 1}',         
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
      }, checked: zoneChecked
          ),
        ], checked: siteChecked),
      );
      notifyListeners();
  }

  void addZoneFromDB(int siteIndex, bool zoneChecked, String zoneNickName, bool humidity, bool temperature, bool light, bool frost, bool rain, bool soil) {
      sites[siteIndex].zones.add(
        LegacyZone(
          name: 'Zone ${sites[siteIndex].zones.length + 1}',
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
      notifyListeners();
  }

  void removeZone(int siteIndex, int zoneIndex) {
      sites[siteIndex].zones.removeAt(zoneIndex);
      for (int i = 0; i < sites.length; i++) {
        for (int j = 0; j < sites[i].zones.length; j++) {
          sites[i].zones[j].name = 'Zone ${j + 1}';
        }
      }
      notifyListeners();
  }

  void toggleSiteChecked(int siteIndex) {
      sites[siteIndex].checked = !sites[siteIndex].checked;
      notifyListeners();
  }

  void toggleZoneChecked(int siteIndex, int zoneIndex) {
      sites[siteIndex].zones[zoneIndex].checked =
          !sites[siteIndex].zones[zoneIndex].checked;
      notifyListeners();
  }

  void toggleMeasurementChecked(
      int siteIndex, int zoneIndex, SensorMeasurement measurement) {
      sites[siteIndex].zones[zoneIndex].fields[measurement] =
          !sites[siteIndex].zones[zoneIndex].fields[measurement]!;
      notifyListeners();
  }

  void finalizeState() {
    notifyListeners();
  }

  void updateSettingsInDB() async {

    // Convert sites list to Map<String, dynamic>
    Map<String, dynamic> convertedSites = {};

    for (int i = 0; i < sites.length; i++) {
      Site site = sites[i];
      
      Map<String, dynamic> siteData = {
        'site_checked': site.checked,
        'nickName': site.nickName
      };
      
      for (int j = 0; j < site.zones.length; j++) {
        LegacyZone zone = site.zones[j];
        
        Map<String, dynamic> zoneData = {
          'zone_checked': zone.checked,
          'nickName' : zone.nickName,
          'humidity': zone.fields.containsKey(SensorMeasurement.humidity) ? zone.fields[SensorMeasurement.humidity] : false,
          'temperature': zone.fields.containsKey(SensorMeasurement.temperature) ? zone.fields[SensorMeasurement.temperature] : false,
          'light': zone.fields.containsKey(SensorMeasurement.light) ? zone.fields[SensorMeasurement.light] : false,
          'rain': zone.fields.containsKey(SensorMeasurement.rain) ? zone.fields[SensorMeasurement.rain] : false,
          'frost': zone.fields.containsKey(SensorMeasurement.frost) ? zone.fields[SensorMeasurement.frost] : false,
          'soil': zone.fields.containsKey(SensorMeasurement.soil) ? zone.fields[SensorMeasurement.soil] : false,
        };
        
        siteData['zone${j+1}'] = zoneData;
      }
      
      convertedSites['site${i + 1}'] = siteData;
    }

    String? userEmail = "";
    userEmail = FirebaseAuth.instance.currentUser?.email;

    Map<String, dynamic> requestData = {
      "email": userEmail,
      "settings": {
        'singleGraphToggle': singleGraphToggle,
        'returnDataFilter': returnDataValue,
        'timeZone': timezone.toString(),
        ...convertedSites,
      },
    };

    // Encode the requestData as JSON
    String requestBody = json.encode(requestData);

    // Send the Post request
    await http.post(
      Uri.parse('https://vinovoltaics-notification-api-6ajy6wk4ca-ul.a.run.app/updateSettings?settings=$requestBody'),
    );
  }
}
