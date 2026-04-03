import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/zone.dart';
import '../../../models/sensor.dart';
import '../../../services/zone_service.dart';
import '../../../services/sensor_service.dart';
import '../../../services/readings_service.dart';
import 'reading_conflict_dialog.dart';
import 'sensor_config_params_dialog.dart';

// Add Sensor Dialog Widget
class AddSensorDialog extends StatefulWidget {
  final String orgId;
  final String siteId;
  final Zone zone;
  final SensorService sensorService;
  final ZoneService zoneService;

  const AddSensorDialog({
    required this.orgId,
    required this.siteId,
    required this.zone,
    required this.sensorService,
    required this.zoneService,
  });

  @override
  State<AddSensorDialog> createState() => _AddSensorDialogState();
}

class _AddSensorDialogState extends State<AddSensorDialog> {
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      isRequired: false,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      controller: _longitudeController,
                      label: 'Longitude',
                      hint: '0.0000',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
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
                }),
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
                              selectedUnit = result;
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
      builder: (context) => ReadingConflictDialog(
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
