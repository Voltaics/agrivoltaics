import 'package:flutter/material.dart';
import 'package:agrivoltaics_flutter_app/models/site.dart';
import 'package:agrivoltaics_flutter_app/services/site_service.dart';
import 'package:agrivoltaics_flutter_app/app_state.dart' hide Site;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

class EditSiteDialog extends StatefulWidget {
  final String organizationId;
  final Site site;

  const EditSiteDialog({
    Key? key,
    required this.organizationId,
    required this.site,
  }) : super(key: key);

  @override
  State<EditSiteDialog> createState() => _EditSiteDialogState();
}

class _EditSiteDialogState extends State<EditSiteDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _addressController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  
  late String _selectedTimezone;
  late bool _isActive;
  bool _isLoading = false;

  // Common US timezones
  final List<String> _timezones = [
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'America/Phoenix',
    'America/Anchorage',
    'Pacific/Honolulu',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.site.name);
    _descriptionController = TextEditingController(text: widget.site.description);
    _addressController = TextEditingController(text: widget.site.address);
    
    // Initialize coordinates if they exist
    if (widget.site.location != null) {
      _latitudeController = TextEditingController(
        text: widget.site.location!.latitude.toString()
      );
      _longitudeController = TextEditingController(
        text: widget.site.location!.longitude.toString()
      );
    } else {
      _latitudeController = TextEditingController();
      _longitudeController = TextEditingController();
    }
    
    _selectedTimezone = widget.site.timezone;
    _isActive = widget.site.isActive;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _updateSite() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Parse latitude and longitude
      double? latitude;
      double? longitude;
      
      if (_latitudeController.text.isNotEmpty && _longitudeController.text.isNotEmpty) {
        latitude = double.tryParse(_latitudeController.text);
        longitude = double.tryParse(_longitudeController.text);
        
        if (latitude == null || longitude == null) {
          throw Exception('Invalid latitude or longitude values');
        }
        
        if (latitude < -90 || latitude > 90) {
          throw Exception('Latitude must be between -90 and 90');
        }
        
        if (longitude < -180 || longitude > 180) {
          throw Exception('Longitude must be between -180 and 180');
        }
      }

      await SiteService().updateSite(
        widget.organizationId,
        widget.site.id,
        {
          'name': _nameController.text.trim(),
          'description': _descriptionController.text.trim(),
          'address': _addressController.text.trim(),
          'timezone': _selectedTimezone,
          'location': (latitude != null && longitude != null)
              ? GeoPoint(latitude, longitude)
              : null,
          'isActive': _isActive,
        },
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Site updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating site: $e'),
            backgroundColor: Colors.red,
          ),
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

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Site'),
        content: Text(
          'Are you sure you want to delete "${widget.site.name}"?\n\n'
          'This will permanently delete the site and all its zones and sensors. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _deleteSite();
    }
  }

  Future<void> _deleteSite() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get the app state to update selected site
      final appState = Provider.of<AppState>(context, listen: false);
      
      // Get all sites before deleting to find a replacement
      final sitesSnapshot = await SiteService().getSites(widget.organizationId).first;
      
      // Find a different site to select (if any)
      Site? newSelectedSite;
      if (sitesSnapshot.length > 1) {
        // Select the first site that isn't the one being deleted
        newSelectedSite = sitesSnapshot.firstWhere(
          (site) => site.id != widget.site.id,
          orElse: () => sitesSnapshot.first,
        );
      }
      
      // Delete the site
      await SiteService().deleteSite(
        widget.organizationId,
        widget.site.id,
      );

      // Update selected site if needed
      if (mounted && appState.selectedSite?.id == widget.site.id) {
        if (newSelectedSite != null) {
          appState.setSelectedSite(newSelectedSite);
        } else {
          // No sites left, clear selection
          appState.setSelectedSite(null as dynamic);
        }
      }

      if (mounted) {
        Navigator.of(context).pop(); // Close edit dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Site deleted successfully'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting site: $e'),
            backgroundColor: Colors.red,
          ),
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Text('Edit Site'),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: _isLoading ? null : _confirmDelete,
            tooltip: 'Delete site',
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
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Site Name',
                    hintText: 'e.g., North Field',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a site name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'e.g., Main solar panel array',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    hintText: 'e.g., 123 Farm Road, City, State',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter an address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedTimezone,
                  decoration: const InputDecoration(
                    labelText: 'Timezone',
                    border: OutlineInputBorder(),
                  ),
                  items: _timezones.map((String timezone) {
                    return DropdownMenuItem<String>(
                      value: timezone,
                      child: Text(timezone),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedTimezone = newValue;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Location Coordinates (optional)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _latitudeController,
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                          hintText: 'e.g., 40.7128',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _longitudeController,
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                          hintText: 'e.g., -74.0060',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Active'),
                  subtitle: const Text('Site is currently active and collecting data'),
                  value: _isActive,
                  onChanged: (bool value) {
                    setState(() {
                      _isActive = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        // Delete button on the left
        TextButton(
          onPressed: _isLoading ? null : _confirmDelete,
          style: TextButton.styleFrom(
            foregroundColor: Colors.red,
          ),
          child: const Text('Delete'),
        ),
        const Spacer(),
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _updateSite,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Update Site'),
        ),
      ],
    );
  }
}
