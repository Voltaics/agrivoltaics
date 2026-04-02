import 'package:flutter/material.dart';

import '../../../../app_colors.dart';

enum _QueryState { idle, loading, success, error }

class IrrigationNeedExampleModel extends StatefulWidget {
  const IrrigationNeedExampleModel({super.key});

  @override
  State<IrrigationNeedExampleModel> createState() => _IrrigationNeedExampleModelState();
}

class _IrrigationNeedExampleModelState extends State<IrrigationNeedExampleModel> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _soilMoistureController = TextEditingController();
  final TextEditingController _temperatureController = TextEditingController();

  _QueryState _state = _QueryState.idle;
  String? _error;
  String? _recommendation;
  int? _needScore;
  int? _suggestedLitersPerHectare;

  @override
  void dispose() {
    _soilMoistureController.dispose();
    _temperatureController.dispose();
    super.dispose();
  }

  Future<void> _queryModel() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final soilMoisture = int.parse(_soilMoistureController.text.trim());
    final temperature = int.parse(_temperatureController.text.trim());

    setState(() {
      _state = _QueryState.loading;
      _error = null;
      _recommendation = null;
      _needScore = null;
      _suggestedLitersPerHectare = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 900));

    if (!mounted) {
      return;
    }

    if (soilMoisture == 13 && temperature == 37) {
      setState(() {
        _state = _QueryState.error;
        _error = 'Mock inference timeout. Please retry your query.';
      });
      return;
    }

    final rawScore = ((temperature * 2) - soilMoisture).clamp(0, 100);
    final score = rawScore;
    final liters = (score * 12).clamp(120, 1200);

    String recommendation;
    if (score >= 70) {
      recommendation = 'High irrigation need in next 24 hours';
    } else if (score >= 40) {
      recommendation = 'Moderate irrigation need in next 24 hours';
    } else {
      recommendation = 'Low irrigation need; monitor soil moisture trend';
    }

    setState(() {
      _state = _QueryState.success;
      _needScore = score;
      _suggestedLitersPerHectare = liters;
      _recommendation = recommendation;
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
              'Irrigation Need Estimator (example)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Inputs: Soil moisture (%) and ambient temperature (C). Output: irrigation need score and recommendation.',
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
                    controller: _soilMoistureController,
                    decoration: const InputDecoration(
                      labelText: 'Soil moisture (%)',
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
                  TextFormField(
                    controller: _temperatureController,
                    decoration: const InputDecoration(
                      labelText: 'Temperature (C)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final parsed = int.tryParse((value ?? '').trim());
                      if (parsed == null) {
                        return 'Enter an integer from -10 to 60';
                      }
                      if (parsed < -10 || parsed > 60) {
                        return 'Value must be between -10 and 60';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _state == _QueryState.loading ? null : _queryModel,
                      icon: const Icon(Icons.bolt),
                      label: const Text('Query model'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Demo tip: use 13 and 37 to trigger a mock error state.',
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
                'Need score: ${_needScore ?? 0} / 100',
                style: const TextStyle(color: AppColors.textOnLight),
              ),
              const SizedBox(height: 6),
              Text(
                'Suggested irrigation: ${_suggestedLitersPerHectare ?? 0} L/ha',
                style: const TextStyle(color: AppColors.textOnLight),
              ),
              const SizedBox(height: 6),
              Text(
                _recommendation ?? '',
                style: const TextStyle(color: AppColors.textOnLight),
              ),
            ],
          ),
        );
    }
  }
}
