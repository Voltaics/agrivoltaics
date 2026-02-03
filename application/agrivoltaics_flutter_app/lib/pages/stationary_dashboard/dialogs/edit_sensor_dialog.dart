import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/zone.dart';
import '../../../models/sensor.dart';
import '../../../services/zone_service.dart';
import '../../../services/sensor_service.dart';
import '../../../services/readings_service.dart';

// Edit Sensor Dialog
class EditSensorDialog extends StatefulWidget {
  final Sensor sensor;
  final String orgId;
  final String siteId;
  final Zone zone;
  final SensorService sensorService;
  final ZoneService zoneService;

  const EditSensorDialog({
    required this.sensor,
    required this.orgId,
    required this.siteId,
    required this.zone,
    required this.sensorService,
    required this.zoneService,
  });

  @override
  State<EditSensorDialog> createState() => _EditSensorDialogState();
}

class _EditSensorDialogState extends State<EditSensorDialog> {
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
                              selectedUnit = result;
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
                }),
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
                      }),
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
