import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/sensor.dart';
import '../services/sensor_service.dart';

class EditSensorDialog extends StatefulWidget {
  final Sensor sensor;
  final String orgId;
  final String siteId;
  final String zoneId;

  const EditSensorDialog({
    super.key,
    required this.sensor,
    required this.orgId,
    required this.siteId,
    required this.zoneId,
  });

  @override
  State<EditSensorDialog> createState() => _EditSensorDialogState();
}

class _EditSensorDialogState extends State<EditSensorDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late String _selectedModel;
  late TextEditingController _latController;
  late TextEditingController _lngController;
  late bool _isOnline;
  late String _status;
  bool _isLoading = false;

  final List<String> _sensorModels = [
    'DHT22',
    'VEML7700',
    'DFRobot-Soil',
    'SGP30',
  ];

  final List<String> _statusOptions = [
    'active',
    'inactive',
    'maintenance',
    'error',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.sensor.name);
    _selectedModel = widget.sensor.model;
    _latController = TextEditingController(
      text: widget.sensor.location?.latitude.toString() ?? '',
    );
    _lngController = TextEditingController(
      text: widget.sensor.location?.longitude.toString() ?? '',
    );
    _isOnline = widget.sensor.isOnline;
    _status = widget.sensor.status;
  }

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
      title: Row(
        children: [
          const Text('Edit Sensor'),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: _isLoading ? null : _confirmDelete,
            tooltip: 'Delete sensor',
          ),
        ],
      ),
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
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a sensor name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Model (disabled, can't change model)
                DropdownButtonFormField<String>(
                  initialValue: _selectedModel,
                  decoration: const InputDecoration(
                    labelText: 'Sensor Model',
                    helperText: 'Model cannot be changed',
                  ),
                  items: _sensorModels.map((model) {
                    return DropdownMenuItem(
                      value: model,
                      child: Text(model),
                    );
                  }).toList(),
                  onChanged: null, // Disabled
                ),
                const SizedBox(height: 16),

                // Location
                const Text(
                  'Location',
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

                // Status
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                  ),
                  items: _statusOptions.map((status) {
                    return DropdownMenuItem(
                      value: status,
                      child: Text(status[0].toUpperCase() + status.substring(1)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _status = value);
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Online status
                SwitchListTile(
                  title: const Text('Online'),
                  value: _isOnline,
                  onChanged: (value) {
                    setState(() => _isOnline = value);
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),

                // Sensor fields info
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Sensor Fields',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...widget.sensor.fields.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Text(
                          '${entry.value.currentValue?.toStringAsFixed(1) ?? '--'} ${entry.value.unit}',
                        ),
                      ],
                    ),
                  );
                }),
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
          onPressed: _isLoading ? null : _updateSensor,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _updateSensor() async {
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

      final sensorService = SensorService();

      // Update name if changed
      if (_nameController.text.trim() != widget.sensor.name) {
        await sensorService.updateSensor(
          widget.orgId,
          widget.siteId,
          widget.zoneId,
          widget.sensor.id,
          {'name': _nameController.text.trim()},
        );
      }

      // Update location if changed
      if (location != widget.sensor.location) {
        await sensorService.updateSensor(
          widget.orgId,
          widget.siteId,
          widget.zoneId,
          widget.sensor.id,
          {'location': location},
        );
      }

      // Update status if changed
      if (_status != widget.sensor.status) {
        await sensorService.updateSensorStatus(
          widget.orgId,
          widget.siteId,
          widget.zoneId,
          widget.sensor.id,
          _status,
        );
      }

      // Update online status if changed
      if (_isOnline != widget.sensor.isOnline) {
        await sensorService.updateSensorOnlineStatus(
          widget.orgId,
          widget.siteId,
          widget.zoneId,
          widget.sensor.id,
          _isOnline,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sensor updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating sensor: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Sensor'),
        content: Text(
          'Are you sure you want to delete "${widget.sensor.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _deleteSensor();
    }
  }

  Future<void> _deleteSensor() async {
    setState(() => _isLoading = true);

    try {
      await SensorService().deleteSensor(
        widget.orgId,
        widget.siteId,
        widget.zoneId,
        widget.sensor.id,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sensor deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting sensor: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }
}
