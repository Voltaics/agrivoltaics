import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/organization.dart';

class OrganizationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get user's organizations
  Stream<List<Organization>> getUserOrganizations() {
    final userId = _auth.currentUser!.uid;
    
    return _firestore
        .collectionGroup('members')
        .where(FieldPath.documentId, isEqualTo: userId)
        .snapshots()
        .asyncMap((snapshot) async {
      // Get org IDs from member docs
      final orgIds = snapshot.docs
          .map((doc) => doc.reference.parent.parent!.id)
          .toList();
      
      if (orgIds.isEmpty) return [];
      
      // Fetch organization documents
      final orgDocs = await Future.wait(
        orgIds.map((id) => _firestore.doc('organizations/$id').get())
      );
      
      return orgDocs
          .where((doc) => doc.exists)
          .map((doc) => Organization.fromFirestore(doc))
          .toList();
    });
  }

  // Get single organization
  Future<Organization?> getOrganization(String orgId) async {
    final doc = await _firestore.doc('organizations/$orgId').get();
    if (!doc.exists) return null;
    return Organization.fromFirestore(doc);
  }

  // Create organization
  Future<String> createOrganization({
    required String name,
    String? description,
    String? logoUrl,
  }) async {
    final userId = _auth.currentUser!.uid;
    final orgRef = _firestore.collection('organizations').doc();
    
    final org = Organization(
      id: orgRef.id,
      name: name,
      description: description ?? '',
      logoUrl: logoUrl,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      createdBy: userId
    );
    
    // Create org document
    await orgRef.set(org.toFirestore());
    
    // Add creator as owner
    await orgRef.collection('members').doc(userId).set({
      'role': 'owner',
      'permissions': {
        'canManageMembers': true,
        'canManageSites': true,
        'canManageSensors': true
      },
      'joinedAt': FieldValue.serverTimestamp(),
      'invitedBy': null
    });
    
    return orgRef.id;
  }

  // Update organization
  Future<void> updateOrganization(
    String orgId,
    Map<String, dynamic> updates,
  ) async {
    await _firestore.doc('organizations/$orgId').update({
      ...updates,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Delete organization
  Future<void> deleteOrganization(String orgId) async {
    // TODO: Delete subcollections (members, sites, etc.)
    await _firestore.doc('organizations/$orgId').delete();
  }
}