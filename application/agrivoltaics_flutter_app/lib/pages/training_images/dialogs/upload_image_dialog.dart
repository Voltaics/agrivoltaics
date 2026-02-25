import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/image_service.dart';

/// Dialog that lets the user pick an image from the gallery, assign labels,
/// add optional notes, and upload it to Firebase Storage + Firestore.
class UploadImageDialog extends StatefulWidget {
  final String orgId;
  final ImageService imageService;

  const UploadImageDialog({
    super.key,
    required this.orgId,
    required this.imageService,
  });

  @override
  State<UploadImageDialog> createState() => _UploadImageDialogState();
}

class _UploadImageDialogState extends State<UploadImageDialog> {
  final _notesController = TextEditingController();
  final _labelController = TextEditingController();

  XFile? _pickedFile;
  List<String> _labels = [];
  bool _isUploading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _notesController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      setState(() {
        _pickedFile = file;
        _errorMessage = null;
      });
    }
  }

  void _addLabel() {
    final label = _labelController.text.trim();
    if (label.isNotEmpty && !_labels.contains(label)) {
      setState(() {
        _labels.add(label);
        _labelController.clear();
      });
    }
  }

  void _removeLabel(String label) {
    setState(() => _labels.remove(label));
  }

  Future<void> _upload() async {
    if (_pickedFile == null) {
      setState(() => _errorMessage = 'Please select an image first.');
      return;
    }

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      final bytes = await _pickedFile!.readAsBytes();
      await widget.imageService.uploadImage(
        orgId: widget.orgId,
        bytes: bytes,
        fileName: _pickedFile!.name,
        labels: _labels,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _isUploading = false;
        _errorMessage = 'Upload failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                const Text(
                  'Upload Training Image',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),

                // Image picker area
                GestureDetector(
                  onTap: _isUploading ? null : _pickImage,
                  child: Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: AppColors.scaffoldBackground,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.textMuted
                            .withAlpha((0.4 * 255).toInt()),
                      ),
                    ),
                    child: _pickedFile == null
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_photo_alternate,
                                    size: 40, color: AppColors.textMuted),
                                SizedBox(height: 8),
                                Text(
                                  'Tap to select an image',
                                  style:
                                      TextStyle(color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          )
                        : Center(
                            child: Text(
                              _pickedFile!.name,
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 20),

                // Labels
                const Text(
                  'Labels',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _labelController,
                        decoration: const InputDecoration(
                          hintText: 'e.g. healthy, disease, powdery_mildew',
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        onSubmitted: (_) => _addLabel(),
                        enabled: !_isUploading,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _isUploading ? null : _addLabel,
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'Add label',
                    ),
                  ],
                ),
                if (_labels.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _labels
                        .map((l) => Chip(
                              label: Text(l,
                                  style: const TextStyle(fontSize: 12)),
                              onDeleted: _isUploading
                                  ? null
                                  : () => _removeLabel(l),
                              deleteIcon: const Icon(Icons.close, size: 14),
                            ))
                        .toList(),
                  ),
                ],

                const SizedBox(height: 16),

                // Notes
                const Text(
                  'Notes (optional)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Any additional notes about the image',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  enabled: !_isUploading,
                ),

                // Error message
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 13),
                  ),
                ],

                const SizedBox(height: 24),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isUploading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isUploading ? null : _upload,
                      child: _isUploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Upload'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
