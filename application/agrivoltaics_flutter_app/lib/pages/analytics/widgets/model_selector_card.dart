import 'package:flutter/material.dart';

import '../analytics_models.dart';

class ModelSelectorCard extends StatelessWidget {
  const ModelSelectorCard({
    super.key,
    required this.models,
    required this.selectedModelId,
    required this.onChanged,
  });

  final List<AnalyticsModelDefinition> models;
  final String? selectedModelId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Model Selector',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a model to load its input and output panel.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedModelId,
              decoration: const InputDecoration(
                labelText: 'Analytics model',
                border: OutlineInputBorder(),
              ),
              items: models
                  .map(
                    (model) => DropdownMenuItem<String>(
                      value: model.id,
                      child: Text(model.displayName),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
