import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/organization.dart';

class OrganizationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get user's organizations
  Stream<List<Organization>> getUserOrganizations() {
    final userId = _auth.currentUser!.uid;
    
    // Query all organizations where the user is a member
    // We'll search through all organizations for this user's membership
    return _firestore
        .collection('organizations')
        .snapshots()
        .asyncMap((orgSnapshot) async {
      // For each organization, check if user is a member
      final memberChecks = await Future.wait(
        orgSnapshot.docs.map((orgDoc) async {
          final memberDoc = await orgDoc.reference
              .collection('members')
              .doc(userId)
              .get();
          
          return memberDoc.exists ? orgDoc : null;
        })
      );
      
      // Filter out nulls and convert to Organization objects
      return memberChecks
          .where((doc) => doc != null)
          .map((doc) => Organization.fromFirestore(doc!))
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