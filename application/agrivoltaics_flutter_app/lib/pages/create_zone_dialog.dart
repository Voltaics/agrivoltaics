import 'package:flutter/material.dart';
import '../services/zone_service.dart';

class CreateZoneDialog extends StatefulWidget {
  final String orgId;
  final String siteId;

  const CreateZoneDialog({
    super.key,
    required this.orgId,
    required this.siteId,
  });

  @override
  State<CreateZoneDialog> createState() => _CreateZoneDialogState();
}

class _CreateZoneDialogState extends State<CreateZoneDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createZone() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await ZoneService().createZone(
        orgId: widget.orgId,
        siteId: widget.siteId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Zone "${_nameController.text}" created')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating zone: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isDesktop = media.size.width >= 1280;
    final maxDialogWidth = media.size.width * 0.95;
    final preferredWidth = isDesktop ? 560.0 : 460.0;
    final dialogWidth = maxDialogWidth > preferredWidth ? preferredWidth : maxDialogWidth;
    final keyboardInset = media.viewInsets.bottom;
    final availableHeight =
        (media.size.height - keyboardInset).clamp(280.0, media.size.height);
    final contentMaxHeight = availableHeight * (isDesktop ? 0.6 : 0.66);

    return AlertDialog(
      title: const Text('Create Zone'),
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
                children: [
                  TextFormField(
                    controller: _nameController,
                    autofillHints: const [], // disable autofill to prevent unwanted suggestions
                    scrollPadding: const EdgeInsets.only(bottom: 140),
                    decoration: const InputDecoration(
                      labelText: 'Zone Name *',
                      hintText: 'e.g., Zone 1, North Section',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a zone name';
                      }
                      return null;
                    },
                    textCapitalization: TextCapitalization.words,
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    autofillHints: const [], // disable autofill to prevent unwanted suggestions
                    scrollPadding: const EdgeInsets.only(bottom: 140),
                    decoration: const InputDecoration(
                      labelText: 'Description (Optional)',
                      hintText: 'Brief description of this zone',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _createZone,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
