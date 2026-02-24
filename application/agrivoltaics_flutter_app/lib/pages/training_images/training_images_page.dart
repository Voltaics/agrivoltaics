import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/training_image.dart';
import '../../services/image_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Training Images Page
// ─────────────────────────────────────────────────────────────────────────────

class TrainingImagesPage extends StatefulWidget {
  const TrainingImagesPage({super.key});

  @override
  State<TrainingImagesPage> createState() => _TrainingImagesPageState();
}

class _TrainingImagesPageState extends State<TrainingImagesPage> {
  final _imageService = ImageService();

  // Filter state
  List<String> _selectedLabels = [];
  bool _filterModeAnd = true; // true = AND, false = OR

  List<TrainingImage> _applyFilter(List<TrainingImage> all) {
    if (_selectedLabels.isEmpty) return all;
    return all.where((img) {
      if (_filterModeAnd) {
        return _selectedLabels.every((l) => img.labels.contains(l));
      } else {
        return _selectedLabels.any((l) => img.labels.contains(l));
      }
    }).toList();
  }

  void _toggleLabel(String label) {
    setState(() {
      if (_selectedLabels.contains(label)) {
        _selectedLabels.remove(label);
      } else {
        _selectedLabels.add(label);
      }
    });
  }

  Future<void> _showUploadDialog(String orgId) async {
    await showDialog(
      context: context,
      builder: (_) => _UploadImageDialog(
        orgId: orgId,
        imageService: _imageService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final org = appState.selectedOrganization;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title row ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Training Images',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (org != null)
                    ElevatedButton.icon(
                      onPressed: () => _showUploadDialog(org.id),
                      icon: const Icon(Icons.upload),
                      label: const Text('Upload Image'),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Content ────────────────────────────────────────────────
            if (org == null)
              const Expanded(child: _NoOrgWidget())
            else
              Expanded(
                child: StreamBuilder<List<String>>(
                  stream: _imageService.getAvailableLabels(org.id),
                  builder: (context, labelSnap) {
                    final availableLabels = labelSnap.data ?? [];

                    return Column(
                      children: [
                        // Label filter bar
                        if (availableLabels.isNotEmpty)
                          _LabelFilterBar(
                            availableLabels: availableLabels,
                            selectedLabels: _selectedLabels,
                            filterModeAnd: _filterModeAnd,
                            onToggleLabel: _toggleLabel,
                            onToggleMode: () =>
                                setState(() => _filterModeAnd = !_filterModeAnd),
                            onClear: () =>
                                setState(() => _selectedLabels = []),
                          ),

                        // Image grid
                        Expanded(
                          child: StreamBuilder<List<TrainingImage>>(
                            stream: _imageService.getImages(org.id),
                            builder: (context, imgSnap) {
                              if (imgSnap.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }

                              if (imgSnap.hasError) {
                                return Center(
                                  child: Text(
                                      'Error loading images: ${imgSnap.error}'),
                                );
                              }

                              final all = imgSnap.data ?? [];
                              final filtered = _applyFilter(all);

                              if (filtered.isEmpty) {
                                return _EmptyImagesWidget(
                                    hasFilters:
                                        _selectedLabels.isNotEmpty);
                              }

                              return _ImageGrid(
                                images: filtered,
                                orgId: org.id,
                                imageService: _imageService,
                              );
                            },
                          ),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Label Filter Bar
// ─────────────────────────────────────────────────────────────────────────────

class _LabelFilterBar extends StatelessWidget {
  final List<String> availableLabels;
  final List<String> selectedLabels;
  final bool filterModeAnd;
  final void Function(String) onToggleLabel;
  final VoidCallback onToggleMode;
  final VoidCallback onClear;

  const _LabelFilterBar({
    required this.availableLabels,
    required this.selectedLabels,
    required this.filterModeAnd,
    required this.onToggleLabel,
    required this.onToggleMode,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AND/OR toggle + clear button
          Row(
            children: [
              const Text(
                'Filter by label:',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),
              // AND / OR toggle
              GestureDetector(
                onTap: onToggleMode,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha((0.12 * 255).toInt()),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color:
                            AppColors.primary.withAlpha((0.4 * 255).toInt())),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        filterModeAnd ? 'AND' : 'OR',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.swap_horiz,
                          size: 14, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (selectedLabels.isNotEmpty)
                TextButton(
                  onPressed: onClear,
                  child: const Text('Clear filters',
                      style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Label chips
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: availableLabels.map((label) {
              final selected = selectedLabels.contains(label);
              return FilterChip(
                label: Text(label, style: const TextStyle(fontSize: 12)),
                selected: selected,
                onSelected: (_) => onToggleLabel(label),
                selectedColor:
                    AppColors.primary.withAlpha((0.2 * 255).toInt()),
                checkmarkColor: AppColors.primary,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image Grid
// ─────────────────────────────────────────────────────────────────────────────

class _ImageGrid extends StatelessWidget {
  final List<TrainingImage> images;
  final String orgId;
  final ImageService imageService;

  const _ImageGrid({
    required this.images,
    required this.orgId,
    required this.imageService,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    final crossAxisCount = isWide ? 4 : 2;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: images.length,
      itemBuilder: (context, i) {
        return _ImageCard(
          image: images[i],
          orgId: orgId,
          imageService: imageService,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image Card
// ─────────────────────────────────────────────────────────────────────────────

class _ImageCard extends StatelessWidget {
  final TrainingImage image;
  final String orgId;
  final ImageService imageService;

  const _ImageCard({
    required this.image,
    required this.orgId,
    required this.imageService,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 2,
      child: InkWell(
        onTap: () => _showDetail(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumbnail
            Expanded(
              child: image.downloadUrl != null
                  ? Image.network(
                      image.downloadUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            // Labels + file name
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    image.fileName,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (image.labels.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: image.labels
                          .take(3)
                          .map((l) => _LabelBadge(label: l))
                          .toList(),
                    ),
                    if (image.labels.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '+${image.labels.length - 3} more',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.scaffoldBackground,
      child: const Center(
        child: Icon(Icons.image, size: 40, color: AppColors.textMuted),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _ImageDetailDialog(
        image: image,
        orgId: orgId,
        imageService: imageService,
      ),
    );
  }
}

class _LabelBadge extends StatelessWidget {
  final String label;
  const _LabelBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha((0.12 * 255).toInt()),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image Detail Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ImageDetailDialog extends StatelessWidget {
  final TrainingImage image;
  final String orgId;
  final ImageService imageService;

  const _ImageDetailDialog({
    required this.image,
    required this.orgId,
    required this.imageService,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image
            Flexible(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: image.downloadUrl != null
                    ? Image.network(image.downloadUrl!, fit: BoxFit.contain)
                    : Container(
                        height: 200,
                        color: AppColors.scaffoldBackground,
                        child: const Center(
                          child:
                              Icon(Icons.image, size: 60, color: AppColors.textMuted),
                        ),
                      ),
              ),
            ),

            // Metadata
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    image.fileName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (image.labels.isNotEmpty) ...[
                    const Text(
                      'Labels',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: image.labels
                          .map((l) => _LabelBadge(label: l))
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (image.notes != null && image.notes!.isNotEmpty) ...[
                    const Text(
                      'Notes',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(image.notes!,
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    'Uploaded ${_formatDate(image.uploadedAt)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.error),
                    onPressed: () async {
                      final confirmed = await _confirmDelete(context);
                      if (confirmed && context.mounted) {
                        await imageService.deleteImage(
                            orgId, image.id, image.storagePath);
                        Navigator.of(context).pop();
                      }
                    },
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete Image'),
            content: const Text(
                'Are you sure you want to permanently delete this image?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _formatDate(DateTime dt) {
    return DateFormat.yMd().format(dt);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Upload Image Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _UploadImageDialog extends StatefulWidget {
  final String orgId;
  final ImageService imageService;

  const _UploadImageDialog({
    required this.orgId,
    required this.imageService,
  });

  @override
  State<_UploadImageDialog> createState() => _UploadImageDialogState();
}

class _UploadImageDialogState extends State<_UploadImageDialog> {
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

                // Image picker
                GestureDetector(
                  onTap: _isUploading ? null : _pickImage,
                  child: Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: AppColors.scaffoldBackground,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.textMuted.withAlpha(
                              (0.4 * 255).toInt())),
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
                                  style: TextStyle(color: AppColors.textMuted),
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

                // Error
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: AppColors.error, fontSize: 13),
                  ),
                ],

                const SizedBox(height: 24),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _isUploading ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isUploading ? null : _upload,
                      child: _isUploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
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

// ─────────────────────────────────────────────────────────────────────────────
// Empty / placeholder widgets
// ─────────────────────────────────────────────────────────────────────────────

class _NoOrgWidget extends StatelessWidget {
  const _NoOrgWidget();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 60),
          const Icon(Icons.photo_library_outlined,
              size: 80, color: AppColors.textMuted),
          const SizedBox(height: 24),
          const Text(
            'No organization selected',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Select an organization from the sidebar to view and upload training images.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _EmptyImagesWidget extends StatelessWidget {
  final bool hasFilters;
  const _EmptyImagesWidget({required this.hasFilters});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 60),
          const Icon(Icons.photo_library_outlined,
              size: 80, color: AppColors.textMuted),
          const SizedBox(height: 24),
          Text(
            hasFilters
                ? 'No images match the selected filters'
                : 'No training images yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasFilters
                ? 'Try adjusting or clearing the label filters.'
                : 'Upload images using the button above to start building your training dataset.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
