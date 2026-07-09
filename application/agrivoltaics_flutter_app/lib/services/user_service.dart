import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user.dart';
import 'organization_service.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user's document
  Future<AppUser?> getCurrentUser() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return null;
    
    final doc = await _firestore.doc('users/$userId').get();
    if (!doc.exists) return null;
    
    return AppUser.fromFirestore(doc);
  }

  // Stream current user's document
  Stream<AppUser?> getCurrentUserStream() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return Stream.value(null);
    
    return _firestore
        .doc('users/$userId')
        .snapshots()
        .map((doc) => doc.exists ? AppUser.fromFirestore(doc) : null);
  }

  // Get user by ID. contextOrgId scopes the lookup: the caller and the
  // target user must both be members of that org, so this can't be used to
  // look up an arbitrary unrelated user.
  Future<AppUser?> getUser(String userId, String contextOrgId) async {
    final orgService = OrganizationService();
    if (!await orgService.isMemberOfOrg(contextOrgId)) {
      throw Exception('You are not a member of this organization.');
    }

    final doc = await _firestore.doc('users/$userId').get();
    if (!doc.exists) return null;
    return AppUser.fromFirestore(doc);
  }

  // Create or update user document (call after authentication)
  Future<void> createOrUpdateUser({
    String? displayName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final normalizedEmail = (user.email ?? '').trim().toLowerCase();

    final userDoc = await _firestore.doc('users/${user.uid}').get();

    if (!userDoc.exists) {
      // Create new user document
      await _firestore.doc('users/${user.uid}').set({
        'uid': user.uid,
        'email': normalizedEmail,
        'displayName': displayName ?? user.displayName ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      });
    } else {
      // Update existing user document
      final updates = <String, dynamic>{
        'email': normalizedEmail,
        'lastLogin': FieldValue.serverTimestamp(),
      };
      
      if (displayName != null) updates['displayName'] = displayName;
      
      await _firestore.doc('users/${user.uid}').update(updates);
    }

    if (normalizedEmail.isNotEmpty) {
      try {
        await _acceptPendingInvites(
          userId: user.uid,
          normalizedEmail: normalizedEmail,
        );
      } catch (_) {
        // Invitation reconciliation should never block login.
      }
    }
  }

  Future<void> _acceptPendingInvites({
    required String userId,
    required String normalizedEmail,
  }) async {
    final invites = await _firestore
        .collectionGroup('pendingInvites')
        .where('email', isEqualTo: normalizedEmail)
        .get();

    final userRef = _firestore.doc('users/$userId');

    for (final inviteDoc in invites.docs) {
      final inviteData = inviteDoc.data();
      final status = (inviteData['status'] as String?) ?? 'pending';
      if (status != 'pending') {
        continue;
      }

      final orgId = inviteData['orgId'] as String?;
      if (orgId == null || orgId.isEmpty) {
        continue;
      }

      final memberRef = _firestore.doc('organizations/$orgId/members/$userId');
      final inviteFullName = (inviteData['fullName'] as String?)?.trim();

      await _firestore.runTransaction((tx) async {
        // All reads must happen before any writes within a transaction.
        final existingMember = await tx.get(memberRef);
        final needsFullNameCheck = inviteFullName != null && inviteFullName.isNotEmpty;
        final userSnapshot = needsFullNameCheck ? await tx.get(userRef) : null;

        if (!existingMember.exists) {
          tx.set(memberRef, {
            'email': normalizedEmail,
            'role': inviteData['role'] ?? 'viewer',
            'permissions': inviteData['permissions'] ?? {},
            'joinedAt': FieldValue.serverTimestamp(),
            'invitedBy': inviteData['invitedBy'],
            'lastActive': null,
          });
        }

        // Only apply the invite's name if the user doesn't already have an
        // override set, so an earlier edit is never clobbered.
        if (needsFullNameCheck) {
          final existingFullName =
              (userSnapshot?.data()?['fullName'] as String?)?.trim() ?? '';
          if (existingFullName.isEmpty) {
            tx.update(userRef, {'fullName': inviteFullName});
          }
        }

        tx.update(inviteDoc.reference, {
          'status': 'accepted',
          'acceptedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    }
  }

  // Update profile information
  Future<void> updateProfile({
    String? displayName,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    final updates = <String, dynamic>{};
    if (displayName != null) updates['displayName'] = displayName;

    if (updates.isNotEmpty) {
      await _firestore.doc('users/$userId').update(updates);
    }
  }

  /// Admin-facing override of another (or the current) user's display name.
  /// Distinct from [updateProfile], which only ever touches the caller's own
  /// document — this requires the caller to manage members in at least one
  /// organization (same bar as the Member Directory this is called from).
  Future<void> updateFullName(String userId, String fullName) async {
    if (!await OrganizationService().canManageMembersInAnyOrg()) {
      throw Exception('You do not have permission to edit member names.');
    }

    final trimmed = fullName.trim();
    if (trimmed.isEmpty) {
      throw Exception('Full name cannot be empty');
    }
    await _firestore.doc('users/$userId').update({'fullName': trimmed});
  }

  // Delete user document
  Future<void> deleteUser() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    await _firestore.doc('users/$userId').delete();
  }

  // Check if user document exists
  Future<bool> userExists(String userId) async {
    final doc = await _firestore.doc('users/$userId').get();
    return doc.exists;
  }

  // Save or clear FCM token for the current user
  Future<void> saveFcmToken(String? token) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    await _firestore.doc('users/$userId').update({
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Get multiple users by IDs. contextOrgId scopes the lookup the same way
  // as getUser — caller must be a member of that org. (No callers today;
  // kept consistent with getUser for whenever this is used.)
  Future<List<AppUser>> getUsers(List<String> userIds, String contextOrgId) async {
    if (userIds.isEmpty) return [];

    final orgService = OrganizationService();
    if (!await orgService.isMemberOfOrg(contextOrgId)) {
      throw Exception('You are not a member of this organization.');
    }

    final docs = await Future.wait(
      userIds.map((id) => _firestore.doc('users/$id').get())
    );

    return docs
        .where((doc) => doc.exists)
        .map((doc) => AppUser.fromFirestore(doc))
        .toList();
  }
}
