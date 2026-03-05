import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/site.dart';

class SiteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get all sites for an organization
  Stream<List<Site>> getSites(String orgId) {
    return _firestore
        .collection('organizations/$orgId/sites')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Site.fromFirestore(doc))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // Newest first
    });
  }

  // Get single site
  Future<Site?> getSite(String orgId, String siteId) async {
    final doc = await _firestore
        .doc('organizations/$orgId/sites/$siteId')
        .get();
    
    if (!doc.exists) return null;
    return Site.fromFirestore(doc);
  }

  // Create site
  Future<String> createSite({
    required String orgId,
    required String name,
    String? description,
    GeoPoint? location,
    String? address,
    String? timezone,
    bool isActive = true,
    bool siteChecked = true,
  }) async {
    final userId = _auth.currentUser!.uid;
    final siteRef = _firestore.collection('organizations/$orgId/sites').doc();
    
    final site = Site(
      id: siteRef.id,
      name: name,
      description: description ?? '',
      location: location,
      address: address ?? '',
      timezone: timezone ?? 'America/New_York',
      isActive: isActive,
      lastDataReceived: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      createdBy: userId,
      siteChecked: siteChecked,
    );
    
    await siteRef.set(site.toFirestore());
    
    return siteRef.id;
  }

  // Update site
  Future<void> updateSite(
    String orgId,
    String siteId,
    Map<String, dynamic> updates,
  ) async {
    await _firestore
        .doc('organizations/$orgId/sites/$siteId')
        .update({
      ...updates,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Delete site
  Future<void> deleteSite(String orgId, String siteId) async {
    final siteRef = _firestore.doc('organizations/$orgId/sites/$siteId');
    
    // Delete zones subcollection
    final zonesSnapshot = await siteRef.collection('zones').get();
    for (final zoneDoc in zonesSnapshot.docs) {
      // Delete sensors subcollection within each zone
      final sensorsSnapshot = await zoneDoc.reference.collection('sensors').get();
      for (final sensorDoc in sensorsSnapshot.docs) {
        await sensorDoc.reference.delete();
      }
      // Delete the zone
      await zoneDoc.reference.delete();
    }
    
    // Delete the site document
    await siteRef.delete();
  }

  // Toggle site active status
  Future<void> toggleSiteActive(String orgId, String siteId, bool isActive) async {
    await updateSite(orgId, siteId, {'isActive': isActive});
  }

  // Toggle site checked (visibility)
  Future<void> toggleSiteChecked(String orgId, String siteId, bool checked) async {
    await updateSite(orgId, siteId, {'siteChecked': checked});
  }

  // Update last data received timestamp
  Future<void> updateLastDataReceived(String orgId, String siteId) async {
    await updateSite(orgId, siteId, {
      'lastDataReceived': FieldValue.serverTimestamp(),
    });
  }
}
