import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/training_image.dart';
import '../../services/image_service.dart';
import 'dialogs/upload_image_dialog.dart';
import 'widgets/empty_images_widget.dart';
import 'widgets/image_grid.dart';
import 'widgets/label_filter_bar.dart';
import 'widgets/no_org_widget.dart';

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
      builder: (_) => UploadImageDialog(
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
            // Title row
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

            // Content
            if (org == null)
              const Expanded(child: NoOrgWidget())
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
                          LabelFilterBar(
                            availableLabels: availableLabels,
                            selectedLabels: _selectedLabels,
                            filterModeAnd: _filterModeAnd,
                            onToggleLabel: _toggleLabel,
                            onToggleMode: () => setState(
                                () => _filterModeAnd = !_filterModeAnd),
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
                                return EmptyImagesWidget(
                                    hasFilters: _selectedLabels.isNotEmpty);
                              }

                              return ImageGrid(
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
