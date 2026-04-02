import 'package:flutter/material.dart';

import 'models/irrigation_need_example/irrigation_need_example_model.dart';
import 'models/yield_proxy_example/yield_proxy_example_model.dart';

class AnalyticsModelDefinition {
  const AnalyticsModelDefinition({
    required this.id,
    required this.displayName,
    required this.builder,
  });

  final String id;
  final String displayName;
  final WidgetBuilder builder;
}

final List<AnalyticsModelDefinition> analyticsModelDefinitions = [
  // Template extension point:
  // 1) Create a new model widget under analytics/models/<model_name>/.
  // 2) Add an entry here with a unique id, display name, and widget builder.
  AnalyticsModelDefinition(
    id: 'irrigation_need_example',
    displayName: 'Irrigation Need Estimator (example)',
    builder: (_) => const IrrigationNeedExampleModel(),
  ),
  AnalyticsModelDefinition(
    id: 'yield_proxy_example',
    displayName: 'Yield Proxy Calculator (example)',
    builder: (_) => const YieldProxyExampleModel(),
  ),
];
