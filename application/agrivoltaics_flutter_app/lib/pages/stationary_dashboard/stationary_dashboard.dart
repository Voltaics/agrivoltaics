import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';

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

    // TODO: Implement sensor list view
    return _buildEmptyState(
      icon: Icons.sensors,
      title: 'No Sensors Yet',
      message: 'Sensors for ${selectedZone.name} will appear here',
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
