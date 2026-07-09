import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import '../../../models/member.dart';
import '../../../services/organization_service.dart';

/// Edits a member's role within one specific organization, via the
/// already-guarded OrganizationService.updateMemberRole (rejects
/// self-role-changes and demoting the last owner). Scoped to a single org's
/// Manage Members list rather than the cross-org Member Directory, since
/// role is a per-organization attribute (a person can hold different roles
/// in different orgs), unlike full name.
class EditRoleDialog extends StatefulWidget {
  final String orgId;
  final String userId;
  final String memberName;
  final String currentRole;

  const EditRoleDialog({
    super.key,
    required this.orgId,
    required this.userId,
    required this.memberName,
    required this.currentRole,
  });

  @override
  State<EditRoleDialog> createState() => _EditRoleDialogState();
}

class _EditRoleDialogState extends State<EditRoleDialog> {
  final _organizationService = OrganizationService();
  late String _selectedRole;
  bool _isSaving = false;
  // Both default to false until the checks resolve, so Save never flashes
  // enabled before settling into its real state.
  bool _canManageMembers = false;
  bool _isOwner = false;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.currentRole;
    Future.wait([
      _organizationService.canManageMembers(widget.orgId),
      _organizationService.isOwnerOfOrg(widget.orgId),
    ]).then((results) {
      if (mounted) {
        setState(() {
          _canManageMembers = results[0];
          _isOwner = results[1];
        });
      }
    });
  }

  // Granting or revoking owner status requires being an owner; other role
  // changes only require canManageMembers — mirrors the server-side rule in
  // OrganizationService.updateMemberRole.
  bool get _touchesOwnerStatus =>
      widget.currentRole == 'owner' || _selectedRole == 'owner';

  bool get _canSave =>
      _canManageMembers && (!_touchesOwnerStatus || _isOwner);

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      await _organizationService.updateMemberRole(
        orgId: widget.orgId,
        userId: widget.userId,
        newRole: _selectedRole,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() => _isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating role: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.admin_panel_settings_outlined, color: AppColors.primary),
          SizedBox(width: 12),
          Text('Edit Role'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.memberName,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedRole,
              decoration: const InputDecoration(
                labelText: 'Role',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: roleDropdownItems,
              onChanged: _isSaving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _selectedRole = value);
                    },
            ),
            const SizedBox(height: 8),
            const Text(
              "The last remaining owner of an organization can't be demoted.",
              style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontStyle: FontStyle.italic),
            ),
            if (_touchesOwnerStatus && !_isOwner) ...[
              const SizedBox(height: 8),
              const Text(
                'Only an owner can grant or revoke owner status.',
                style: TextStyle(color: AppColors.error, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: (_isSaving || !_canSave) ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.textPrimary),
                  ),
                )
              : const Icon(Icons.save),
          label: Text(_isSaving ? 'Saving...' : 'Save'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
