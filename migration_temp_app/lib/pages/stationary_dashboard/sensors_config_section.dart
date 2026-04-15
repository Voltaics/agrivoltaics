import 'package:flutter/material.dart';
import '../../models/sensor.dart';
import '../../services/sensor_service.dart';
import '../create_sensor_dialog.dart';
import '../edit_sensor_dialog.dart';

class SensorsConfigSection extends StatelessWidget {
  final String orgId;
  final String siteId;
  final String zoneId;

  const SensorsConfigSection({
    super.key,
    required this.orgId,
    required this.siteId,
    required this.zoneId,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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
                ElevatedButton.icon(
                  onPressed: () => _showCreateSensorDialog(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Sensor'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // Sensors list
          Expanded(
            child: StreamBuilder<List<Sensor>>(
              stream: SensorService().getSensors(orgId, siteId, zoneId),
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

                if (sensors.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.sensors_off, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No sensors configured',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Click "Add Sensor" to get started',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: sensors.length,
                  itemBuilder: (context, index) {
                    final sensor = sensors[index];
                    return _SensorConfigCard(
                      sensor: sensor,
                      orgId: orgId,
                      siteId: siteId,
                      zoneId: zoneId,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateSensorDialog(BuildContext context) {
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

class _SensorConfigCard extends StatelessWidget {
  final Sensor sensor;
  final String orgId;
  final String siteId;
  final String zoneId;

  const _SensorConfigCard({
    required this.sensor,
    required this.orgId,
    required this.siteId,
    required this.zoneId,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: sensor.isOnline ? Colors.green : Colors.grey,
          child: Icon(
            _getSensorIcon(sensor.model),
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          sensor.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Model: ${sensor.model}'),
            Text('Status: ${sensor.status}'),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: sensor.isOnline ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  sensor.isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: sensor.isOnline ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () => _showEditDialog(context),
          tooltip: 'Edit sensor',
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => EditSensorDialog(
        sensor: sensor,
        orgId: orgId,
        siteId: siteId,
        zoneId: zoneId,
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
}
