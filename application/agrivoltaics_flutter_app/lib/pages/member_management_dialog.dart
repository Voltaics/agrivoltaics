import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/organization.dart';
import '../models/member.dart';
import '../services/organization_service.dart';
import '../services/user_service.dart';
import 'member_directory/dialogs/edit_full_name_dialog.dart';
import 'member_directory/dialogs/edit_role_dialog.dart';

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
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _fullNameController = TextEditingController();
  String _selectedRole = 'member';
  bool _isAddingMember = false;
  // Defaults to false until the check resolves, so Add/Remove/Edit-role
  // never flash enabled before settling into their real state.
  bool _canManageMembers = false;

  @override
  void initState() {
    super.initState();
    _organizationService.canManageMembers(widget.organization.id).then((canManage) {
      if (mounted) setState(() => _canManageMembers = canManage);
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  Future<void> _addMember() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final fullName = _fullNameController.text.trim();

    setState(() {
      _isAddingMember = true;
    });

    try {
      final outcome = await _organizationService.addMember(
        orgId: widget.organization.id,
        userEmail: email,
        role: _selectedRole,
        fullName: fullName.isEmpty ? null : fullName,
      );

      if (!mounted) return;

      // Clear form
      _emailController.clear();
      _fullNameController.clear();
      setState(() {
        _selectedRole = 'member';
        _isAddingMember = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            outcome == AddMemberOutcome.added
                ? 'Added $email as $_selectedRole'
                : 'Invitation created for $email ($_selectedRole). They will join after first login.',
          ),
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
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final isDesktop = media.size.width >= 1280;
    final dialogWidth = isLandscape
      ? (isDesktop ? 900.0 : media.size.width * 0.9)
        : 600.0;
    final maxDialogWidth = media.size.width * 0.95;
    final effectiveWidth = dialogWidth > maxDialogWidth ? maxDialogWidth : dialogWidth;
    final keyboardInset = media.viewInsets.bottom;
    final availableHeight =
        (media.size.height - keyboardInset).clamp(320.0, media.size.height);
    final dialogMaxHeight = availableHeight * (isDesktop ? 0.84 : 0.9);

    return Dialog(
      child: Container(
        width: effectiveWidth,
        constraints: BoxConstraints(
          maxHeight: dialogMaxHeight,
          minHeight: isLandscape ? 460 : 420,
        ),
        child: Column(
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
            
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final useTwoColumns = isLandscape;

                  if (!useTwoColumns) {
                    return Column(
                      children: [
                        Expanded(child: _buildMemberList()),
                        _buildAddMemberPanel(compact: true),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      SizedBox(
                        width: 300,
                        child: _buildAddMemberPanel(compact: false),
                      ),
                      const VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: AppColors.scaffoldBackground,
                      ),
                      Expanded(
                        flex: 3,
                        child: _buildMemberList(),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberList() {
    return StreamBuilder<List<Member>>(
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
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: members.length,
          itemBuilder: (context, index) {
            final member = members[index];
            return MemberListItem(
              member: member,
              organization: widget.organization,
              canManageMembers: _canManageMembers,
            );
          },
        );
      },
    );
  }

  Widget _buildAddMemberPanel({required bool compact}) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + keyboardInset),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBackground,
        border: compact
            ? const Border(top: BorderSide(color: AppColors.scaffoldBackground))
            : null,
      ),
      child: Form(
        key: _formKey,
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
            TextFormField(
              controller: _emailController,
              autofillHints: const [],
              scrollPadding: const EdgeInsets.only(bottom: 140),
              decoration: const InputDecoration(
                labelText: 'Email Address',
                hintText: 'user@example.com',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
                isDense: true,
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) {
                  return 'Please enter an email address';
                }
                if (!email.contains('@')) {
                  return 'Please enter a valid email address';
                }
                return null;
              },
              enabled: !_isAddingMember,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fullNameController,
              autofillHints: const [],
              scrollPadding: const EdgeInsets.only(bottom: 140),
              decoration: const InputDecoration(
                labelText: 'Full Name (optional)',
                hintText: 'e.g., Jane Smith',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge_outlined),
                isDense: true,
              ),
              enabled: !_isAddingMember,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _addMember(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedRole,
              decoration: const InputDecoration(
                labelText: 'Role',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: roleDropdownItems,
              onChanged: _isAddingMember
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          _selectedRole = value;
                        });
                      }
                    },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_isAddingMember || !_canManageMembers) ? null : _addMember,
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
                label: Text(_isAddingMember ? 'Adding...' : 'Add Member'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
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
  final bool canManageMembers;

  const MemberListItem({
    super.key,
    required this.member,
    required this.organization,
    required this.canManageMembers,
  });

  @override
  State<MemberListItem> createState() => _MemberListItemState();
}

class _MemberListItemState extends State<MemberListItem> {
  bool _isRemoving = false;

  Future<void> _editFullName(String email, String? currentFullName) async {
    await showDialog<bool>(
      context: context,
      builder: (context) => EditFullNameDialog(
        userId: widget.member.userId,
        email: email,
        currentFullName: currentFullName,
      ),
    );

    // The FutureBuilder in build() re-fetches on every rebuild, so a simple
    // setState is enough to pick up the new name after the dialog closes.
    if (mounted) setState(() {});
  }

  Future<void> _editRole(String currentRole, String memberName) async {
    await showDialog<bool>(
      context: context,
      builder: (context) => EditRoleDialog(
        orgId: widget.organization.id,
        userId: widget.member.userId,
        memberName: memberName,
        currentRole: currentRole,
      ),
    );
    // No setState needed here: widget.member comes from the StreamBuilder in
    // _buildMemberList(), which will already re-emit fresh role/permissions
    // once the Firestore write in EditRoleDialog completes.
  }

  Future<void> _removeMember() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: AppColors.warning),
            SizedBox(width: 12),
            Text('Remove Member?'),
          ],
        ),
        content: FutureBuilder(
          future: UserService().getUser(widget.member.userId, widget.organization.id),
          builder: (context, snapshot) {
            final userName = snapshot.data?.resolvedName ?? 'this member';
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
                  Text(userEmail, style: const TextStyle(color: AppColors.textMuted)),
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
      future: userService.getUser(widget.member.userId, widget.organization.id),
      builder: (context, snapshot) {
        final userData = snapshot.data;
        final isPending = snapshot.connectionState != ConnectionState.done;
        final displayName = userData?.resolvedName ??
            (isPending
                ? 'Loading...'
                : (snapshot.hasError ? 'Error loading member' : 'Unknown member'));
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
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              if (!isPending && snapshot.hasError)
                Text(
                  '${snapshot.error}',
                  style: const TextStyle(fontSize: 11, color: AppColors.error),
                ),
              const SizedBox(height: 4),
              _buildRoleBadge(widget.member.role),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCurrentUser)
                const Tooltip(
                  message: 'You cannot change your own role',
                  child: Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                )
              else if (!widget.canManageMembers)
                const Tooltip(
                  message: 'You do not have permission to edit roles',
                  child: Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.admin_panel_settings_outlined, size: 20),
                  color: AppColors.textMuted,
                  onPressed: () => _editRole(widget.member.role, displayName),
                  tooltip: 'Edit role',
                ),
              if (userData != null)
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  color: AppColors.textMuted,
                  onPressed: () => _editFullName(userData.email, userData.fullName),
                  tooltip: 'Edit full name',
                ),
              if (_isRemoving)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (isCurrentUser) // Hide delete button for current user
                const Tooltip(
                  message: 'You cannot remove yourself',
                  child: Icon(
                    Icons.person,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                )
              else if (!widget.canManageMembers)
                const Tooltip(
                  message: 'You do not have permission to remove members',
                  child: Icon(
                    Icons.delete,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  color: AppColors.error,
                  onPressed: _removeMember,
                  tooltip: 'Remove member',
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
}
