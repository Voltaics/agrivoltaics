import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import 'sensors_config_section.dart';
import 'sensor_data_section.dart';

class StationaryDashboardPage extends StatefulWidget {
  const StationaryDashboardPage({super.key});

  @override
  State<StationaryDashboardPage> createState() => _StationaryDashboardPageState();
}

class _StationaryDashboardPageState extends State<StationaryDashboardPage> {
  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final selectedSite = appState.selectedSite;
    final selectedZone = appState.selectedZone;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
            ],
          ),
        ),
        
        // Main content
        Expanded(
          child: _buildContent(selectedSite, selectedZone),
        ),
      ],
    );
  }

  Widget _buildContent(dynamic selectedSite, dynamic selectedZone) {
    if (selectedSite == null) {
      return _buildEmptyState(
        icon: Icons.business,
        title: 'No Site Selected',
        message: 'Please select a site from the breadcrumb above',
      );
    }

    if (selectedZone == null) {
      return _buildEmptyState(
        icon: Icons.location_on,
        title: 'No Zone Selected',
        message: 'Please select a zone from the breadcrumb above',
      );
    }

    // Show sensor configuration and data sections side by side
    final appState = Provider.of<AppState>(context, listen: false);
    final selectedOrg = appState.selectedOrganization;
    
    if (selectedOrg == null) {
      return _buildEmptyState(
        icon: Icons.business,
        title: 'No Organization Selected',
        message: 'Please select an organization',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Mobile layout (vertical stack with dropdown)
        if (constraints.maxWidth < 800) {
          return _MobileSensorLayout(
            orgId: selectedOrg.id,
            siteId: selectedSite.id,
            zoneId: selectedZone.id,
          );
        }
        
        // Desktop layout (side by side)
        return Row(
          children: [
            // Left side: Sensor Configuration
            Expanded(
              flex: 1,
              child: SensorsConfigSection(
                orgId: selectedOrg.id,
                siteId: selectedSite.id,
                zoneId: selectedZone.id,
              ),
            ),
            
            // Right side: Sensor Data Display
            Expanded(
              flex: 1,
              child: SensorDataSection(
                orgId: selectedOrg.id,
                siteId: selectedSite.id,
                zoneId: selectedZone.id,
                isDesktop: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 24),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Mobile layout widget with dropdown for sensor configuration
class _MobileSensorLayout extends StatefulWidget {
  final String orgId;
  final String siteId;
  final String zoneId;

  const _MobileSensorLayout({
    required this.orgId,
    required this.siteId,
    required this.zoneId,
  });

  @override
  State<_MobileSensorLayout> createState() => _MobileSensorLayoutState();
}

class _MobileSensorLayoutState extends State<_MobileSensorLayout> {
  bool _showConfigPanel = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Dropdown button for sensor configuration
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _showConfigPanel = !_showConfigPanel;
              });
            },
            icon: Icon(_showConfigPanel ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
            label: const Text('Sensor Configuration'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.centerLeft,
            ),
          ),
        ),
        
        // Expandable configuration panel
        if (_showConfigPanel)
          Container(
            height: 300,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SensorsConfigSection(
              orgId: widget.orgId,
              siteId: widget.siteId,
              zoneId: widget.zoneId,
            ),
          ),
        
        // Sensor data display (scrollable)
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 32),
            child: SensorDataSection(
              orgId: widget.orgId,
              siteId: widget.siteId,
              zoneId: widget.zoneId,
              isDesktop: false,
            ),
          ),
        ),
      ],
    );
  }
}
