import 'package:cloud_firestore/cloud_firestore.dart';

class Member {
  final String userId; // Document ID from members subcollection
  final String role;
  final MemberPermissions permissions;
  final DateTime joinedAt;
  final String? invitedBy;
  final DateTime? lastActive;

  Member({
    required this.userId,
    required this.role,
    required this.permissions,
    required this.joinedAt,
    this.invitedBy,
    this.lastActive,
  });

  // Convert from Firestore document
  factory Member.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Member(
      userId: doc.id,
      role: data['role'] ?? 'viewer',
      permissions: MemberPermissions.fromMap(data['permissions'] ?? {}),
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      invitedBy: data['invitedBy'],
      lastActive: (data['lastActive'] as Timestamp?)?.toDate(),
    );
  }

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'role': role,
      'permissions': permissions.toMap(),
      'joinedAt': Timestamp.fromDate(joinedAt),
      'invitedBy': invitedBy,
      'lastActive': lastActive != null ? Timestamp.fromDate(lastActive!) : null,
    };
  }

  // Helper to get role display name
  String get roleDisplayName {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'admin':
        return 'Admin';
      case 'member':
        return 'Member';
      case 'viewer':
        return 'Viewer';
      default:
        return role;
    }
  }

  // Helper to check if this is an owner
  bool get isOwner => role == 'owner';
}

class MemberPermissions {
  final bool canManageMembers;
  final bool canManageSites;
  final bool canManageSensors;

  MemberPermissions({
    this.canManageMembers = false,
    this.canManageSites = false,
    this.canManageSensors = false,
  });

  factory MemberPermissions.fromMap(Map<String, dynamic> map) {
    return MemberPermissions(
      canManageMembers: map['canManageMembers'] ?? false,
      canManageSites: map['canManageSites'] ?? false,
      canManageSensors: map['canManageSensors'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'canManageMembers': canManageMembers,
      'canManageSites': canManageSites,
      'canManageSensors': canManageSensors,
    };
  }

  // Predefined permission sets for roles
  static MemberPermissions forRole(String role) {
    switch (role) {
      case 'owner':
        return MemberPermissions(
          canManageMembers: true,
          canManageSites: true,
          canManageSensors: true,
        );
      case 'admin':
        return MemberPermissions(
          canManageMembers: true,
          canManageSites: true,
          canManageSensors: true,
        );
      case 'member':
        return MemberPermissions(
          canManageMembers: false,
          canManageSites: true,
          canManageSensors: true,
        );
      case 'viewer':
        return MemberPermissions(
          canManageMembers: false,
          canManageSites: false,
          canManageSensors: false,
        );
      default:
        return MemberPermissions();
    }
  }
}
