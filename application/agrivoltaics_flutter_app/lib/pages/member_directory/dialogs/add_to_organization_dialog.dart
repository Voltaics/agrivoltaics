import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import '../../../models/authorized_member_summary.dart';
import '../../../models/organization.dart';
import '../../../services/organization_service.dart';

/// Adds an authorized-but-not-yet-a-member person to one of the current
/// user's manageable organizations, optionally setting their full name at
/// the same time. Reuses OrganizationService.addMember exactly as the
/// per-org Manage Members dialog does, so both surfaces share one code path.
class AddToOrganizationDialog extends StatefulWidget {
  final AuthorizedMemberSummary member;

  const AddToOrganizationDialog({super.key, required this.member});

  @override
  State<AddToOrganizationDialog> createState() => _AddToOrganizationDialogState();
}

class _AddToOrganizationDialogState extends State<AddToOrganizationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _organizationService = OrganizationService();
  late final TextEditingController _nameController;

  Future<List<Organization>>? _organizationsFuture;
  String? _selectedOrgId;
  String _selectedRole = 'member';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.member.fullName ?? '');
    _organizationsFuture = _organizationService.getManageableOrganizations();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit(List<Organization> organizations) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedOrgId == null) return;

    setState(() => _isSaving = true);

    final org = organizations.firstWhere((o) => o.id == _selectedOrgId);
    final name = _nameController.text.trim();

    try {
      await _organizationService.addMember(
        orgId: org.id,
        userEmail: widget.member.email,
        role: _selectedRole,
        fullName: name.isEmpty ? null : name,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() => _isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding to organization: $e'),
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
          Icon(Icons.group_add, color: AppColors.primary),
          SizedBox(width: 12),
          Text('Add to Organization'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: FutureBuilder<List<Organization>>(
          future: _organizationsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final allOrgs = snapshot.data ?? [];
            final memberOrgIds = widget.member.organizations.map((o) => o.orgId).toSet();
            final availableOrgs = allOrgs.where((o) => !memberOrgIds.contains(o.id)).toList();

            if (availableOrgs.isEmpty) {
              return const Text(
                'You don\'t manage any organization this person isn\'t already a member of.',
              );
            }

            _selectedOrgId ??= availableOrgs.first.id;

            return Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.member.email,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedOrgId,
                    decoration: const InputDecoration(
                      labelText: 'Organization',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: availableOrgs
                        .map((o) => DropdownMenuItem(value: o.id, child: Text(o.name)))
                        .toList(),
                    onChanged: _isSaving ? null : (value) => setState(() => _selectedOrgId = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
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
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value != null) setState(() => _selectedRole = value);
                          },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    autofillHints: const [],
                    decoration: const InputDecoration(
                      labelText: 'Full Name (optional)',
                      hintText: 'e.g., Jane Smith',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.badge_outlined),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.words,
                    enabled: !_isSaving,
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FutureBuilder<List<Organization>>(
          future: _organizationsFuture,
          builder: (context, snapshot) {
            final orgs = snapshot.data ?? [];
            final canSubmit = orgs.isNotEmpty &&
                orgs.any((o) => !widget.member.organizations.map((m) => m.orgId).contains(o.id));

            return ElevatedButton.icon(
              onPressed: (_isSaving || !canSubmit) ? null : () => _submit(orgs),
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.textPrimary),
                      ),
                    )
                  : const Icon(Icons.add),
              label: Text(_isSaving ? 'Adding...' : 'Add'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textPrimary,
              ),
            );
          },
        ),
      ],
    );
  }
}
