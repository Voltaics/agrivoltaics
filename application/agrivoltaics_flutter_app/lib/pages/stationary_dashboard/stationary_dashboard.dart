import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../app_state.dart';
import '../../models/zone.dart';
import '../../models/sensor.dart';
import '../../services/zone_service.dart';
import '../../services/sensor_service.dart';
import '../../services/readings_service.dart';
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

  // Format reading name for display - get from ReadingsService, fallback to camelCase conversion
  String _formatReadingName(String alias) {
    // Try to get the display name from ReadingsService
    final readingsService = ReadingsService();
    final reading = readingsService.getReading(alias);
    if (reading != null) {
      return reading.name;
    }
    
    // Fallback: Convert camelCase to Title Case if reading not found
    if (alias.isEmpty) return alias;
    
    final words = alias.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );
    
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
        zoneService: _zoneService,
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
  final ZoneService zoneService;

  const _SensorConfigDialog({
    required this.orgId,
    required this.siteId,
    required this.zone,
    required this.sensorService,
    required this.zoneService,
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
                    showDialog(
                      context: context,
                      builder: (context) => _AddSensorDialog(
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
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No readings configured for this zone',
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
                status: 'unknown',
                isOnline: false,
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
                            _formatReadingName(readingName),
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
                              color: Colors.grey[600],
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
                                color: Colors.grey[500],
                                fontStyle: FontStyle.italic,
                              ),
                            )
                          : DropdownButtonFormField<String>(
                              value: currentPrimarySensorId,
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
                                          status: 'unknown',
                                          isOnline: false,
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
                                          backgroundColor: Colors.red,
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
      builder: (context) => _EditSensorDialog(
        sensor: sensor,
        orgId: widget.orgId,
        siteId: widget.siteId,
        zone: widget.zone,
        sensorService: widget.sensorService,
        zoneService: widget.zoneService,
      ),
    );
  }

  // Format reading name for display - get from ReadingsService, fallback to camelCase conversion
  String _formatReadingName(String alias) {
    // Try to get the display name from ReadingsService
    final readingsService = ReadingsService();
    final reading = readingsService.getReading(alias);
    if (reading != null) {
      return reading.name;
    }
    
    // Fallback: Convert camelCase to Title Case if reading not found
    if (alias.isEmpty) return alias;
    
    final words = alias.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );
    
    return words[0].toUpperCase() + words.substring(1);
  }
}

// Add Sensor Dialog Widget
class _AddSensorDialog extends StatefulWidget {
  final String orgId;
  final String siteId;
  final Zone zone;
  final SensorService sensorService;
  final ZoneService zoneService;

  const _AddSensorDialog({
    required this.orgId,
    required this.siteId,
    required this.zone,
    required this.sensorService,
    required this.zoneService,
  });

  @override
  State<_AddSensorDialog> createState() => _AddSensorDialogState();
}

class _AddSensorDialogState extends State<_AddSensorDialog> {
  final _sensorNameController = TextEditingController();
  final _sensorModelController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();

  final List<_ReadingItem> _readings = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _sensorNameController.dispose();
    _sensorModelController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              const Text(
                'Add New Sensor',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),

              // Sensor name input (required)
              _buildTextField(
                controller: _sensorNameController,
                label: 'Sensor Name',
                hint: 'e.g., DHT22 Sensor 1',
                isRequired: true,
              ),
              const SizedBox(height: 16),

              // Sensor model input (optional)
              _buildTextField(
                controller: _sensorModelController,
                label: 'Sensor Model',
                hint: 'e.g., DHT22',
                isRequired: false,
              ),
              const SizedBox(height: 16),

