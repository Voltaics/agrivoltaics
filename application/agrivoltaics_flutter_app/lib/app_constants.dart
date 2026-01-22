abstract class AppConstants {
  static const String influxdbUrl = String.fromEnvironment(
    'INFLUXDB_URL',
    defaultValue: ''
  );

  static const String influxdbToken = String.fromEnvironment(
    'INFLUXDB_TOKEN',
    defaultValue: ''
  );
  
  static const String influxdbOrg = String.fromEnvironment(
    'INFLUXDB_ORG',
    defaultValue: ''
  );

  static const String influxdbBucket = String.fromEnvironment(
    'INFLUXDB_BUCKET',
    defaultValue: ''
  );

  static const bool influxdbDebug = bool.fromEnvironment(
    'INFLUXDB_DEBUG',
    defaultValue: false
  );

  static List<String> authorizedEmails = const String.fromEnvironment(
    'AUTHORIZED_EMAILS',
    defaultValue: ''
  ).split(RegExp(r'[|,]')).where((email) => email.trim().isNotEmpty).map((email) => email.trim()).toList();

  static const String timezone = String.fromEnvironment(
    'TIMEZONE',
    defaultValue: 'America/New_York'
  );
  
  static const int numSites = 1;
  static const int numZones = 4;

  static const Map<int, String> siteConfiguration = {
    1: '172.20.10.5:80'
  };
}

enum TimeUnit {
  second, // TODO: remove this, debugging purposes only
  minute,
  hour,
  day,
  week,
  month
}

class TimeInterval {
  TimeInterval(TimeUnit unit, int value) {
    this.unit = unit;
    this.value = value;
  }

  TimeUnit unit = TimeUnit.hour;
  int value = 1;
}

extension TimeIntervalExtension on TimeInterval {
  Duration? get duration {
    switch (this.unit) {
      case TimeUnit.second:
        return Duration(seconds: this.value);
      case TimeUnit.minute:
        return Duration(minutes: this.value * 15); // changes the graph interval to 15 miute intervals 
      case TimeUnit.hour:
        return Duration(hours: this.value);
      case TimeUnit.day:
        return Duration(days: this.value);
      case TimeUnit.week:
        return Duration(days: this.value * 7);
      case TimeUnit.month:
        return Duration(days: this.value * 30);
    }
  }
}

extension TimeUnitExtension on TimeUnit {
  String? get fluxQuery {
    switch (this) {
      case TimeUnit.second:
        return 's';
      case TimeUnit.minute:
        return 'm';
      case TimeUnit.hour:
        return 'h';
      case TimeUnit.day:
        return 'd';
      case TimeUnit.week:
        return 'w';
      case TimeUnit.month:
        return 'mo';
    }
  }
}

enum SensorMeasurement {
  humidity,
  temperature,
  light,
  rain,
  frost,
  soil,
  rssi
}

extension SensorMeasurementExtension on SensorMeasurement {
  String get fluxQuery {
    switch (this) {
      case SensorMeasurement.humidity:
        return 'humidity';
      case SensorMeasurement.temperature:
        return 'temperature';
      case SensorMeasurement.light:
        return 'light_intensity';
      case SensorMeasurement.rain:
        return 'rain_events';
      case SensorMeasurement.frost:
        return 'Radiation Fahrenheit';
      case SensorMeasurement.soil:
        return 'soil_moisture';
      case SensorMeasurement.rssi:
        return 'rssi';
    }
  }

  String get displayName {
    switch (this) {
      case SensorMeasurement.humidity:
        return 'Humidity';
      case SensorMeasurement.temperature:
        return 'Temp';
      case SensorMeasurement.light:
        return 'Light';
      case SensorMeasurement.rain:
        return 'Rain';
      case SensorMeasurement.frost:
        return 'Frost';
      case SensorMeasurement.soil:
        return 'Soil';
      default:
        return '';
    }
  }

  String get unit {
    switch (this) {
      case SensorMeasurement.humidity:
        return '%';
      case SensorMeasurement.temperature:
        return 'F';
      case SensorMeasurement.light:
        return 'Lux';
      case SensorMeasurement.rain:
        return '%';
      case SensorMeasurement.frost:
        return 'Radiation Fahrenheit';
      case SensorMeasurement.soil:
        return '%';
      default:
        return '';
    }
  }
}

// Where site selection will resolve to
enum SiteRoute {
  dashboard,
  sensorManagement
}