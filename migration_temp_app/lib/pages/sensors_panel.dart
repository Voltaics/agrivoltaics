import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sensor.dart';
import '../services/sensor_service.dart';
import '../app_state.dart';
import 'create_sensor_dialog.dart';
import 'edit_sensor_dialog.dart';

class SensorsPanel extends StatelessWidget {
  const SensorsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final selectedOrg = appState.selectedOrganization;
    final selectedSite = appState.selectedSite;
    final selectedZone = appState.selectedZone;

    if (selectedOrg == null || selectedSite == null || selectedZone == null) {
      return const Center(
        child: Text('Please select a zone to view sensors'),
      );
    }

    return StreamBuilder<List<Sensor>>(
      stream: SensorService().getSensors(
        selectedOrg.id,
        selectedSite.id,
        selectedZone.id,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading sensors: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final sensors = snapshot.data!;

        return Column(
          children: [
            // Header with Add button
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sensors',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showCreateSensorDialog(
                      context,
                      selectedOrg.id,
                      selectedSite.id,
                      selectedZone.id,
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Sensor'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Sensors list
            Expanded(
              child: sensors.isEmpty
                  ? const Center(
                      child: Text('No sensors yet. Add one to get started!'),
                    )
                  : ListView.builder(
                      itemCount: sensors.length,
                      itemBuilder: (context, index) {
                        final sensor = sensors[index];
                        return _SensorListItem(
                          sensor: sensor,
                          orgId: selectedOrg.id,
                          siteId: selectedSite.id,
                          zoneId: selectedZone.id,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _showCreateSensorDialog(
    BuildContext context,
    String orgId,
    String siteId,
    String zoneId,
  ) {
    showDialog(
      context: context,
      builder: (context) => CreateSensorDialog(
        orgId: orgId,
        siteId: siteId,
        zoneId: zoneId,
      ),
    );
  }
}

class _SensorListItem extends StatefulWidget {
  final Sensor sensor;
  final String orgId;
  final String siteId;
  final String zoneId;

  const _SensorListItem({
    required this.sensor,
    required this.orgId,
    required this.siteId,
    required this.zoneId,
  });

  @override
  State<_SensorListItem> createState() => _SensorListItemState();
}

class _SensorListItemState extends State<_SensorListItem> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final sensor = widget.sensor;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with sensor name and online status
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  _getSensorIcon(sensor.model),
                  size: 20,
                  color: sensor.isOnline ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    sensor.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: sensor.isOnline
                        ? Colors.green.withAlpha((0.1 * 255).toInt())
                        : Colors.red.withAlpha((0.1 * 255).toInt()),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sensor.isOnline ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        sensor.isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          fontSize: 11,
                          color: sensor.isOnline ? Colors.green[700] : Colors.red[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings, size: 20),
                  onPressed: () => _showEditSensorDialog(context),
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          
          // Sensor data (readings)
          if (sensor.fields.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: sensor.fields.entries.map((entry) {
                  final field = entry.value;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha((0.05 * 255).toInt()),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.blue.withAlpha((0.2 * 255).toInt()),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatFieldName(entry.key),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          field.currentValue != null
                              ? '${field.currentValue!.toStringAsFixed(1)} ${field.unit}'
                              : 'No data',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          
          // Expandable section for details
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(
                'Details',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
              initiallyExpanded: _isExpanded,
              onExpansionChanged: (expanded) {
                setState(() {
                  _isExpanded = expanded;
                });
              },
              tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _DetailItem(
                        icon: Icons.category,
                        label: 'Model',
                        value: sensor.model,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DetailItem(
                        icon: Icons.info_outline,
                        label: 'Status',
                        value: sensor.status,
                      ),
                    ),
                  ],
                ),
                if (sensor.lastReading != null) ...[
                  const SizedBox(height: 8),
                  _DetailItem(
                    icon: Icons.access_time,
                    label: 'Last Reading',
                    value: _formatDateTime(sensor.lastReading!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEditSensorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => EditSensorDialog(
        sensor: widget.sensor,
        orgId: widget.orgId,
        siteId: widget.siteId,
        zoneId: widget.zoneId,
      ),
    );
  }

  IconData _getSensorIcon(String model) {
    switch (model.toUpperCase()) {
      case 'DHT22':
        return Icons.thermostat;
      case 'VEML7700':
        return Icons.light_mode;
      case 'DFROBOT-SOIL':
        return Icons.grass;
      case 'SGP30':
        return Icons.air;
      default:
        return Icons.sensors;
    }
  }

  String _formatFieldName(String fieldName) {
    // Convert field names like "temperature" to "Temperature"
    if (fieldName.isEmpty) return fieldName;
    return fieldName[0].toUpperCase() + fieldName.substring(1);
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}

// Helper widget for detail items
class _DetailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: Colors.grey[600],
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
