import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/sensor.dart';
import 'sensor_lookup_service.dart';

class SensorService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SensorLookupService _lookupService = SensorLookupService();

  /// Get real-time stream of sensors for a specific zone
  Stream<List<Sensor>> getSensors(String orgId, String siteId, String zoneId) {
    return _firestore
        .collection('organizations')
        .doc(orgId)
        .collection('sites')
        .doc(siteId)
        .collection('zones')
        .doc(zoneId)
        .collection('sensors')
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Sensor.fromFirestore(doc)).toList());
  }

  /// Get a single sensor
  Future<Sensor?> getSensor(String orgId, String siteId, String zoneId, String sensorId) async {
    try {
      final doc = await _firestore
          .collection('organizations')
          .doc(orgId)
          .collection('sites')
          .doc(siteId)
          .collection('zones')
          .doc(zoneId)
          .collection('sensors')
          .doc(sensorId)
          .get();

      if (doc.exists) {
        return Sensor.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('Error getting sensor: $e');
      return null;
    }
  }

  /// Create a new sensor
  Future<String> createSensor({
    required String orgId,
    required String siteId,
    required String zoneId,
    required String name,
    required String model,
    GeoPoint? location,
    Map<String, SensorField>? fields,
  }) async {
    try {
      final now = DateTime.now();
      final docRef = _firestore
          .collection('organizations')
          .doc(orgId)
          .collection('sites')
          .doc(siteId)
          .collection('zones')
          .doc(zoneId)
          .collection('sensors')
          .doc();

      final sensorFields = fields ?? getDefaultFieldsForModel(model);
      
      final sensor = Sensor(
        id: docRef.id,
        name: name,
        model: model,
        location: location,
        fields: sensorFields,
        status: 'inactive',
        isOnline: false,
        createdAt: now,
        updatedAt: now,
      );

      await docRef.set(sensor.toFirestore());
      
      // Create corresponding sensorLookup entry
      await _lookupService.upsertSensorLookup(
        orgId: orgId,
        siteId: siteId,
        zoneId: zoneId,
        sensorId: docRef.id,
        sensorName: name,
        sensorModel: model,
        fields: sensorFields.keys.toList(),
      );
      
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create sensor: $e');
    }
  }

  /// Update sensor details
  Future<void> updateSensor(
    String orgId,
    String siteId,
    String zoneId,
    String sensorId,
    Map<String, dynamic> updates,
  ) async {
    try {
      updates['updatedAt'] = Timestamp.fromDate(DateTime.now());
      
      await _firestore
          .collection('organizations')
          .doc(orgId)
          .collection('sites')
          .doc(siteId)
          .collection('zones')
          .doc(zoneId)
          .collection('sensors')
          .doc(sensorId)
          .update(updates);
      
      // Update sensorLookup if name or model changed
      if (updates.containsKey('name') || updates.containsKey('model')) {
        final sensor = await getSensor(orgId, siteId, zoneId, sensorId);
        if (sensor != null) {
          await _lookupService.upsertSensorLookup(
            orgId: orgId,
            siteId: siteId,
            zoneId: zoneId,
            sensorId: sensorId,
            sensorName: sensor.name,
            sensorModel: sensor.model,
            fields: sensor.fields.keys.toList(),
          );
        }
      }
    } catch (e) {
      throw Exception('Failed to update sensor: $e');
    }
  }

  /// Update a specific sensor field value
  Future<void> updateSensorField(
    String orgId,
    String siteId,
    String zoneId,
    String sensorId,
    String fieldName,
    double value,
    String unit,
  ) async {
    try {
      final now = DateTime.now();
      await _firestore
          .collection('organizations')
          .doc(orgId)
          .collection('sites')
          .doc(siteId)
          .collection('zones')
          .doc(zoneId)
          .collection('sensors')
          .doc(sensorId)
          .update({
        'fields.$fieldName.currentValue': value,
        'fields.$fieldName.unit': unit,
        'fields.$fieldName.lastUpdated': Timestamp.fromDate(now),
        'lastReading': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
    } catch (e) {
      throw Exception('Failed to update sensor field: $e');
    }
  }

  /// Delete a sensor
  Future<void> deleteSensor(String orgId, String siteId, String zoneId, String sensorId) async {
    try {
      await _firestore
          .collection('organizations')
          .doc(orgId)
          .collection('sites')
          .doc(siteId)
          .collection('zones')
          .doc(zoneId)
          .collection('sensors')
          .doc(sensorId)
          .delete();
      
      // Also delete the sensorLookup entry
      await _lookupService.deleteSensorLookup(sensorId);
    } catch (e) {
      throw Exception('Failed to delete sensor: $e');
    }
  }

  /// Update sensor status
  Future<void> updateSensorStatus(
    String orgId,
    String siteId,
    String zoneId,
    String sensorId,
    String status,
  ) async {
    try {
      await _firestore
          .collection('organizations')
          .doc(orgId)
          .collection('sites')
          .doc(siteId)
          .collection('zones')
          .doc(zoneId)
          .collection('sensors')
          .doc(sensorId)
          .update({
        'status': status,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      throw Exception('Failed to update sensor status: $e');
    }
  }

  /// Update sensor online status
  Future<void> updateSensorOnlineStatus(
    String orgId,
    String siteId,
    String zoneId,
    String sensorId,
    bool isOnline,
  ) async {
    try {
      await _firestore
          .collection('organizations')
          .doc(orgId)
          .collection('sites')
          .doc(siteId)
          .collection('zones')
          .doc(zoneId)
          .collection('sensors')
          .doc(sensorId)
          .update({
        'isOnline': isOnline,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      throw Exception('Failed to update sensor online status: $e');
    }
  }

  /// Get sensor count for a zone
  Future<int> getSensorCount(String orgId, String siteId, String zoneId) async {
    try {
      final snapshot = await _firestore
          .collection('organizations')
          .doc(orgId)
          .collection('sites')
          .doc(siteId)
          .collection('zones')
          .doc(zoneId)
          .collection('sensors')
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      print('Error getting sensor count: $e');
      return 0;
    }
  }

  /// Initialize default fields for a sensor based on model
  Map<String, SensorField> getDefaultFieldsForModel(String model) {
    final now = DateTime.now();
    
    switch (model.toLowerCase()) {
      case 'dht22':
        return {
          'temperature': SensorField(unit: '°F', lastUpdated: now),
          'humidity': SensorField(unit: '%', lastUpdated: now),
        };
      case 'veml7700':
        return {
          'light': SensorField(unit: 'lux', lastUpdated: now),
        };
      case 'dfrobot-soil':
        return {
          'soilTemperature': SensorField(unit: '°F', lastUpdated: now),
          'soilMoisture': SensorField(unit: '%', lastUpdated: now),
          'soilEC': SensorField(unit: 'mS/cm', lastUpdated: now),
        };
      case 'sgp30':
        return {
          'co2': SensorField(unit: 'ppm', lastUpdated: now),
          'tvoc': SensorField(unit: 'ppb', lastUpdated: now),
        };
      default:
        return {};
    }
  }
}
