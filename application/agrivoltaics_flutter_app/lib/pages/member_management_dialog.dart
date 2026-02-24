import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/organization.dart';
import '../models/member.dart';
import '../services/organization_service.dart';
import '../services/user_service.dart';

class MemberManagementDialog extends StatefulWidget {
  final Organization organization;

  const MemberManagementDialog({
    super.key,
    required this.organization,
  });

  @override
  State<MemberManagementDialog> createState() => _MemberManagementDialogState();
}

class _MemberManagementDialogState extends State<MemberManagementDialog> {
  final _organizationService = OrganizationService();
  final _emailController = TextEditingController();
  String _selectedRole = 'member';
  bool _isAddingMember = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _addMember() async {
    final email = _emailController.text.trim();
    
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an email address'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    // Basic email validation
    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() {
      _isAddingMember = true;
    });

    try {
      await _organizationService.addMember(
        orgId: widget.organization.id,
        userEmail: email,
        role: _selectedRole,
      );

      if (!mounted) return;

      // Clear form
      _emailController.clear();
      setState(() {
        _selectedRole = 'member';
        _isAddingMember = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $email as $_selectedRole'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isAddingMember = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding member: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people, color: AppColors.textPrimary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Manage Members',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.organization.name,
                          style: TextStyle(
                            color: AppColors.textPrimary.withAlpha((0.9 * 255).toInt()),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            
            // Member List
            Flexible(
              child: StreamBuilder<List<Member>>(
                stream: _organizationService.getOrganizationMembers(widget.organization.id),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Error loading members: ${snapshot.error}',
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                    );
                  }

                  final members = snapshot.data ?? [];

                  if (members.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No members found'),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final member = members[index];
                      return MemberListItem(
                        member: member,
                        organization: widget.organization,
                      );
                    },
                  );
                },
              ),
            ),

            // Footer with Add Member button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.scaffoldBackground,
                border: Border(
                  top: BorderSide(color: AppColors.scaffoldBackground),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Add New Member',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Email field - full width
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      hintText: 'user@example.com',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                      isDense: true,
                    ),
                    enabled: !_isAddingMember,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addMember(),
                  ),
                  const SizedBox(height: 12),
                  // Role selector and Add button - side by side
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedRole,
                          decoration: const InputDecoration(
                            labelText: 'Role',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'owner', child: Text('Owner')),
                            DropdownMenuItem(value: 'admin', child: Text('Admin')),
                            DropdownMenuItem(value: 'member', child: Text('Member')),
                            DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                          ],
                          onChanged: _isAddingMember
                              ? null
                              : (value) {
                                  if (value != null) {
                                    _selectedRole = value;
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _isAddingMember ? null : _addMember,
                        icon: _isAddingMember
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.textPrimary),
                              ),
                            )
                            : const Icon(Icons.add),
                        label: Text(_isAddingMember ? 'Adding...' : 'Add'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.textPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MemberListItem extends StatefulWidget {
  final Member member;
  final Organization organization;

  const MemberListItem({
    super.key,
    required this.member,
    required this.organization,
  });

  @override
  State<MemberListItem> createState() => _MemberListItemState();
}

class _MemberListItemState extends State<MemberListItem> {
  bool _isRemoving = false;

  Future<void> _removeMember() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            const Icon(Icons.warning, color: AppColors.warning),
            SizedBox(width: 12),
            Text('Remove Member?'),
          ],
        ),
        content: FutureBuilder(
          future: UserService().getUser(widget.member.userId),
          builder: (context, snapshot) {
            final userName = snapshot.data?.displayName ?? 'this member';
            final userEmail = snapshot.data?.email ?? '';
            
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to remove $userName?',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (userEmail.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(userEmail, style: TextStyle(color: AppColors.textMuted)),
                ],
                const SizedBox(height: 12),
                const Text(
                  'They will lose access to this organization and all its data.',
                  style: TextStyle(color: AppColors.error),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.textPrimary,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isRemoving = true;
    });

    try {
      await OrganizationService().removeMember(
        orgId: widget.organization.id,
        userId: widget.member.userId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Member removed successfully'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isRemoving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userService = UserService();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isCurrentUser = widget.member.userId == currentUserId;

    return FutureBuilder(
      future: userService.getUser(widget.member.userId),
      builder: (context, snapshot) {
        final userData = snapshot.data;
        final displayName = userData?.displayName ?? 'Loading...';
        final email = userData?.email ?? '';

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.primary,
            child: Text(
              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            displayName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (email.isNotEmpty)
                Text(
                  email,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _buildRoleBadge(widget.member.role),
                  const SizedBox(width: 8),
                  _buildPermissionChips(widget.member.permissions),
                ],
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // TODO: Add role dropdown
              if (_isRemoving)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (!isCurrentUser) // Hide delete button for current user
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  color: AppColors.error,
                  onPressed: _removeMember,
                  tooltip: 'Remove member',
                )
              else
                Tooltip(
                  message: 'You cannot remove yourself',
                  child: Icon(
                    Icons.person,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRoleBadge(String role) {
    Color badgeColor;
    switch (role) {
      case 'owner':
        badgeColor = AppColors.primaryLight;
        break;
      case 'admin':
        badgeColor = AppColors.primary;
        break;
      case 'member':
        badgeColor = AppColors.success;
        break;
      case 'viewer':
        badgeColor = AppColors.textMuted;
        break;
      default:
        badgeColor = AppColors.textMuted;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withAlpha((0.1 * 255).toInt()),
        border: Border.all(color: badgeColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        role.toUpperCase(),
        style: TextStyle(
          color: badgeColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildPermissionChips(MemberPermissions permissions) {
    final activePermissions = <String>[];
    if (permissions.canManageMembers) activePermissions.add('Members');
    if (permissions.canManageSites) activePermissions.add('Sites');
    if (permissions.canManageSensors) activePermissions.add('Sensors');

    if (activePermissions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Expanded(
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: activePermissions.map((perm) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.info.withAlpha((0.1 * 255).toInt()),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              perm,
              style: const TextStyle(
                color: AppColors.info,
                fontSize: 9,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
