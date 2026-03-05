import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/zone.dart';

class ZoneService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get all zones for a site
  Stream<List<Zone>> getZones(String orgId, String siteId) {
    return _firestore
        .collection('organizations/$orgId/sites/$siteId/zones')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Zone.fromFirestore(doc))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name)); // Sort alphabetically by name
    });
  }

  // Get single zone
  Future<Zone?> getZone(String orgId, String siteId, String zoneId) async {
    final doc = await _firestore
        .doc('organizations/$orgId/sites/$siteId/zones/$zoneId')
        .get();
    
    if (!doc.exists) return null;
    return Zone.fromFirestore(doc);
  }

  // Create zone
  Future<String> createZone({
    required String orgId,
    required String siteId,
    required String name,
    String? description,
    GeoPoint? location,
    bool zoneChecked = true,
  }) async {
    final zoneRef = _firestore
        .collection('organizations/$orgId/sites/$siteId/zones')
        .doc();
    
    final zone = Zone(
      id: zoneRef.id,
      name: name,
      description: description ?? '',
      location: location,
      zoneChecked: zoneChecked,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    
    await zoneRef.set(zone.toFirestore());
    
    return zoneRef.id;
  }

  // Update zone
  Future<void> updateZone(
    String orgId,
    String siteId,
    String zoneId,
    Map<String, dynamic> updates,
  ) async {
    await _firestore
        .doc('organizations/$orgId/sites/$siteId/zones/$zoneId')
        .update({
      ...updates,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Delete zone
  Future<void> deleteZone(String orgId, String siteId, String zoneId) async {
    final zoneRef = _firestore
        .doc('organizations/$orgId/sites/$siteId/zones/$zoneId');
    
    // Delete all sensors in this zone
    final sensorsSnapshot = await zoneRef.collection('sensors').get();
    for (final sensorDoc in sensorsSnapshot.docs) {
      await sensorDoc.reference.delete();
    }
    
    // Delete the zone document
    await zoneRef.delete();
  }

  // Toggle zone checked (visibility)
  Future<void> toggleZoneChecked(
    String orgId,
    String siteId,
    String zoneId,
    bool checked,
  ) async {
    await updateZone(orgId, siteId, zoneId, {'zoneChecked': checked});
  }

  // Get zone count for a site
  Future<int> getZoneCount(String orgId, String siteId) async {
    final snapshot = await _firestore
        .collection('organizations/$orgId/sites/$siteId/zones')
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  // Batch create multiple zones (useful for initial setup)
  Future<List<String>> createZones({
    required String orgId,
    required String siteId,
    required List<String> zoneNames,
  }) async {
    final batch = _firestore.batch();
    final zoneIds = <String>[];
    
    for (final zoneName in zoneNames) {
      final zoneRef = _firestore
          .collection('organizations/$orgId/sites/$siteId/zones')
          .doc();
      
      final zone = Zone(
        id: zoneRef.id,
        name: zoneName,
        description: '',
        location: null,
        zoneChecked: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      batch.set(zoneRef, zone.toFirestore());
      zoneIds.add(zoneRef.id);
    }
    
    await batch.commit();
    return zoneIds;
  }
}
