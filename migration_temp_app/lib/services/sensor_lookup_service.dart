import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/sensor_lookup.dart';

class SensorLookupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get a sensor lookup by sensor ID (primary lookup method)
  Future<SensorLookup?> getSensorLookup(String sensorId) async {
    try {
      final doc = await _firestore
          .collection('sensorLookup')
          .doc(sensorId)
          .get();

      if (doc.exists) {
        return SensorLookup.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('Error getting sensor lookup: $e');
      return null;
    }
  }

  /// Get all sensor lookups
  Stream<List<SensorLookup>> getAllSensorLookups() {
    return _firestore
        .collection('sensorLookup')
        .orderBy('sensorName')
        .snapshots()
        .map((snapshot) => 
            snapshot.docs.map((doc) => SensorLookup.fromFirestore(doc)).toList());
  }

  /// Get sensor lookups for a specific organization
  Stream<List<SensorLookup>> getSensorLookupsByOrg(String orgId) {
    return _firestore
        .collection('sensorLookup')
        .where('organizationId', isEqualTo: orgId)
        .orderBy('sensorName')
        .snapshots()
        .map((snapshot) => 
            snapshot.docs.map((doc) => SensorLookup.fromFirestore(doc)).toList());
  }

  /// Create or update a sensor lookup entry
  /// This should be called when a sensor is created or updated
  Future<void> upsertSensorLookup({
    required String orgId,
    required String siteId,
    required String zoneId,
    required String sensorId,
    required String sensorModel,
    required String sensorName,
    required List<String> fields,
    bool isActive = true,
  }) async {
    try {
      final now = DateTime.now();
      final sensorDocPath = 'organizations/$orgId/sites/$siteId/zones/$zoneId/sensors/$sensorId';

      // Check if lookup already exists
      final existingDoc = await _firestore
          .collection('sensorLookup')
          .doc(sensorId)
          .get();

      final lookup = SensorLookup(
        id: sensorId,
        sensorDocPath: sensorDocPath,
        organizationId: orgId,
        siteId: siteId,
        zoneId: zoneId,
        sensorId: sensorId,
        sensorModel: sensorModel,
        sensorName: sensorName,
        fields: fields,
        isActive: isActive,
        registeredAt: existingDoc.exists 
            ? (existingDoc.data()!['registeredAt'] as Timestamp).toDate()
            : now,
        updatedAt: now,
      );

      await _firestore
          .collection('sensorLookup')
          .doc(sensorId)
          .set(lookup.toFirestore());
    } catch (e) {
      throw Exception('Failed to upsert sensor lookup: $e');
    }
  }

  /// Delete a sensor lookup entry by sensor ID
  Future<void> deleteSensorLookup(String sensorId) async {
    try {
      await _firestore
          .collection('sensorLookup')
          .doc(sensorId)
          .delete();
    } catch (e) {
      throw Exception('Failed to delete sensor lookup: $e');
    }
  }

  /// Update the last data received timestamp
  /// This should be called when data is received for a sensor
  Future<void> updateLastDataReceived(String sensorId) async {
    try {
      await _firestore
          .collection('sensorLookup')
          .doc(sensorId)
          .update({
        'lastDataReceived': Timestamp.fromDate(DateTime.now()),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      throw Exception('Failed to update last data received: $e');
    }
  }

  /// Update sensor lookup active status
  Future<void> updateActiveStatus(String sensorId, bool isActive) async {
    try {
      await _firestore
          .collection('sensorLookup')
          .doc(sensorId)
          .update({
        'isActive': isActive,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      throw Exception('Failed to update active status: $e');
    }
  }
}
