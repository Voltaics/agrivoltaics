import 'package:agrivoltaics_flutter_app/models/site.dart' as models;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';

typedef OnSiteChanged = void Function(models.Site site);
typedef OnDateRangePressed = void Function();

class SiteSelectorWidget extends StatelessWidget {
  final String orgId;
  final List<models.Site> sites;
  final models.Site? selectedSite;
  final PickerDateRange dateRange;
  final OnSiteChanged onSiteChanged;
  final OnDateRangePressed onDateRangePressed;
  final bool isLoading;

  const SiteSelectorWidget({
    super.key,
    required this.orgId,
    required this.sites,
    required this.selectedSite,
    required this.dateRange,
    required this.onSiteChanged,
    required this.onDateRangePressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final dateFormat = DateFormat('MMM d, yyyy');
    final start = dateRange.startDate ?? DateTime.now();
    final end = dateRange.endDate ?? start;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Site & Date Range',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (sites.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No sites available',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButton<String>(
                    value: selectedSite?.id,
                    isExpanded: true,
                    hint: const Text('Choose a site'),
                    onChanged: (siteId) {
                      if (siteId != null) {
                        final site = sites.firstWhere(
                          (s) => s.id == siteId,
                          orElse: () => sites.first,
                        );
                        onSiteChanged(site);
                      }
                    },
                    items: sites.map((site) {
                      return DropdownMenuItem(
                        value: site.id,
                        child: Text(site.name),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Date Range',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ActionChip(
                    label: Text('${dateFormat.format(start)} - ${dateFormat.format(end)}'),
                    avatar: const Icon(Icons.date_range, size: 18),
                    onPressed: onDateRangePressed,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
