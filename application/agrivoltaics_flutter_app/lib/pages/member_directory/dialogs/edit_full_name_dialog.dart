import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import '../../../services/user_service.dart';

/// Reusable "set/edit full name" dialog, opened both from the per-org
/// Manage Members list and from the cross-org Member Directory page. Always
/// writes to users/{userId}.fullName via UserService.updateFullName, so
/// there is exactly one place this data lives regardless of where it's
/// edited from.
class EditFullNameDialog extends StatefulWidget {
  final String userId;
  final String email;
  final String? currentFullName;

  const EditFullNameDialog({
    super.key,
    required this.userId,
    required this.email,
    this.currentFullName,
  });

  @override
  State<EditFullNameDialog> createState() => _EditFullNameDialogState();
}

class _EditFullNameDialogState extends State<EditFullNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final _userService = UserService();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentFullName ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      await _userService.updateFullName(widget.userId, _nameController.text.trim());

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() => _isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating name: $e'),
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
          Icon(Icons.badge, color: AppColors.primary),
          SizedBox(width: 12),
          Text('Edit Full Name'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.email,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                autofillHints: const [],
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  hintText: 'e.g., Jane Smith',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
                textCapitalization: TextCapitalization.words,
                autofocus: true,
                enabled: !_isSaving,
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 8),
              const Text(
                'This overrides the name shown from their Google account, '
                'everywhere it appears in the app.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _isSaving ? null : _save,
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
