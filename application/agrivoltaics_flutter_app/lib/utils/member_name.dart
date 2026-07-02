/// Single place that decides what name to show for a person: an admin-set
/// full name override takes priority, falling back to Google's display name,
/// and finally to the email address if neither is available.
String resolveMemberDisplayName({
  String? fullName,
  String? displayName,
  required String email,
}) {
  final trimmedFullName = fullName?.trim() ?? '';
  if (trimmedFullName.isNotEmpty) return trimmedFullName;

  final trimmedDisplayName = displayName?.trim() ?? '';
  if (trimmedDisplayName.isNotEmpty) return trimmedDisplayName;

  return email;
}
