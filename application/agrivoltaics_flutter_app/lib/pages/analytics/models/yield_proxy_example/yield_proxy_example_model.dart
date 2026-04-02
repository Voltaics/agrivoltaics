import 'package:flutter/material.dart';

import '../../../../app_colors.dart';

enum _QueryState { idle, loading, success, error }

class YieldProxyExampleModel extends StatefulWidget {
  const YieldProxyExampleModel({super.key});

  @override
  State<YieldProxyExampleModel> createState() => _YieldProxyExampleModelState();
}

class _YieldProxyExampleModelState extends State<YieldProxyExampleModel> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _sunlightHoursController = TextEditingController();
  final TextEditingController _vigorIndexController = TextEditingController();

  _QueryState _state = _QueryState.idle;
  String? _error;
  int? _yieldIndex;
  String? _yieldBand;
  String? _harvestOutlook;

  @override
  void dispose() {
    _sunlightHoursController.dispose();
    _vigorIndexController.dispose();
    super.dispose();
  }

  Future<void> _queryModel() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final sunlightHours = int.parse(_sunlightHoursController.text.trim());
    final vigorIndex = int.parse(_vigorIndexController.text.trim());

    setState(() {
      _state = _QueryState.loading;
      _error = null;
      _yieldIndex = null;
      _yieldBand = null;
      _harvestOutlook = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 1000));

    if (!mounted) {
      return;
    }

    if (sunlightHours == 0 && vigorIndex == 0) {
      setState(() {
        _state = _QueryState.error;
        _error = 'Mock model rejected missing canopy conditions. Update inputs and retry.';
      });
      return;
    }

    final rawIndex = ((sunlightHours * 4) + (vigorIndex * 0.6)).round();
    final normalized = rawIndex.clamp(0, 100);

    String band;
    String outlook;
    if (normalized >= 75) {
      band = 'High';
      outlook = 'Strong harvest potential if weather stays stable.';
    } else if (normalized >= 45) {
      band = 'Moderate';
      outlook = 'Steady projection; continue balanced irrigation and monitoring.';
    } else {
      band = 'Low';
      outlook = 'Below expected trend; inspect stress factors and nutrient plan.';
    }

    setState(() {
      _state = _QueryState.success;
      _yieldIndex = normalized;
      _yieldBand = band;
      _harvestOutlook = outlook;
    });
  }

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
              'Yield Proxy Calculator (example)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Inputs: daily sunlight hours and vine vigor index. Output: normalized yield proxy score.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Input section',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _sunlightHoursController,
                    decoration: const InputDecoration(
                      labelText: 'Sunlight hours (per day)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final parsed = int.tryParse((value ?? '').trim());
                      if (parsed == null) {
                        return 'Enter an integer from 0 to 24';
                      }
                      if (parsed < 0 || parsed > 24) {
                        return 'Value must be between 0 and 24';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _vigorIndexController,
                    decoration: const InputDecoration(
                      labelText: 'Vine vigor index (0-100)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final parsed = int.tryParse((value ?? '').trim());
                      if (parsed == null) {
                        return 'Enter an integer from 0 to 100';
                      }
                      if (parsed < 0 || parsed > 100) {
                        return 'Value must be between 0 and 100';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _state == _QueryState.loading ? null : _queryModel,
                      icon: const Icon(Icons.analytics),
                      label: const Text('Query model'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Demo tip: use 0 and 0 to trigger a mock error state.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Output section',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            _buildOutput(context),
          ],
        ),
      ),
    );
  }

  Widget _buildOutput(BuildContext context) {
    switch (_state) {
      case _QueryState.idle:
        return const Text('Run a query to view model output.');
      case _QueryState.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Running mock inference...'),
            ],
          ),
        );
      case _QueryState.error:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _error ?? 'Unknown error',
            style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
          ),
        );
      case _QueryState.success:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.infoLight,
            border: Border.all(
              color: AppColors.info.withAlpha((0.35 * 255).toInt()),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Model output',
                style: TextStyle(
                  color: AppColors.textOnLight,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Yield proxy index: ${_yieldIndex ?? 0} / 100',
                style: const TextStyle(color: AppColors.textOnLight),
              ),
              const SizedBox(height: 6),
              Text(
                'Yield band: ${_yieldBand ?? 'Unknown'}',
                style: const TextStyle(color: AppColors.textOnLight),
              ),
              const SizedBox(height: 6),
              Text(
                _harvestOutlook ?? '',
                style: const TextStyle(color: AppColors.textOnLight),
              ),
            ],
          ),
        );
    }
  }
}
