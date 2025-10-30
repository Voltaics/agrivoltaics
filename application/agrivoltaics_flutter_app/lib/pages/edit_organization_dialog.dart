import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/organization.dart';
import '../services/organization_service.dart';
import 'organization_selection.dart';

class EditOrganizationDialog extends StatefulWidget {
  final Organization organization;

  const EditOrganizationDialog({
    super.key,
    required this.organization,
  });

  @override
  State<EditOrganizationDialog> createState() => _EditOrganizationDialogState();
}

class _EditOrganizationDialogState extends State<EditOrganizationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  final _organizationService = OrganizationService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.organization.name);
    _descriptionController = TextEditingController(text: widget.organization.description);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _updateOrganization() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final orgName = _nameController.text.trim();
      
      await _organizationService.updateOrganization(
        widget.organization.id,
        {
          'name': orgName,
          'description': _descriptionController.text.trim(),
        },
      );

      if (!mounted) return;

      // Update the selected organization in AppState if this is the current org
      final appState = Provider.of<AppState>(context, listen: false);
      if (appState.selectedOrganization?.id == widget.organization.id) {
        final updatedOrg = Organization(
          id: widget.organization.id,
          name: orgName,
          description: _descriptionController.text.trim(),
          logoUrl: widget.organization.logoUrl,
          createdAt: widget.organization.createdAt,
          updatedAt: DateTime.now(),
          createdBy: widget.organization.createdBy,
        );
        appState.setSelectedOrganization(updatedOrg);
      }

      if (!mounted) return;

      // Close dialog
      Navigator.of(context).pop();

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Organization updated successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating organization: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteOrganization() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 12),
            Text('Delete Organization?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "${widget.organization.name}"?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'This action cannot be undone. All sites, sensors, and data associated with this organization will be permanently deleted.',
              style: TextStyle(color: Colors.red),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _organizationService.deleteOrganization(widget.organization.id);

      if (!mounted) return;

      // Check if this was the selected organization
      final appState = Provider.of<AppState>(context, listen: false);
      final wasSelectedOrg = appState.selectedOrganization?.id == widget.organization.id;

      if (!mounted) return;

      // Close all dialogs and menus
      Navigator.of(context).popUntil((route) => route.isFirst);

      // If the deleted org was selected, navigate to organization selection
      if (wasSelectedOrg) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const OrganizationSelectionPage(),
          ),
        );
        
        // Show message after navigation
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Organization deleted. Please select another organization.'),
              backgroundColor: Colors.orange,
            ),
          );
        });
      } else {
        // Just show success message if it wasn't the active org
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Organization deleted successfully'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting organization: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _manageMembers() {
    // TODO: Implement member management
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Member management coming soon!'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.edit, color: Color(0xFF2D53DA)),
          SizedBox(width: 12),
          Text('Edit Organization'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Organization Name',
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
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              // Manage Members Button
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _manageMembers,
                icon: const Icon(Icons.people),
                label: const Text('Manage Members'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2D53DA),
                ),
              ),
              const SizedBox(height: 12),
              // Delete Button
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _deleteOrganization,
                icon: const Icon(Icons.delete),
                label: const Text('Delete Organization'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _updateOrganization,
          icon: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.save),
          label: Text(_isLoading ? 'Saving...' : 'Save'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2D53DA),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
