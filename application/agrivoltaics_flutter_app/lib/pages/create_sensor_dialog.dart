import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/sensor_service.dart';

class CreateSensorDialog extends StatefulWidget {
  final String orgId;
  final String siteId;
  final String zoneId;

  const CreateSensorDialog({
    super.key,
    required this.orgId,
    required this.siteId,
    required this.zoneId,
  });

  @override
  State<CreateSensorDialog> createState() => _CreateSensorDialogState();
}

class _CreateSensorDialogState extends State<CreateSensorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String _selectedModel = 'DHT22';
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  bool _isLoading = false;

  final List<String> _sensorModels = [
    'DHT22',
    'VEML7700',
    'DFRobot-Soil',
    'SGP30',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Sensor'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Sensor Name',
                    hintText: 'e.g., DHT22 Weather Sensor',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a sensor name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Model
                DropdownButtonFormField<String>(
                  initialValue: _selectedModel,
                  decoration: const InputDecoration(
                    labelText: 'Sensor Model',
                  ),
                  items: _sensorModels.map((model) {
                    return DropdownMenuItem(
                      value: model,
                      child: Text(model),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedModel = value);
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Location
                const Text(
                  'Location (Optional)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _latController,
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                          hintText: '37.7749',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _lngController,
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                          hintText: '-122.4194',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                const Text(
                  'Note: Sensor will be created as inactive/offline. Update status after installation.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _createSensor,
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

  Future<void> _createSensor() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Parse location if provided
      GeoPoint? location;
      if (_latController.text.isNotEmpty && _lngController.text.isNotEmpty) {
        final lat = double.tryParse(_latController.text);
        final lng = double.tryParse(_lngController.text);
        if (lat != null && lng != null) {
          location = GeoPoint(lat, lng);
        }
      }

      // Get default fields for the sensor model
      final sensorService = SensorService();
      final defaultFields = sensorService.getDefaultFieldsForModel(_selectedModel);

      await sensorService.createSensor(
        orgId: widget.orgId,
        siteId: widget.siteId,
        zoneId: widget.zoneId,
        name: _nameController.text.trim(),
        model: _selectedModel,
        location: location,
        fields: defaultFields,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sensor created successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating sensor: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
