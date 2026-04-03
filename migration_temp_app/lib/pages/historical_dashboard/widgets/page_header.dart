import 'package:flutter/material.dart';

/// Static header displayed at the top of the Historical Dashboard page.
class HistoricalDashboardHeader extends StatelessWidget {
  const HistoricalDashboardHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Historical Trends',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 4),
          Text(
            'Review sensor trends over time with custom filters.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
