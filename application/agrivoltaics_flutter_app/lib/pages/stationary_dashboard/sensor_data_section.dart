import 'package:flutter/material.dart';
import '../../models/sensor.dart';
import '../../services/sensor_service.dart';
import '../../services/readings_service.dart';

class SensorDataSection extends StatelessWidget {
  final String orgId;
  final String siteId;
  final String zoneId;
  final bool isDesktop;

  const SensorDataSection({
    super.key,
    required this.orgId,
    required this.siteId,
    required this.zoneId,
    this.isDesktop = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: isDesktop 
          ? const EdgeInsets.all(16)
          : const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: isDesktop ? MainAxisSize.max : MainAxisSize.min,
        children: [
          // Header
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Sensor Data',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          
          // Sensor data cards
          if (isDesktop)
            Expanded(
              child: StreamBuilder<List<Sensor>>(
                stream: SensorService().getSensors(orgId, siteId, zoneId),
                builder: (context, snapshot) {
                  return _buildSensorContent(context, snapshot);
                },
              ),
            )
          else
            StreamBuilder<List<Sensor>>(
              stream: SensorService().getSensors(orgId, siteId, zoneId),
              builder: (context, snapshot) {
                return _buildSensorContent(context, snapshot);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSensorContent(BuildContext context, AsyncSnapshot<List<Sensor>> snapshot) {
    if (snapshot.hasError) {
      return Center(
        child: Text('Error loading sensor data: ${snapshot.error}'),
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
            Icon(Icons.analytics_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No sensor data available',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Configure sensors to see their readings',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    // Filter only online sensors with data
    final sensorsWithData = sensors.where((s) => s.fields.isNotEmpty).toList();

    if (sensorsWithData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_empty, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Waiting for sensor data',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sensors are configured but haven\'t sent data yet',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    // Use ListView on mobile for better content sizing
    if (MediaQuery.of(context).size.width < 800) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: sensorsWithData.length,
        itemBuilder: (context, index) {
          final sensor = sensorsWithData[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _SensorDataCard(sensor: sensor),
          );
        },
      );
    }

    // GridView for desktop
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.5,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: sensorsWithData.length,
      itemBuilder: (context, index) {
        final sensor = sensorsWithData[index];
        return _SensorDataCard(sensor: sensor);
      },
    );
  }
}

class _SensorDataCard extends StatelessWidget {
  final Sensor sensor;

  const _SensorDataCard({required this.sensor});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with sensor name and icon
            Row(
              children: [
                Icon(
                  _getSensorIcon(sensor.model),
                  size: 20,
                  color: sensor.isOnline ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sensor.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: sensor.isOnline ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              sensor.model,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
            const Divider(height: 20),
            
            // Sensor readings based on fields
            _buildSensorReadings(),
            
            // Last updated
            if (sensor.lastReading != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Updated ${_formatLastReading(sensor.lastReading!)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorReadings() {
    if (sensor.fields.isEmpty) {
      return Center(
        child: Text(
          'No data',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[400],
          ),
        ),
      );
    }

    // Build custom layout based on sensor type
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: sensor.fields.entries.map((entry) {
        return _buildFieldReading(
          entry.key,
          entry.value.currentValue,
          entry.value.unit,
        );
      }).toList(),
    );
  }

  Widget _buildFieldReading(String fieldName, double? value, String unit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              _formatFieldName(fieldName),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
              ),
            ),
          ),
          Text(
            value != null ? '${value.toStringAsFixed(1)} $unit' : '-- $unit',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatFieldName(String alias) {
    return ReadingsService().formatFieldName(alias);
  }

  String _formatLastReading(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
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
