import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import '../../../models/zone.dart';
import '../../../models/sensor.dart';
import '../../../services/zone_service.dart';
import '../../../services/sensor_service.dart';
import '../../../services/formatters_service.dart';
import 'add_sensor_dialog.dart';
import 'edit_sensor_dialog.dart';
import 'sensor_config_params_dialog.dart';

// Sensor Configuration Dialog Widget
class SensorConfigDialog extends StatefulWidget {
  final String orgId;
  final String siteId;
  final Zone zone;
  final SensorService sensorService;
  final ZoneService zoneService;

  const SensorConfigDialog({
    required this.orgId,
    required this.siteId,
    required this.zone,
    required this.sensorService,
    required this.zoneService,
  });

  @override
  State<SensorConfigDialog> createState() => _SensorConfigDialogState();
}

class _SensorConfigDialogState extends State<SensorConfigDialog> {
  int _selectedTabIndex = 0; // 0 = Sensors, 1 = Readings
  final FormattersService _formattersService = FormattersService();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with title and add button
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sensor Configuration',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // Add sensor button
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AddSensorDialog(
                        orgId: widget.orgId,
                        siteId: widget.siteId,
                        zone: widget.zone,
                        sensorService: widget.sensorService,
                        zoneService: widget.zoneService,
                      ),
                    );
                  },
                  tooltip: 'Add Sensor',
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // Tab selector (Sensors / Readings)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _buildTabButton('Sensors', 0),
                const SizedBox(width: 16),
                _buildTabButton('Readings', 1),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // Content based on selected tab
          Expanded(
            child: _selectedTabIndex == 0
                ? _buildSensorsTab()
                : _buildReadingsTab(),
          ),
          
          // Close button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTabIndex = index;
          });
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppColors.textOnLight : AppColors.textMuted,
                ),
              ),
            ),
            if (isSelected)
              Container(
                height: 3,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorsTab() {
    return StreamBuilder<List<Sensor>>(
      stream: widget.sensorService.getSensors(
        widget.orgId,
        widget.siteId,
        widget.zone.id,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading sensors: ${snapshot.error}'),
          );
        }

        final sensors = snapshot.data ?? [];

        if (sensors.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.sensors_off,
                    size: 48,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No sensors configured for this zone',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: sensors.length,
          itemBuilder: (context, index) {
            return _buildSensorItem(sensors[index]);
          },
        );
      },
    );
  }

  Widget _buildSensorItem(Sensor sensor) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sensor name with edit button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    sensor.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () {
                        showSensorConfigParamsDialog(
                          context,
                          orgId: widget.orgId,
                          siteId: widget.siteId,
                          zoneId: widget.zone.id,
                          sensorId: sensor.id,
                        );
                      },
                      tooltip: 'Show Configuration Parameters',
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () {
                        _showEditSensorDialog(sensor);
                      },
                      tooltip: 'Edit Sensor',
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Sensor model info
            Text(
              'Model: ${sensor.model}',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Readings list
            if (sensor.fields.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Readings:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...sensor.fields.entries.map((entry) {
                    final fieldName = entry.key;
                    final field = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formattersService.formatReadingName(fieldName),
                            style: const TextStyle(fontSize: 13),
                          ),
                          Text(
                            field.unit,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              )
            else
              Text(
                'No readings available',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingsTab() {
    // Get all unique reading names from zone readings map
    if (widget.zone.readings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.library_books,
                size: 48,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 16),
              Text(
                'No readings configured for this zone',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<List<Sensor>>(
      stream: widget.sensorService.getSensors(
        widget.orgId,
        widget.siteId,
        widget.zone.id,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading sensors: ${snapshot.error}'),
          );
        }

        final sensors = snapshot.data ?? [];

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: widget.zone.readings.length,
          itemBuilder: (context, index) {
            final readings = widget.zone.readings.entries.toList();
            final entry = readings[index];
            final readingName = entry.key;
            final currentPrimarySensorId = entry.value;

            // Find all sensors that have this reading
            final sensorsWithReading = sensors
                .where((sensor) => sensor.fields.containsKey(readingName))
                .toList();

            // Find current primary sensor
            final currentPrimarySensor = sensors.firstWhere(
              (s) => s.id == currentPrimarySensorId,
              orElse: () => Sensor(
                id: '',
                name: 'Unknown',
                model: '',
                fields: {},
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Reading name on the left
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formattersService.formatReadingName(readingName),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${sensorsWithReading.length} sensor${sensorsWithReading.length != 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Dropdown on the right
                    Expanded(
                      flex: 3,
                      child: sensorsWithReading.isEmpty
                          ? Text(
                              'No sensors available',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                                fontStyle: FontStyle.italic,
                              ),
                            )
                          : DropdownButtonFormField<String>(
                              initialValue: currentPrimarySensorId,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: sensorsWithReading.map((sensor) {
                                return DropdownMenuItem<String>(
                                  value: sensor.id,
                                  child: Text(
                                    sensor.name,
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (newSensorId) async {
                                if (newSensorId != null && newSensorId != currentPrimarySensorId) {
                                  try {
                                    // Update the primary sensor for this reading
                                    await widget.zoneService.setPrimarySensor(
                                      orgId: widget.orgId,
                                      siteId: widget.siteId,
                                      zoneId: widget.zone.id,
                                      readingFieldName: readingName,
                                      sensorId: newSensorId,
                                    );

                                    // Show confirmation
                                    if (mounted) {
                                      final newSensor = sensors.firstWhere(
                                        (s) => s.id == newSensorId,
                                        orElse: () => Sensor(
                                          id: '',
                                          name: 'Unknown',
                                          model: '',
                                          fields: {},
                                          createdAt: DateTime.now(),
                                          updatedAt: DateTime.now(),
                                        ),
                                      );
                                      final oldSensorName = currentPrimarySensor.name;
                                      final newSensorName = newSensor.name;

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '$readingName: "$oldSensorName" → "$newSensorName"',
                                          ),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Error updating reading: $e'),
                                          backgroundColor: AppColors.error,
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditSensorDialog(Sensor sensor) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => EditSensorDialog(
        sensor: sensor,
        orgId: widget.orgId,
        siteId: widget.siteId,
        zone: widget.zone,
        sensorService: widget.sensorService,
        zoneService: widget.zoneService,
      ),
    );
  }

}
