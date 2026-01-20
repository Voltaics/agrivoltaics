import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../models/zone.dart';
import '../../models/sensor.dart';
import '../../services/zone_service.dart';
import '../../services/sensor_service.dart';
import '../home/site_zone_breadcrumb.dart';

class StationaryDashboardPage extends StatefulWidget {
  const StationaryDashboardPage({super.key});

  @override
  State<StationaryDashboardPage> createState() => _StationaryDashboardPageState();
}

class _StationaryDashboardPageState extends State<StationaryDashboardPage> {
  final ZoneService _zoneService = ZoneService();
  final SensorService _sensorService = SensorService();

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final selectedOrg = appState.selectedOrganization;
    final selectedSite = appState.selectedSite;
    final selectedZone = appState.selectedZone;

    return Column(
      children: [
        // Title row with options button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Title
              const Text(
                'Stationary Sensors',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // Options button
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {
                  final appState = Provider.of<AppState>(context, listen: false);
                  if (appState.selectedZone == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please select a zone to configure sensors'),
                      ),
                    );
                  } else {
                    _showSensorConfigDialog(
                      context,
                      appState.selectedOrganization!.id,
                      appState.selectedSite!.id,
                      appState.selectedZone!,
                    );
                  }
                },
                tooltip: 'Sensor Configuration',
              ),
            ],
          ),
        ),
        
        // Site > Zone breadcrumb
        const SiteZoneBreadcrumb(),
        
        // Main content area
        Expanded(
          child: _buildContent(selectedOrg, selectedSite, selectedZone),
        ),
      ],
    );
  }

  Widget _buildContent(dynamic selectedOrg, dynamic selectedSite, dynamic selectedZone) {
    // Check if org and site are selected
    if (selectedOrg == null || selectedSite == null) {
      return _buildEmptyState();
    }

    // Case 1: Site + Zone selected - Show single zone card
    if (selectedZone != null) {
      return _buildSingleZoneView(selectedOrg.id, selectedSite.id, selectedZone);
    }

    // Case 2: Site only selected - Show all zones
    return _buildAllZonesView(selectedOrg.id, selectedSite.id);
  }

  // Build view for single zone (site + zone selected)
  Widget _buildSingleZoneView(String orgId, String siteId, dynamic zone) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: _buildZoneCard(orgId, siteId, zone),
    );
  }

  // Build view for all zones (site only selected)
  Widget _buildAllZonesView(String orgId, String siteId) {
    return StreamBuilder<List<Zone>>(
      stream: _zoneService.getZones(orgId, siteId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading zones: ${snapshot.error}'),
          );
        }

        final zones = snapshot.data ?? [];

        if (zones.isEmpty) {
          return _buildEmptyState();
        }

        // Check if any zones have readings
        final zonesWithReadings = zones.where((zone) => zone.readings.isNotEmpty).toList();
        
        if (zonesWithReadings.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          itemCount: zonesWithReadings.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildZoneCard(orgId, siteId, zonesWithReadings[index]),
            );
          },
        );
      },
    );
  }

  // Build a single zone card with its readings
  Widget _buildZoneCard(String orgId, String siteId, dynamic zone) {
    final zoneModel = zone as Zone;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Zone name header
            Text(
              zoneModel.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Readings list
            if (zoneModel.readings.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No readings configured for this zone',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              )
            else
              ...zoneModel.readings.entries.map((entry) {
                final readingName = entry.key;
                final sensorId = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildReadingCard(orgId, siteId, zoneModel.id, readingName, sensorId),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }

  // Build a single reading card
  Widget _buildReadingCard(String orgId, String siteId, String zoneId, String readingName, String sensorId) {
    return StreamBuilder<Sensor?>(
      stream: _sensorService.getSensors(orgId, siteId, zoneId).map((sensors) {
        try {
          return sensors.firstWhere((s) => s.id == sensorId);
        } catch (e) {
          return null;
        }
      }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildReadingCardUI(readingName, null, null, isLoading: true);
        }

        final sensor = snapshot.data;
        if (sensor == null) {
          return _buildReadingCardUI(readingName, null, null, error: 'Sensor not found');
        }

        // Get the field from the sensor that matches this reading name
        final field = sensor.fields[readingName];
        if (field == null) {
          return _buildReadingCardUI(readingName, null, null, error: 'Reading not available');
        }

        return _buildReadingCardUI(
          readingName,
          field.currentValue,
          field.unit,
          isOnline: sensor.isOnline,
        );
      },
    );
  }

  // UI for reading card
  Widget _buildReadingCardUI(
    String readingName,
    double? value,
    String? unit, {
    bool isLoading = false,
    String? error,
    bool isOnline = false,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey[300]!),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Reading name
            Text(
              _formatReadingName(readingName),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            
            // Value and unit
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (error != null)
              Text(
                error,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              )
            else if (value != null)
              Row(
                children: [
                  Text(
                    value.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isOnline ? Colors.black : Colors.grey[600],
                    ),
                  ),
                  if (unit != null && unit.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(
                      unit,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ],
              )
            else
              Text(
                'No data',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Format reading name for display (e.g., "temperature" -> "Temperature")
  String _formatReadingName(String name) {
    if (name.isEmpty) return name;
    
    // Convert camelCase to Title Case with spaces
    final words = name.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );
    
    // Capitalize first letter
    return words[0].toUpperCase() + words.substring(1);
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 60),
          Icon(
            Icons.sensors_off,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 24),
          Text(
            'No sensor readings for the site/zone selected',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Select another site/zone or you can add/configure sensors and readings by clicking the options button above',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  // Show sensor configuration dialog
  void _showSensorConfigDialog(
    BuildContext context,
    String orgId,
    String siteId,
    dynamic zone,
  ) {
    showDialog(
      context: context,
      builder: (context) => _SensorConfigDialog(
        orgId: orgId,
        siteId: siteId,
        zone: zone as Zone,
        sensorService: _sensorService,
      ),
    );
  }
}

// Sensor Configuration Dialog Widget
class _SensorConfigDialog extends StatefulWidget {
  final String orgId;
  final String siteId;
  final Zone zone;
  final SensorService sensorService;

  const _SensorConfigDialog({
    required this.orgId,
    required this.siteId,
    required this.zone,
    required this.sensorService,
  });

  @override
  State<_SensorConfigDialog> createState() => _SensorConfigDialogState();
}

class _SensorConfigDialogState extends State<_SensorConfigDialog> {
  int _selectedTabIndex = 0; // 0 = Sensors, 1 = Readings

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
                    // TODO: Implement add sensor functionality
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
                  color: isSelected ? Colors.black : Colors.grey[600],
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
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No sensors configured for this zone',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
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
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    // TODO: Implement edit sensor functionality
                  },
                  tooltip: 'Edit Sensor',
                  iconSize: 20,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Sensor model info
            Text(
              'Model: ${sensor.model}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
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
                      color: Colors.grey[700],
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
                            _formatReadingName(fieldName),
                            style: const TextStyle(fontSize: 13),
                          ),
                          Text(
                            field.unit,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              )
            else
              Text(
                'No readings available',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingsTab() {
    return Center(
      child: Text(
        'Readings configuration coming soon',
        style: TextStyle(
          fontSize: 16,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  // Format reading name for display
  String _formatReadingName(String name) {
    if (name.isEmpty) return name;
    
    // Convert camelCase to Title Case with spaces
    final words = name.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );
    
    // Capitalize first letter
    return words[0].toUpperCase() + words.substring(1);
  }
}