              // Location section
              const Text(
                'Location (Optional)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _latitudeController,
                      label: 'Latitude',
                      hint: '0.0000',
                      keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
                      isRequired: false,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      controller: _longitudeController,
                      label: 'Longitude',
                      hint: '0.0000',
                      keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
                      isRequired: false,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Readings section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Readings',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _showAddReadingDialog,
                    tooltip: 'Add Reading',
                    iconSize: 20,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Readings list
              if (_readings.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'No readings added yet. Add at least one reading to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                )
              else
                ...List.generate(_readings.length, (index) {
                  final reading = _readings[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${reading.displayName} (${reading.unit})',
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            setState(() {
                              _readings.removeAt(index);
                            });
                          },
                          tooltip: 'Remove Reading',
                          iconSize: 20,
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[300],
                      ),
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleAddSensor,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Add'),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool isRequired = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            if (isRequired)
              const Text(
                ' *',
                style: TextStyle(color: Colors.red),
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  void _showAddReadingDialog() {
    _showAddReadingDialogAsync();
  }

  Future<void> _showAddReadingDialogAsync() async {
    final readingsService = ReadingsService();
    final allReadings = readingsService.getAllReadings(); // Pre-load outside dialog
    String? selectedReadingAlias;
    String? selectedReadingDisplayName;
    String? selectedUnit;
    final outerContext = context; // Capture outer context
    late List<Reading> readingsList;

    if (allReadings.isEmpty) {
      // Handle empty case before opening dialog
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No readings available')),
      );
      return;
    }

    readingsList = allReadings.values.toList(); // Pre-compute list

    if (!mounted) return;

    // Create controllers once, outside the builder
    final readingController = TextEditingController();
    final unitController = TextEditingController();

    showDialog(
      context: outerContext,
      builder: (innerContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add Reading',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: InputDecoration(
                        labelText: 'Reading Name *',
                        hintText: 'Search or select a reading',
                        border: const OutlineInputBorder(),
                        suffixIcon: selectedReadingAlias != null
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setDialogState(() {
                                    selectedReadingAlias = null;
                                    selectedUnit = null;
                                    readingController.clear();
                                    unitController.clear();
                                  });
                                },
                              )
                            : null,
                      ),
                      readOnly: true,
                      focusNode: FocusNode(skipTraversal: true)..canRequestFocus = false,
                      controller: readingController,
                      onTap: () async {
                        // Filter out readings already added
                        final availableReadings = readingsList
                            .where((r) => !_readings.any((item) => item.name == r.alias))
                            .toList();
                        
                        final result = await _showSearchableDropdown(
                          innerContext,
                          availableReadings,
                          (r) => r.name,
                        );
                        if (result != null) {
                          setDialogState(() {
                            selectedReadingAlias = result.alias;
                            selectedReadingDisplayName = result.name;
                            selectedUnit = result.defaultUnit;
                            readingController.text = result.name;
                            unitController.text = result.defaultUnit;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    if (selectedReadingAlias != null) ...[
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: 'Unit *',
                          hintText: 'Search or select a unit',
                          border: const OutlineInputBorder(),
                          suffixIcon: selectedUnit != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setDialogState(() {
                                      selectedUnit = null;
                                    });
                                  },
                                )
                              : null,
                        ),
                        readOnly: true,
                        focusNode: FocusNode(skipTraversal: true)..canRequestFocus = false,
                        controller: unitController,
                        onTap: () async {
                          final validUnits =
                              readingsService.getValidUnits(selectedReadingAlias!);
                          final result = await _showSearchableDropdown(
                            innerContext,
                            validUnits,
                            (u) => u,
                          );
                          if (result != null) {
                            setDialogState(() {
                              selectedUnit = result as String;
                              unitController.text = result;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[300],
                            ),
                            onPressed: () => Navigator.pop(innerContext),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(color: Colors.black),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selectedReadingAlias != null &&
                                    selectedUnit != null
                                ? () {
                                    setState(() {
                                      _readings.add(_ReadingItem(
                                        name: selectedReadingAlias!,
                                        displayName: selectedReadingDisplayName!,
                                        unit: selectedUnit!,
                                      ));
                                    });
                                    Navigator.pop(innerContext);
                                  }
                                : null,
                            child: const Text('Add'),
                          ),
                        ),
                      ],
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

  Future<T?> _showSearchableDropdown<T>(
    BuildContext context,
    List<T> items,
    String Function(T) getLabel,
  ) async {
    String searchText = '';
    late List<T> filtered = items;

    return showDialog<T>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            insetPadding: const EdgeInsets.symmetric(horizontal: 40),
            child: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      autofocus: true,
                      onChanged: (value) {
                        setState(() {
                          searchText = value;
                          filtered = items
                              .where((item) => getLabel(item)
                                  .toLowerCase()
                                  .contains(searchText.toLowerCase()))
                              .toList();
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                      ),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              searchText.isEmpty
                                  ? 'No items'
                                  : 'No results for "$searchText"',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: false,
                            padding: EdgeInsets.zero,
                            itemExtent: 48,
                            addAutomaticKeepAlives: false,
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              return ListTile(
                                dense: true,
                                title: Text(getLabel(item)),
                                onTap: () {
                                  Navigator.pop(dialogContext, item);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleAddSensor() async {
    // Validation
    final sensorName = _sensorNameController.text.trim();
    if (sensorName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sensor name is required')),
      );
      return;
    }

    if (_readings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one reading')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Parse location if provided
      GeoPoint? location;
      final lat = _latitudeController.text.trim();
      final lon = _longitudeController.text.trim();
      if (lat.isNotEmpty && lon.isNotEmpty) {
        try {
          location = GeoPoint(double.parse(lat), double.parse(lon));
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid latitude/longitude')),
            );
          }
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      // Create sensor fields from readings
      final Map<String, SensorField> fields = {};
      for (final reading in _readings) {
        fields[reading.name] = SensorField(unit: reading.unit);
      }

      // Check for conflicting readings
      final conflictingReadings = <String, String>{}; // reading name -> existing sensor id
      for (final readingName in fields.keys) {
        if (widget.zone.readings.containsKey(readingName)) {
          conflictingReadings[readingName] = widget.zone.readings[readingName]!;
        }
      }

      Map<String, bool>? conflictResolution;
      if (conflictingReadings.isNotEmpty && mounted) {
        conflictResolution = await _showConflictDialog(
          conflictingReadings,
          sensorName,
        );
        if (conflictResolution == null) {
          setState(() {
            _isLoading = false;
          });
          return; // User cancelled
        }
      }

      // Create the sensor
      final sensorId = await widget.sensorService.createSensor(
        orgId: widget.orgId,
        siteId: widget.siteId,
        zoneId: widget.zone.id,
        name: sensorName,
        model: _sensorModelController.text.trim(),
        location: location,
        fields: fields,
      );

      // Update zone readings to include new readings (respect conflict resolution)
      // Apply explicit per-reading updates to avoid merge issues
      for (final readingName in fields.keys) {
        if (conflictingReadings.containsKey(readingName)) {
          final useNew = conflictResolution?[readingName] ?? false;
          if (useNew) {
            await widget.zoneService.setPrimarySensor(
              orgId: widget.orgId,
              siteId: widget.siteId,
              zoneId: widget.zone.id,
              readingFieldName: readingName,
              sensorId: sensorId,
            );
          }
          // else keep existing mapping
        } else {
          await widget.zoneService.setPrimarySensor(
            orgId: widget.orgId,
            siteId: widget.siteId,
            zoneId: widget.zone.id,
            readingFieldName: readingName,
            sensorId: sensorId,
          );
        }
      }

      if (mounted) {
        await showSensorConfigParamsDialog(
          context,
          orgId: widget.orgId,
          siteId: widget.siteId,
          zoneId: widget.zone.id,
          sensorId: sensorId,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating sensor: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<Map<String, bool>?> _showConflictDialog(
    Map<String, String> conflictingReadings,
    String newSensorName,
  ) {
    return showDialog<Map<String, bool>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ReadingConflictDialog(
        conflictingReadings: conflictingReadings,
        newSensorName: newSensorName,
        orgId: widget.orgId,
        siteId: widget.siteId,
        zoneId: widget.zone.id,
        sensorService: widget.sensorService,
      ),
    );
  }

}

// Helper class for readings
class _ReadingItem {
  final String name; // alias (for storage/reference)
  final String displayName; // human-readable name
  final String unit;

  _ReadingItem({
    required this.name,
    required this.displayName,
    required this.unit,
  });
}

// Small row for displaying key/value pairs in dialogs
class _ConfigRow extends StatelessWidget {
  final String label;
  final String value;

  const _ConfigRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: SelectableText(value),
          ),
        ],
      ),
    );
  }
}

// Shared helper to show sensor configuration parameters dialog
Future<void> showSensorConfigParamsDialog(
  BuildContext context, {
  required String orgId,
  required String siteId,
  required String zoneId,
  required String sensorId,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Sensor Configuration Parameters'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'These parameters will need to be configured in the CPU that sends the sensor data to the cloud',
          ),
          const SizedBox(height: 16),
          _ConfigRow(label: 'Organization ID', value: orgId),
          _ConfigRow(label: 'Site ID', value: siteId),
          _ConfigRow(label: 'Zone ID', value: zoneId),
          _ConfigRow(label: 'Sensor ID', value: sensorId),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

// Edit Sensor Dialog
class _EditSensorDialog extends StatefulWidget {
  final Sensor sensor;
  final String orgId;
  final String siteId;
  final Zone zone;
  final SensorService sensorService;
  final ZoneService zoneService;

  const _EditSensorDialog({
    required this.sensor,
    required this.orgId,
    required this.siteId,
    required this.zone,
    required this.sensorService,
    required this.zoneService,
  });

  @override
  State<_EditSensorDialog> createState() => _EditSensorDialogState();
}

class _EditSensorDialogState extends State<_EditSensorDialog> {
  late final TextEditingController _sensorNameController;
  late final TextEditingController _sensorModelController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  
  late List<_ReadingItem> _readings;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _sensorNameController = TextEditingController(text: widget.sensor.name);
    _sensorModelController = TextEditingController(text: widget.sensor.model);
    
    // Initialize location controllers
    if (widget.sensor.location != null) {
      _latitudeController = TextEditingController(
        text: widget.sensor.location!.latitude.toString(),
      );
      _longitudeController = TextEditingController(
        text: widget.sensor.location!.longitude.toString(),
      );
    } else {
      _latitudeController = TextEditingController();
      _longitudeController = TextEditingController();
    }
    
    // Initialize readings from sensor's fields
    final readingsService = ReadingsService();
    final allReadings = readingsService.getAllReadings();
    _readings = widget.sensor.fields.entries
        .map((e) {
          final reading = allReadings[e.key];
          return _ReadingItem(
            name: e.key,
            displayName: reading?.name ?? e.key,
            unit: e.value.unit,
          );
        })
        .toList();
  }

  @override
  void dispose() {
    _sensorNameController.dispose();
    _sensorModelController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _showAddReadingDialog() async {
    final readingsService = ReadingsService();
    final allReadings = readingsService.getAllReadings(); // Pre-load outside dialog
    String? selectedReadingAlias;
    String? selectedReadingDisplayName;
    String? selectedUnit;
    
    if (allReadings.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No readings available')),
      );
      return;
    }

    final allReadingsList = allReadings.values.toList(); // Pre-compute list
    
    if (!mounted) return;

    // Create controllers once, outside the builder
    final readingController = TextEditingController();
    final unitController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Filter out readings already added
            final availableReadings = allReadingsList
                .where((r) => !_readings.any((item) => item.name == r.alias))
                .toList();

            return AlertDialog(
              title: const Text('Add Reading'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      decoration: InputDecoration(
                        labelText: 'Reading Name *',
                        hintText: 'Search or select a reading',
                        border: const OutlineInputBorder(),
                        suffixIcon: selectedReadingAlias != null
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setDialogState(() {
                                    selectedReadingAlias = null;
                                    selectedUnit = null;
                                  });
                                },
                              )
                            : null,
                      ),
                      readOnly: true,
                      focusNode: FocusNode(skipTraversal: true)..canRequestFocus = false,
                      controller: readingController,
                      onTap: () async {
                        final result = await _showSearchableDropdown(
                          context,
                          availableReadings,
                          (r) => r.name,
                        );
                        if (result != null) {
                          setDialogState(() {
                            selectedReadingAlias = result.alias;
                            selectedReadingDisplayName = result.name;
                            selectedUnit = result.defaultUnit;
                            readingController.text = result.name;
                            unitController.text = result.defaultUnit;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    if (selectedReadingAlias != null)
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: 'Unit *',
                          hintText: 'Search or select a unit',
                          border: const OutlineInputBorder(),
                          suffixIcon: selectedUnit != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setDialogState(() {
                                      selectedUnit = null;
                                    });
                                  },
                                )
                              : null,
                        ),
                        readOnly: true,
                        focusNode: FocusNode(skipTraversal: true)..canRequestFocus = false,
                        controller: unitController,
                        onTap: () async {
                          final validUnits =
                              readingsService.getValidUnits(selectedReadingAlias!);
                          final result = await _showSearchableDropdown(
                            context,
                            validUnits,
                            (u) => u,
                          );
                          if (result != null) {
                            setDialogState(() {
                              selectedUnit = result as String;
                              unitController.text = result;
                            });
                          }
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: selectedReadingAlias != null &&
                          selectedUnit != null
                      ? () {
                          setState(() {
                            _readings.add(_ReadingItem(
                              name: selectedReadingAlias!,
                              displayName: selectedReadingDisplayName!,
                              unit: selectedUnit!,
                            ));
                          });
                          Navigator.pop(context);
                        }
                      : null,
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<T?> _showSearchableDropdown<T>(
    BuildContext context,
    List<T> items,
    String Function(T) getLabel,
  ) async {
    String searchText = '';
    late List<T> filtered = items;

    return showDialog<T>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            insetPadding: const EdgeInsets.symmetric(horizontal: 40),
            child: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      autofocus: true,
                      onChanged: (value) {
                        setState(() {
                          searchText = value;
                          filtered = items
                              .where((item) => getLabel(item)
                                  .toLowerCase()
                                  .contains(searchText.toLowerCase()))
                              .toList();
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                      ),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              searchText.isEmpty
                                  ? 'No items'
                                  : 'No results for "$searchText"',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: false,
                            padding: EdgeInsets.zero,
                            itemExtent: 48,
                            addAutomaticKeepAlives: false,
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              return ListTile(
                                dense: true,
                                title: Text(getLabel(item)),
                                onTap: () {
                                  Navigator.pop(dialogContext, item);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  void _removeReading(int index) {
    setState(() {
      _readings.removeAt(index);
    });
  }

  Future<void> _handleDeleteSensor() async {
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
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Find all readings that need reassignment
      final List<String> deletedReadings = widget.sensor.fields.keys.toList();
      final Map<String, String?> readingChanges = {};

      // Fetch latest zone readings to avoid stale state
      final currentZone = await widget.zoneService.getZone(widget.orgId, widget.siteId, widget.zone.id);
      final currentReadings = currentZone?.readings ?? {};

      // Check which readings were primary for this sensor
      for (final reading in deletedReadings) {
        final primarySensorId = currentReadings[reading];
        if (primarySensorId == widget.sensor.id) {
          // This reading was primary, need to find replacement or remove
          final newPrimary = await _findReplacementSensor(reading, widget.sensor.id);
          readingChanges[reading] = newPrimary;
          
          if (newPrimary != null) {
            await widget.zoneService.setPrimarySensor(
              orgId: widget.orgId,
              siteId: widget.siteId,
              zoneId: widget.zone.id,
              readingFieldName: reading,
              sensorId: newPrimary,
            );
          } else {
            await widget.zoneService.removePrimarySensor(
              orgId: widget.orgId,
              siteId: widget.siteId,
              zoneId: widget.zone.id,
              readingFieldName: reading,
            );
          }
        }
      }

      // Delete the sensor
      await widget.sensorService.deleteSensor(
        widget.orgId,
        widget.siteId,
        widget.zone.id,
        widget.sensor.id,
      );

      if (mounted) {
        Navigator.pop(context); // Close edit dialog
        await _showSummaryDialog(readingChanges, wasDeleted: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting sensor: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSave() async {
    final sensorName = _sensorNameController.text.trim();
    
    if (sensorName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sensor name is required')),
      );
      return;
    }

    if (_readings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one reading is required')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Prepare updates map
      final Map<String, dynamic> updates = {
        'name': sensorName,
        'model': _sensorModelController.text.trim(),
      };

      // Handle location
      final latStr = _latitudeController.text.trim();
      final lonStr = _longitudeController.text.trim();
      if (latStr.isNotEmpty && lonStr.isNotEmpty) {
        final lat = double.tryParse(latStr);
        final lon = double.tryParse(lonStr);
        if (lat != null && lon != null) {
          updates['location'] = GeoPoint(lat, lon);
        }
      } else {
        updates['location'] = null;
      }

      // Handle fields changes
      final Map<String, SensorField> newFields = {};
      for (final reading in _readings) {
        // Preserve existing field data if it exists
        if (widget.sensor.fields.containsKey(reading.name)) {
          final existingField = widget.sensor.fields[reading.name]!;
          newFields[reading.name] = existingField.copyWith(unit: reading.unit);
        } else {
          // New field
          newFields[reading.name] = SensorField(unit: reading.unit);
        }
      }
      updates['fields'] = newFields.map((key, value) => MapEntry(key, value.toMap()));

      // Track reading changes for summary
      final Map<String, String?> readingChanges = {};
      
      // Find removed and new readings
      final oldReadings = widget.sensor.fields.keys.toSet();
      final newReadingNames = _readings.map((r) => r.name).toSet();
      final removedReadings = oldReadings.difference(newReadingNames);
      final addedReadings = newReadingNames.difference(oldReadings);

      // Fetch latest zone readings to avoid stale state
      final currentZone = await widget.zoneService.getZone(widget.orgId, widget.siteId, widget.zone.id);
      final currentReadings = currentZone?.readings ?? {};

      // Handle primary reading reassignments for removed readings
      for (final reading in removedReadings) {
        final primarySensorId = currentReadings[reading];
        if (primarySensorId == widget.sensor.id) {
          // This reading was primary for this sensor, need to find replacement
          final newPrimary = await _findReplacementSensor(reading, widget.sensor.id);
          readingChanges[reading] = newPrimary;
          
          if (newPrimary != null) {
            await widget.zoneService.setPrimarySensor(
              orgId: widget.orgId,
              siteId: widget.siteId,
              zoneId: widget.zone.id,
              readingFieldName: reading,
              sensorId: newPrimary,
            );
          } else {
            await widget.zoneService.removePrimarySensor(
              orgId: widget.orgId,
              siteId: widget.siteId,
              zoneId: widget.zone.id,
              readingFieldName: reading,
            );
          }
        }
      }

      // Handle new readings - add them to zone readings
      for (final reading in addedReadings) {
        await widget.zoneService.setPrimarySensor(
          orgId: widget.orgId,
          siteId: widget.siteId,
          zoneId: widget.zone.id,
          readingFieldName: reading,
          sensorId: widget.sensor.id,
        );
      }

      // Update the sensor
      await widget.sensorService.updateSensor(
        widget.orgId,
        widget.siteId,
        widget.zone.id,
        widget.sensor.id,
        updates,
      );

      if (mounted) {
        Navigator.pop(context); // Close edit dialog
        if (readingChanges.isNotEmpty) {
          await _showSummaryDialog(readingChanges);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating sensor: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<String?> _findReplacementSensor(String readingName, String excludeSensorId) async {
    // Get all sensors in this zone
    final sensors = await widget.sensorService
        .getSensors(widget.orgId, widget.siteId, widget.zone.id)
        .first;
    
    // Find another sensor with this reading
    for (final sensor in sensors) {
      if (sensor.id != excludeSensorId && sensor.fields.containsKey(readingName)) {
        return sensor.id;
      }
    }
    return null;
  }

  Future<void> _showSummaryDialog(Map<String, String?> readingChanges, {bool wasDeleted = false}) async {
    // Fetch sensor names for the summary
    final Map<String, String> sensorNames = {};
    final sensorIds = readingChanges.values.whereType<String>().toSet();
    for (final sensorId in sensorIds) {
      final sensor = await widget.sensorService.getSensor(
        widget.orgId,
        widget.siteId,
        widget.zone.id,
        sensorId,
      );
      if (sensor != null) {
        sensorNames[sensorId] = sensor.name;
      }
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(wasDeleted ? 'Sensor Deleted' : 'Sensor Updated'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wasDeleted)
                Text(
                  '"${widget.sensor.name}" has been deleted.',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                )
              else
                const Text(
                  'Sensor has been updated successfully.',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              if (readingChanges.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Primary Reading Changes:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...readingChanges.entries.map((entry) {
                  final readingName = entry.key;
                  final newPrimarySensorId = entry.value;
                  
                  if (newPrimarySensorId == null) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, size: 18, color: Colors.orange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$readingName: No longer has a primary sensor assigned',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  } else {
                    final newSensorName = sensorNames[newPrimarySensorId] ?? 'Unknown';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.swap_horiz, size: 18, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 13, color: Colors.black87),
                                children: [
                                  TextSpan(
                                    text: '$readingName: ',
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                  TextSpan(text: '"${widget.sensor.name}" → '),
                                  TextSpan(
                                    text: '"$newSensorName"',
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                }).toList(),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    bool isRequired = true,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        hintText: hint,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      keyboardType: keyboardType,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit, color: Colors.blue),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Edit Sensor',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    iconSize: 20,
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTextField(
                      controller: _sensorNameController,
                      label: 'Sensor Name',
                      hint: 'e.g., Soil Moisture Sensor',
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _sensorModelController,
                      label: 'Sensor Model',
                      hint: 'e.g., DHT22',
                      isRequired: false,
                    ),
                    const SizedBox(height: 16),

                    // Location section
                    const Text(
                      'Location (Optional)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _latitudeController,
                            label: 'Latitude',
                            hint: '0.0000',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            isRequired: false,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            controller: _longitudeController,
                            label: 'Longitude',
                            hint: '0.0000',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            isRequired: false,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Readings section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Readings',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: _isLoading ? null : _showAddReadingDialog,
                          tooltip: 'Add Reading',
                          iconSize: 20,
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Readings list
                    if (_readings.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'No readings configured. Add at least one reading to continue.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      )
                    else
                      ...List.generate(_readings.length, (index) {
                        final reading = _readings[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    border: Border.all(color: Colors.grey[300]!),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          reading.displayName,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        reading.unit,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 18),
                                onPressed: _isLoading ? null : () => _removeReading(index),
                                tooltip: 'Remove',
                                color: Colors.red[400],
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                children: [
                  // Delete button on the left
                  TextButton.icon(
                    onPressed: _isLoading ? null : _handleDeleteSensor,
                    icon: const Icon(Icons.delete, size: 18),
                    label: const Text('Delete Sensor'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                  const Spacer(),
                  // Cancel and Save buttons on the right
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleSave,
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Reading Conflict Dialog
class _ReadingConflictDialog extends StatefulWidget {
  final Map<String, String> conflictingReadings;
  final String newSensorName;
  final String orgId;
  final String siteId;
  final String zoneId;
  final SensorService sensorService;

  const _ReadingConflictDialog({
    required this.conflictingReadings,
    required this.newSensorName,
    required this.orgId,
    required this.siteId,
    required this.zoneId,
    required this.sensorService,
  });

  @override
  State<_ReadingConflictDialog> createState() => _ReadingConflictDialogState();
}

class _ReadingConflictDialogState extends State<_ReadingConflictDialog> {
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
                }).toList(),
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
