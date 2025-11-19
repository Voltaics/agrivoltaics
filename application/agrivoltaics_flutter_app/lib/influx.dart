import 'package:agrivoltaics_flutter_app/app_constants.dart';
import 'package:get_it/get_it.dart';
import 'package:influxdb_client/api.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'package:agrivoltaics_flutter_app/app_state.dart';
import 'package:timezone/standalone.dart' as tz;

var getIt = GetIt.instance;
var influxDBClient = getIt.get<InfluxDBClient>();

String singleGraphQuery
(
  PickerDateRange timeUnit,
  TimeInterval timeInterval,
  List<Site> sites,
  bool singleGraphToggle,
  int numberOfZones,
  String returnDataValue
) {
  var startDate = DateFormat('yyyy-MM-dd').format(timeUnit.startDate!.toUtc());
  var endDate = DateFormat('yyyy-MM-dd').format(timeUnit.endDate!.toUtc());

  String query = "|> filter(fn: (r) => ";

  for (int i = 1; i <= sites.length; i++) {
    if (sites[i-1].checked) {
      for (int j = 1; j <= sites[i-1].zones.length; j++) {
        if (sites[i-1].zones[j-1].checked) {
          

          numberOfZones -= 1;
          if (numberOfZones == 0) {
            query += '(r._measurement == "${sites[i-1].name}" and (r.Zone == "$j"';
            List<MapEntry<SensorMeasurement, bool>> fieldEntries = sites[i-1].zones[j-1].fields.entries.toList();

            int fieldCount = 0;

            for (var entry in fieldEntries) {
              bool checked = entry.value;

              if (checked == true) {
                fieldCount++;
              }
            }

            if (fieldCount == 0) {
              query += ' and (r._field == "N/A"))';
            }
            else {
              bool firstCheckedSite = true;
              for (int k = 1; k <= sites[i-1].zones[j-1].fields.length; k++) {
                MapEntry<SensorMeasurement, bool> firstEntry = fieldEntries[k-1];
                String measurement = firstEntry.key.fluxQuery;
                bool checked = firstEntry.value;

                if (checked) {
                  if (fieldCount == 1) {
                    query += ' and (r._field == "$measurement"))';
                  }
                  else if (k == 1 || firstCheckedSite == true) {
                    query += ' and (r._field == "$measurement"';
                    firstCheckedSite = false;
                  } else if (k != sites[i-1].zones[j-1].fields.length) {
                    query += ' or r._field  == "$measurement"';
                  } else {
                    query += ' or r._field  == "$measurement"))';
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  int openBrackets = query.split('(').length - 1;
  int closeBrackets = query.split(')').length - 1;

  int balance = openBrackets - closeBrackets;

  if (balance > 0) {
    query += ')' * balance;
  } else if (balance < 0) {
    query = query.substring(0, query.length + balance);
  }

  return '''
  from(bucket: "${AppConstants.influxdbBucket}")
  |> range(start: ${startDate}T00:00:00Z, stop: ${endDate}T23:59:00Z)
  $query
  |> map(fn: (r) => ({
      r with
      _value: if r._field == "temperature" then float(v: r._value) * 9.0/5.0 + 32.0 else float(v: r._value)
    }))
  |> aggregateWindow(every: ${timeInterval.value}${timeInterval.unit.fluxQuery}, fn: $returnDataValue, createEmpty: false)
  ''';
}
// Generate InfluxDB Flux Query
String _generateQuery
(
  PickerDateRange timeUnit,
  TimeInterval timeInterval,
  List<Site> sites,
  bool singleGraphToggle,
  int numberOfZones,
  String returnDataValue
) {

  String finalQuery='';

// first case is if the toggle for multiple sites is selected
if (singleGraphToggle == false) {
  finalQuery = singleGraphQuery(timeUnit, timeInterval, sites, singleGraphToggle, numberOfZones, returnDataValue);
} 
else {
  List<String> unionStrings = [];
    var startDate = DateFormat('yyyy-MM-dd').format(timeUnit.startDate!.toUtc());
    var endDate = DateFormat('yyyy-MM-dd').format(timeUnit.endDate!.toUtc());
    String filterString = '';
    for (int i = 1; i <= sites.length; i++) {
      for (int j = 1; j <= sites[i-1].zones.length; j++) {
        if (sites[i-1].zones[j-1].checked) {
          bool firstFieldChecked = false;
          filterString = '|> filter(fn: (r) => (r._measurement == "${sites[i-1].name}" and (r.Zone == "$j" and (';
          // logic goes here
          List<MapEntry<SensorMeasurement, bool>> fieldEntries = sites[i-1].zones[j-1].fields.entries.toList();
          for (int k = 1; k <= sites[i-1].zones[j-1].fields.length; k++) {

            // if true then the field is checked
            if (fieldEntries[k-1].value == true) {
              //first iteration doesn't have or at the beginning
              String fieldName = fieldEntries[k-1].key.fluxQuery;
              if (firstFieldChecked == false) {
                filterString += 'r._field == "$fieldName"';
                firstFieldChecked = true;
              } else {
                filterString += 'or r._field == "$fieldName"';
              }
            }
          }
          filterString += "))))";

          String unionString = '''
                              from(bucket: "${AppConstants.influxdbBucket}")
                              |> range(start: ${startDate}T00:00:00Z, stop: ${endDate}T23:59:00Z)
                              $filterString
                              |> map(fn: (r) => ({
                                  r with
                                  _value: if r._field == "temperature" then float(v: r._value) * 9.0/5.0 + 32.0 else float(v: r._value)
                              }))
                              |> aggregateWindow(every: ${timeInterval.value}${timeInterval.unit.fluxQuery}, fn: $returnDataValue, createEmpty: false),
                              ''';

          unionStrings.add(unionString);
        }
      }

      finalQuery = 'union(tables: [\n';
      for (int i = 0; i < unionStrings.length; i++) {
        finalQuery += unionStrings[i];

        // If it's not the last query, print a newline
        if (i < unionStrings.length - 1) {
           finalQuery += '\n'; // newline
        }
      }
      finalQuery += '])';
    }
}

return finalQuery;
}

// Get data from InfluxDB according to specified parameters
Future<Map<String, List<FluxRecord>>> getInfluxData
(
  PickerDateRange timeUnit,
  TimeInterval timeInterval,
  List<Site> sites,
  bool singleGraphToggle,
  int numberOfZones,
  String returnDataValue
) async {
  var queryService = influxDBClient.getQueryService();

  var dataSets = <String, List<FluxRecord>>{};    
  String query = _generateQuery(timeUnit, timeInterval, sites, singleGraphToggle, numberOfZones, returnDataValue);

  Stream<FluxRecord> recordStream = await queryService.query(query);

  List<FluxRecord> records = await recordStream.toList();
  for (var record in records) {
    // DO NOT EXECUTE THE BELOW OR THE RECORDSTREAM WILL NEVER BE READ
    // WHO KNOWS WHY, I SURE DON'T
    // TOOK ME 3 HOURS OF DEBUGGING TO FIGURE THAT ONE OUT
    // String field = record['_field'];
    // String zone = record['Zone'];

    SensorMeasurement measurement = SensorMeasurement.values.firstWhere((e) => e.fluxQuery == record['_field']);

    String key = '${measurement.displayName} (${measurement.unit}) Zone ${record["Zone"]}';
    if (!dataSets.keys.contains(key)) {
      dataSets[key] = [record];
    } else {
      dataSets[key]!.add(record);
    }
  }
  
  Map<String, List<FluxRecord>> sortedDataSets = Map.fromEntries(
    dataSets.entries.toList()..sort((e1, e2) => e1.key.compareTo(e2.key))
  );
  return sortedDataSets;
}

// TODO: document these properly, maybe clean up/rename to make more understandable
class InfluxDatapoint {
  InfluxDatapoint(DateTime timeStamp, this.value, this.unit, tz.Location timezone) {
    this.timeStamp = DateFormat('yyyy-MM-dd kk:mm:ss').format(tz.TZDateTime.from(timeStamp, timezone));
  }
  late String timeStamp;
  final double? value;
  final String unit;
}

class InfluxData {
  InfluxData(this.data, tz.Location timezone) {
    for (var record in this.data.value) {
      DateTime timestamp = DateTime.parse(record['_time']);
      String field = record['_field'];
      double? value = record['_value'];
      String unit = SensorMeasurement.values.firstWhere((e) => e.fluxQuery == field).unit;
      this.datapoints.add(InfluxDatapoint(timestamp, value, unit, timezone));
    }
  }
  // final List<FluxRecord> records;
  MapEntry<String, List<FluxRecord>> data;
  List<InfluxDatapoint> datapoints = [];
}