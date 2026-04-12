import 'package:flutter/material.dart';

import '../../responsive/app_viewport.dart';
import 'analytics_models.dart';
import 'widgets/model_not_selected.dart';
import 'widgets/model_selector_card.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';

class AnalyticsDashboardPage extends StatefulWidget {
  const AnalyticsDashboardPage({super.key});

  @override
  State<AnalyticsDashboardPage> createState() => _AnalyticsDashboardPageState();
}

class _AnalyticsDashboardPageState extends State<AnalyticsDashboardPage> {

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final selectedModelId = appState.analyticsSelectedModelId;
    final modelSession = appState.analyticsModelSession;
    final viewportInfo = AppViewportInfo.fromMediaQuery(MediaQuery.of(context));
    final horizontalPadding = viewportInfo.isDesktop ? 16.0 : 12.0;
    final selectedModel = analyticsModelDefinitions
        .where((m) => m.id == selectedModelId)
        .firstOrNull;

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const Text(
              'Analytics',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose a model, enter inputs, and query the model to view outputs.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            ModelSelectorCard(
              models: analyticsModelDefinitions,
              selectedModelId: selectedModelId,
              onChanged: (modelId) {
                context.read<AppState>().setAnalyticsSelectedModelId(modelId);
              },
            ),
            const SizedBox(height: 12),
            if (selectedModel == null)
              const ModelNotSelectedWidget()
            else
              KeyedSubtree(
                key: ValueKey('${selectedModel.id}_$modelSession'),
                child: selectedModel.builder(context),
              ),
          ],
        ),
      ),
    );
  }
}
