import '../services/organization_service.dart';
import '../utils/member_name.dart';

/// One row of the Member Directory: a single authorized email (from
/// AUTHORIZED_EMAILS) cross-referenced with whether they've signed in and
/// which organization(s) they belong to or have a pending invite for.
///
/// This is the "single source of truth" roster the per-org Manage Members
/// dialog intentionally does not try to replicate — a person can belong to
/// zero, one, or many organizations, so membership status only makes sense
/// viewed across all of them at once.
class AuthorizedMemberSummary {
  final String email;
  final String? uid;
  final String? displayName;
  final String? fullName;
  final DateTime? lastLogin;
  final List<MemberOrganizationRef> organizations;
  final List<MemberOrganizationRef> pendingInvites;

  AuthorizedMemberSummary({
    required this.email,
    this.uid,
    this.displayName,
    this.fullName,
    this.lastLogin,
    this.organizations = const [],
    this.pendingInvites = const [],
  });

  bool get hasSignedIn => uid != null;

  /// A name can only be set once a person has signed in (uid exists) or has
  /// at least one pending invite to stash it on (see OrganizationService
  /// .addMember + UserService._acceptPendingInvites) — this flags that case.
  bool get canEditName => hasSignedIn;

  String get resolvedName => resolveMemberDisplayName(
        fullName: fullName,
        displayName: displayName,
        email: email,
      );

  String get statusSummary {
    if (!hasSignedIn) return 'Not signed in yet';
    if (organizations.isNotEmpty) {
      final parts = organizations.map((o) => '${o.orgName} (${o.role})').join(', ');
      return 'Member of: $parts';
    }
    return 'Signed in — no organizations';
  }
}
