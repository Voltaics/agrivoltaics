import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../services/organization_service.dart';
import 'home/home.dart';

class CreateOrganizationDialog extends StatefulWidget {
  final bool autoNavigate;
  
  const CreateOrganizationDialog({
    super.key,
    this.autoNavigate = false,
  });

  @override
  State<CreateOrganizationDialog> createState() => _CreateOrganizationDialogState();
}

class _CreateOrganizationDialogState extends State<CreateOrganizationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _organizationService = OrganizationService();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createOrganization() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final orgId = await _organizationService.createOrganization(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
      );

      if (!mounted) return;

      // Fetch the newly created organization and set it as selected
      final newOrg = await _organizationService.getOrganization(orgId);
      if (!mounted) return;

      if (newOrg != null) {
        final appState = Provider.of<AppState>(context, listen: false);
        appState.setSelectedOrganization(newOrg);
      }

      if (!mounted) return;

      // Close dialog
      Navigator.of(context).pop();
      
      // If autoNavigate is true, navigate to home page
      if (widget.autoNavigate && newOrg != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const HomeState(),
          ),
        );
      }
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Organization "${_nameController.text}" created successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating organization: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isDesktop = media.size.width >= 1280;
    final maxDialogWidth = media.size.width * 0.95;
    final preferredWidth = isDesktop ? 560.0 : 520.0;
    final dialogWidth = maxDialogWidth > preferredWidth ? preferredWidth : maxDialogWidth;
    final keyboardInset = media.viewInsets.bottom;
    final availableHeight =
        (media.size.height - keyboardInset).clamp(280.0, media.size.height);
    final contentMaxHeight = availableHeight * (isDesktop ? 0.58 : 0.72);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.business, color: AppColors.primary),
          SizedBox(width: 12),
          Text('Create Organization'),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: contentMaxHeight),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(bottom: keyboardInset + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              const Text(
                'Create a new organization to manage your sites, sensors, and team members.',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                autofillHints: const [], // disable autofill to prevent unwanted suggestions
                scrollPadding: const EdgeInsets.only(bottom: 140),
                decoration: const InputDecoration(
                  labelText: 'Organization Name',
                  hintText: 'e.g., Vineyard Co.',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an organization name';
                  }
                  if (value.trim().length < 3) {
                    return 'Name must be at least 3 characters';
                  }
                  return null;
                },
                textCapitalization: TextCapitalization.words,
                autofocus: true,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                autofillHints: const [], // disable autofill to prevent unwanted suggestions
                scrollPadding: const EdgeInsets.only(bottom: 140),
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'e.g., Main vineyard operations',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 8),
              const Text(
                'You will be set as the owner with full permissions.',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _createOrganization,
          icon: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.textPrimary),
                  ),
                )
              : const Icon(Icons.add),
          label: Text(_isLoading ? 'Creating...' : 'Create'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
