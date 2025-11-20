import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/organization.dart';
import '../models/member.dart';

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
    
    // Add creator as owner using member permissions
    final ownerPermissions = MemberPermissions.forRole('owner');
    await orgRef.collection('members').doc(userId).set({
      'role': 'owner',
      'permissions': ownerPermissions.toMap(),
      'joinedAt': FieldValue.serverTimestamp(),
      'invitedBy': null,
      'lastActive': null,
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
    final orgRef = _firestore.doc('organizations/$orgId');
    
    // Delete members subcollection
    final membersSnapshot = await orgRef.collection('members').get();
    for (final doc in membersSnapshot.docs) {
      await doc.reference.delete();
    }
    
    // TODO: Delete other subcollections (sites, zones, sensors, etc.) when implemented
    
    // Delete the organization document
    await orgRef.delete();
  }

  // ==================== MEMBER MANAGEMENT ====================

  // Get all members of an organization
  Stream<List<Member>> getOrganizationMembers(String orgId) {
    return _firestore
        .collection('organizations/$orgId/members')
        .snapshots()
        .map((snapshot) {
      final members = snapshot.docs
          .map((doc) => Member.fromFirestore(doc))
          .toList();
      
      // Sort: owners first, then by role
      members.sort((a, b) {
        // Role priority: owner > admin > member > viewer
        final rolePriority = {'owner': 0, 'admin': 1, 'member': 2, 'viewer': 3};
        return (rolePriority[a.role] ?? 99).compareTo(rolePriority[b.role] ?? 99);
      });
      
      return members;
    });
  }

  // Add a member to an organization
  Future<void> addMember({
    required String orgId,
    required String userEmail,
    String role = 'viewer',
  }) async {
    final currentUserId = _auth.currentUser!.uid;
    
    // Find user by email
    final userQuery = await _firestore
        .collection('users')
        .where('email', isEqualTo: userEmail.toLowerCase().trim())
        .limit(1)
        .get();
    
    if (userQuery.docs.isEmpty) {
      throw Exception('User with email $userEmail not found');
    }
    
    final userId = userQuery.docs.first.id;
    
    // Check if user is already a member
    final memberDoc = await _firestore
        .doc('organizations/$orgId/members/$userId')
        .get();
    
    if (memberDoc.exists) {
      throw Exception('User is already a member of this organization');
    }
    
    // Add member with permissions based on role
    final permissions = MemberPermissions.forRole(role);
    
    await _firestore.doc('organizations/$orgId/members/$userId').set({
      'role': role,
      'permissions': permissions.toMap(),
      'joinedAt': FieldValue.serverTimestamp(),
      'invitedBy': currentUserId,
      'lastActive': null,
    });
  }

  // Remove a member from an organization
  Future<void> removeMember({
    required String orgId,
    required String userId,
  }) async {
    final currentUserId = _auth.currentUser!.uid;
    
    // Don't allow removing yourself
    if (userId == currentUserId) {
      throw Exception('You cannot remove yourself from the organization');
    }
    
    // Check if the user being removed is an owner
    final memberDoc = await _firestore
        .doc('organizations/$orgId/members/$userId')
        .get();
    
    if (memberDoc.exists) {
      final memberData = memberDoc.data() as Map<String, dynamic>;
      if (memberData['role'] == 'owner') {
        // Count total owners
        final ownersSnapshot = await _firestore
            .collection('organizations/$orgId/members')
            .where('role', isEqualTo: 'owner')
            .get();
        
        if (ownersSnapshot.docs.length <= 1) {
          throw Exception('Cannot remove the last owner of the organization');
        }
      }
    }
    
    // Remove the member
    await _firestore.doc('organizations/$orgId/members/$userId').delete();
  }

  // Update member role and permissions
  Future<void> updateMemberRole({
    required String orgId,
    required String userId,
    required String newRole,
  }) async {
    final currentUserId = _auth.currentUser!.uid;
    
    // Don't allow changing your own role
    if (userId == currentUserId) {
      throw Exception('You cannot change your own role');
    }
    
    // Get current member data
    final memberDoc = await _firestore
        .doc('organizations/$orgId/members/$userId')
        .get();
    
    if (!memberDoc.exists) {
      throw Exception('Member not found');
    }
    
    final currentData = memberDoc.data() as Map<String, dynamic>;
    final currentRole = currentData['role'];
    
    // If removing owner status, check if there's another owner
    if (currentRole == 'owner' && newRole != 'owner') {
      final ownersSnapshot = await _firestore
          .collection('organizations/$orgId/members')
          .where('role', isEqualTo: 'owner')
          .get();
      
      if (ownersSnapshot.docs.length <= 1) {
        throw Exception('Cannot remove owner role from the last owner');
      }
    }
    
    // Update role and permissions
    final permissions = MemberPermissions.forRole(newRole);
    
    await _firestore.doc('organizations/$orgId/members/$userId').update({
      'role': newRole,
      'permissions': permissions.toMap(),
    });
  }

  // Check if current user has permission to manage members
  Future<bool> canManageMembers(String orgId) async {
    final userId = _auth.currentUser!.uid;
    final memberDoc = await _firestore
        .doc('organizations/$orgId/members/$userId')
        .get();
    
    if (!memberDoc.exists) return false;
    
    final data = memberDoc.data() as Map<String, dynamic>;
    final permissions = data['permissions'] as Map<String, dynamic>?;
    
    return permissions?['canManageMembers'] ?? false;
  }
}
