import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';

typedef OnDateRangeApplied = void Function(PickerDateRange range);

void showDateRangePickerDialog(
  BuildContext context, {
  required PickerDateRange initialRange,
  required OnDateRangeApplied onApplied,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      PickerDateRange tempRange = initialRange;
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'Select date range',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 1),
            SizedBox(
              height: 360,
              child: SfDateRangePicker(
                selectionMode: DateRangePickerSelectionMode.range,
                initialSelectedRange: initialRange,
                maxDate: DateTime.now(),
                onSelectionChanged: (args) {
                  if (args.value is PickerDateRange) {
                    tempRange = args.value;
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final start = tempRange.startDate;
                  // endDate is null when the user tapped only one day in the
                  // range picker (first tap sets start, second tap sets end).
                  // Treat a null end as a same-day selection.
                  final end = tempRange.endDate ?? tempRange.startDate;

                  if (start != null && end != null) {
                    final now = DateTime.now();
                    final today = DateTime(now.year, now.month, now.day);
                    
                    // Normalize start to beginning of day (00:00:00)
                    final normalizedStart = DateTime(start.year, start.month, start.day);
                    
                    // Normalize end based on whether it's today or not
                    final endDate = DateTime(end.year, end.month, end.day);
                    final DateTime normalizedEnd;
                    
                    if (endDate.isAtSameMomentAs(today)) {
                      // End date is today - use current time
                      normalizedEnd = now;
                    } else {
                      // End date is not today - use end of day (23:59:59)
                      normalizedEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);
                    }
                    
                    final normalizedRange = PickerDateRange(normalizedStart, normalizedEnd);
                    onApplied(normalizedRange);
                  } else {
                    onApplied(tempRange);
                  }
                  
                  Navigator.pop(context);
                },
                child: const Text('Apply range'),
              ),
            ),
          ],
        ),
      );
    },
  );
}
