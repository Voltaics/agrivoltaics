import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/member_name.dart';

class AppUser {
  final String uid;
  final String email;
  final String displayName;
  final DateTime createdAt;
  final DateTime lastLogin;

  /// Firebase Cloud Messaging token for push notifications.
  /// Null when the user has not granted notification permission on any device.
  final String? fcmToken;

  /// Admin-set override shown instead of [displayName] wherever this person's
  /// name is rendered. Never touched by the Google sign-in sync — only by
  /// explicit edits (see UserService.updateFullName).
  final String? fullName;

  AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.createdAt,
    required this.lastLogin,
    this.fcmToken,
    this.fullName,
  });

  // Convert from Firestore document
  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUser(
      uid: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastLogin: (data['lastLogin'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fcmToken: data['fcmToken'] as String?,
      fullName: data['fullName'] as String?,
    );
  }

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLogin': Timestamp.fromDate(lastLogin),
      if (fullName != null) 'fullName': fullName,
    };
  }

  /// Resolved name to show in the UI: full name override, else Google's
  /// display name, else the email as a last resort.
  String get resolvedName => resolveMemberDisplayName(
        fullName: fullName,
        displayName: displayName,
        email: email,
      );

  AppUser copyWith({
    String? uid,
    String? email,
    String? displayName,
    DateTime? createdAt,
    DateTime? lastLogin,
    String? fcmToken,
    String? fullName,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
      fcmToken: fcmToken ?? this.fcmToken,
      fullName: fullName ?? this.fullName,
    );
  }
}
