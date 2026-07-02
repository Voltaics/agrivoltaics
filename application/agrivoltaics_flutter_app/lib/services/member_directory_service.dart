import 'package:cloud_firestore/cloud_firestore.dart';
import '../app_constants.dart';
import '../models/authorized_member_summary.dart';
import 'organization_service.dart';

/// Builds the cross-org Member Directory: one row per email in
/// AUTHORIZED_EMAILS, merged with sign-in state (users/{uid}), active org
/// memberships, and outstanding invites.
///
/// This is a one-shot load (with manual refresh) rather than a live stream —
/// the directory is an infrequently-used admin view, and streaming a merge
/// across a static email list plus two collectionGroup queries per person
/// would add real complexity for no meaningful benefit at this scale.
class MemberDirectoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final OrganizationService _organizationService = OrganizationService();

  Future<bool> canAccessDirectory() {
    return _organizationService.canManageMembersInAnyOrg();
  }

  Future<List<AuthorizedMemberSummary>> loadDirectory() async {
    final emails = AppConstants.authorizedEmails
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    final summaries = await Future.wait(emails.map(_loadSummaryForEmail));
    summaries.sort((a, b) => a.resolvedName.toLowerCase().compareTo(b.resolvedName.toLowerCase()));
    return summaries;
  }

  Future<AuthorizedMemberSummary> _loadSummaryForEmail(String normalizedEmail) async {
    final userQuery = await _firestore
        .collection('users')
        .where('email', isEqualTo: normalizedEmail)
        .limit(1)
        .get();

    String? uid;
    String? displayName;
    String? fullName;
    DateTime? lastLogin;

    if (userQuery.docs.isNotEmpty) {
      final doc = userQuery.docs.first;
      final data = doc.data();
      uid = doc.id;
      displayName = data['displayName'] as String?;
      fullName = data['fullName'] as String?;
      lastLogin = (data['lastLogin'] as Timestamp?)?.toDate();
    }

    final organizations = await _organizationService.getOrganizationsForEmail(normalizedEmail);
    final pendingInvites = await _organizationService.getPendingInvitesForEmail(normalizedEmail);

    return AuthorizedMemberSummary(
      email: normalizedEmail,
      uid: uid,
      displayName: displayName,
      fullName: fullName,
      lastLogin: lastLogin,
      organizations: organizations,
      pendingInvites: pendingInvites,
    );
  }
}
