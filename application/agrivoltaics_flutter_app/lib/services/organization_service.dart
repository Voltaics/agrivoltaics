import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../app_constants.dart';
import '../models/organization.dart';
import '../models/member.dart';
import 'user_service.dart';

enum AddMemberOutcome { added, invited }

class OrganizationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _inviteDocIdForEmail(String normalizedEmail) {
    // Firestore document IDs cannot contain '/'.
    return normalizedEmail.replaceAll('/', '_');
  }

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
    final user = _auth.currentUser;
    if (!AppConstants.canCreateOrganizationForUser(
      uid: user?.uid,
      email: user?.email,
    )) {
      throw Exception('You are not authorized to create organizations.');
    }

    final userId = user!.uid;
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
    final normalizedCreatorEmail = (user.email ?? '').trim().toLowerCase();
    await orgRef.collection('members').doc(userId).set({
      if (normalizedCreatorEmail.isNotEmpty) 'email': normalizedCreatorEmail,
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
    if (!await isOwnerOfOrg(orgId)) {
      throw Exception('Only the organization owner can do this.');
    }

    await _firestore.doc('organizations/$orgId').update({
      ...updates,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Delete organization
  Future<void> deleteOrganization(String orgId) async {
    if (!await isOwnerOfOrg(orgId)) {
      throw Exception('Only the organization owner can do this.');
    }

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

  // Add a member to an organization. If [fullName] is provided: for a user
  // who already has an account, it's applied immediately as their name
  // override; for a not-yet-signed-in user, it's stashed on the invite and
  // applied once they accept (see UserService._acceptPendingInvites).
  Future<AddMemberOutcome> addMember({
    required String orgId,
    required String userEmail,
    String role = 'viewer',
    String? fullName,
  }) async {
    if (!await canManageMembers(orgId)) {
      throw Exception('You do not have permission to manage members in this organization.');
    }

    final trimmedFullName = fullName?.trim();
    final currentUserId = _auth.currentUser!.uid;
    final normalizedEmail = userEmail.trim().toLowerCase();
    final inviteDocId = _inviteDocIdForEmail(normalizedEmail);
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    if (normalizedEmail.isEmpty) {
      throw Exception('Email is required');
    }

    if (!emailRegex.hasMatch(normalizedEmail)) {
      throw Exception('Please provide a valid email address.');
    }

    final existingByEmail = await _firestore
        .collection('organizations/$orgId/members')
        .where('email', isEqualTo: normalizedEmail)
        .limit(1)
        .get();

    if (existingByEmail.docs.isNotEmpty) {
      throw Exception('User is already a member of this organization');
    }
    
    // Find user by email
    final userQuery = await _firestore
        .collection('users')
        .where('email', isEqualTo: normalizedEmail)
        .limit(1)
        .get();

    final permissions = MemberPermissions.forRole(role);

    if (userQuery.docs.isEmpty) {
      final inviteRef = _firestore.doc(
        'organizations/$orgId/pendingInvites/$inviteDocId',
      );

      await inviteRef.set({
        'orgId': orgId,
        'email': normalizedEmail,
        'emailOriginal': userEmail.trim(),
        'role': role,
        'permissions': permissions.toMap(),
        'status': 'pending',
        'invitedBy': currentUserId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (trimmedFullName != null && trimmedFullName.isNotEmpty)
          'fullName': trimmedFullName,
      }, SetOptions(merge: true));

      return AddMemberOutcome.invited;
    }
    
    final userId = userQuery.docs.first.id;
    
    // Check if user is already a member
    final memberDoc = await _firestore
        .doc('organizations/$orgId/members/$userId')
        .get();
    
    if (memberDoc.exists) {
      throw Exception('User is already a member of this organization');
    }

    await _firestore
        .doc('organizations/$orgId/pendingInvites/$inviteDocId')
        .delete();
    
    await _firestore.doc('organizations/$orgId/members/$userId').set({
      'email': normalizedEmail,
      'role': role,
      'permissions': permissions.toMap(),
      'joinedAt': FieldValue.serverTimestamp(),
      'invitedBy': currentUserId,
      'lastActive': null,
    });

    if (trimmedFullName != null && trimmedFullName.isNotEmpty) {
      await UserService().updateFullName(userId, trimmedFullName);
    }

    return AddMemberOutcome.added;
  }

  // Remove a member from an organization
  Future<void> removeMember({
    required String orgId,
    required String userId,
  }) async {
    if (!await canManageMembers(orgId)) {
      throw Exception('You do not have permission to manage members in this organization.');
    }

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
    if (!await canManageMembers(orgId)) {
      throw Exception('You do not have permission to manage members in this organization.');
    }

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

    // Granting or revoking owner status is an owner-only action — being an
    // admin (canManageMembers above) is not enough, otherwise an admin could
    // promote an arbitrary member to owner.
    if ((currentRole == 'owner' || newRole == 'owner') &&
        !await isOwnerOfOrg(orgId)) {
      throw Exception('Only an owner can grant or revoke owner status.');
    }

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

  // Whether the current user is the owner (not just admin) of orgId.
  Future<bool> isOwnerOfOrg(String orgId) async {
    final userId = _auth.currentUser!.uid;
    final memberDoc = await _firestore
        .doc('organizations/$orgId/members/$userId')
        .get();

    if (!memberDoc.exists) return false;

    final data = memberDoc.data() as Map<String, dynamic>;
    return data['role'] == 'owner';
  }

  // Whether the current user is a member (any role) of orgId.
  Future<bool> isMemberOfOrg(String orgId) async {
    final userId = _auth.currentUser!.uid;
    final memberDoc = await _firestore
        .doc('organizations/$orgId/members/$userId')
        .get();

    return memberDoc.exists;
  }

  // Whether the current user has member-management permission in at least
  // one organization. Gates access to the cross-org Member Directory and to
  // full-name editing, since both surface/affect data beyond a single org.
  Future<bool> canManageMembersInAnyOrg() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return false;

    final orgSnapshot = await _firestore.collection('organizations').get();
    final checks = await Future.wait(
      orgSnapshot.docs.map((orgDoc) async {
        final memberDoc = await orgDoc.reference.collection('members').doc(userId).get();
        if (!memberDoc.exists) return false;
        final data = memberDoc.data() as Map<String, dynamic>;
        final permissions = data['permissions'] as Map<String, dynamic>?;
        return permissions?['canManageMembers'] ?? false;
      }),
    );

    return checks.any((canManage) => canManage);
  }

  // Every organization the given user email belongs to, with their role.
  // Used by the Member Directory to show cross-org membership status.
  Future<List<MemberOrganizationRef>> getOrganizationsForEmail(String normalizedEmail) async {
    final memberDocs = await _firestore
        .collectionGroup('members')
        .where('email', isEqualTo: normalizedEmail)
        .get();

    final refs = await Future.wait(memberDocs.docs.map((doc) async {
      final orgId = doc.reference.parent.parent!.id;
      final orgDoc = await _firestore.doc('organizations/$orgId').get();
      final orgName = orgDoc.data()?['name'] as String? ?? 'Unknown organization';
      final role = doc.data()['role'] as String? ?? 'viewer';
      return MemberOrganizationRef(orgId: orgId, orgName: orgName, role: role);
    }));

    return refs;
  }

  // Every organization with a pending (not yet accepted) invite for the
  // given email. Used by the Member Directory to surface outstanding invites.
  Future<List<MemberOrganizationRef>> getPendingInvitesForEmail(String normalizedEmail) async {
    final inviteDocs = await _firestore
        .collectionGroup('pendingInvites')
        .where('email', isEqualTo: normalizedEmail)
        .where('status', isEqualTo: 'pending')
        .get();

    final refs = await Future.wait(inviteDocs.docs.map((doc) async {
      final orgId = doc.data()['orgId'] as String? ?? doc.reference.parent.parent!.id;
      final orgDoc = await _firestore.doc('organizations/$orgId').get();
      final orgName = orgDoc.data()?['name'] as String? ?? 'Unknown organization';
      final role = doc.data()['role'] as String? ?? 'viewer';
      return MemberOrganizationRef(orgId: orgId, orgName: orgName, role: role);
    }));

    return refs;
  }

  // Organizations where the current user can manage members — used to scope
  // the "Add to Organization" picker on the Member Directory page.
  Future<List<Organization>> getManageableOrganizations() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return [];

    final orgSnapshot = await _firestore.collection('organizations').get();
    final results = <Organization>[];

    for (final orgDoc in orgSnapshot.docs) {
      final memberDoc = await orgDoc.reference.collection('members').doc(userId).get();
      if (!memberDoc.exists) continue;
      final data = memberDoc.data() as Map<String, dynamic>;
      final permissions = data['permissions'] as Map<String, dynamic>?;
      if (permissions?['canManageMembers'] == true) {
        results.add(Organization.fromFirestore(orgDoc));
      }
    }

    return results;
  }
}

/// Lightweight reference to an organization + a role/relationship, used by
/// the Member Directory to show cross-org membership and invite status
/// without pulling in the full Organization/Member models.
class MemberOrganizationRef {
  final String orgId;
  final String orgName;
  final String role;

  MemberOrganizationRef({
    required this.orgId,
    required this.orgName,
    required this.role,
  });
}
