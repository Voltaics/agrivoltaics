import 'package:flutter/material.dart';
import '../../../services/sensor_service.dart';

// Reading Conflict Dialog
class ReadingConflictDialog extends StatefulWidget {
  final Map<String, String> conflictingReadings;
  final String newSensorName;
  final String orgId;
  final String siteId;
  final String zoneId;
  final SensorService sensorService;

  const ReadingConflictDialog({
    required this.conflictingReadings,
    required this.newSensorName,
    required this.orgId,
    required this.siteId,
    required this.zoneId,
    required this.sensorService,
  });

  @override
  State<ReadingConflictDialog> createState() => _ReadingConflictDialogState();
}

class _ReadingConflictDialogState extends State<ReadingConflictDialog> {
  late Map<String, bool> _resolutions; // true = use new sensor, false = keep existing
  final Map<String, String> _sensorNames = {}; // sensorId -> sensor name
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _resolutions = {for (final entry in widget.conflictingReadings.entries) entry.key: false};
    _loadSensorNames();
  }

  Future<void> _loadSensorNames() async {
    final sensorIds = widget.conflictingReadings.values.toSet();
    for (final sensorId in sensorIds) {
      final sensor = await widget.sensorService.getSensor(
        widget.orgId,
        widget.siteId,
        widget.zoneId,
        sensorId,
      );
      if (sensor != null) {
        _sensorNames[sensorId] = sensor.name;
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reading Conflict',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The following readings already exist in this zone. Choose which sensor should be the primary source:',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                ...widget.conflictingReadings.entries.map((entry) {
                  final readingName = entry.key;
                  final existingSensorId = entry.value;
                  final existingSensorName = _sensorNames[existingSensorId] ?? 'Unknown Sensor';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          readingName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        RadioListTile<bool>(
                          title: Text(
                            existingSensorName,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: const Text(
                            'Keep existing',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: false,
                          groupValue: _resolutions[readingName],
                          onChanged: (value) {
                            setState(() {
                              _resolutions[readingName] = value ?? false;
                            });
                          },
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<bool>(
                          title: Text(
                            widget.newSensorName,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: const Text(
                            'Use new sensor',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: true,
                          groupValue: _resolutions[readingName],
                          onChanged: (value) {
                            setState(() {
                              _resolutions[readingName] = value ?? true;
                            });
                          },
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[300],
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, _resolutions);
                      },
                      child: const Text('Confirm'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
