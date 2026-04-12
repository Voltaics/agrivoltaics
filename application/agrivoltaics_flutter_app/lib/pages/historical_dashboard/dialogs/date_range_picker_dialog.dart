import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';

typedef OnDateRangeApplied = void Function(PickerDateRange range);
final now = DateTime.now();
final minAllowedDate = DateTime(now.year, now.month - 3, now.day);

void showDateRangePickerDialog(
  BuildContext context, {
  required PickerDateRange initialRange,
  required OnDateRangeApplied onApplied,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      PickerDateRange tempRange = initialRange;
      final media = MediaQuery.of(context);
      final isLandscape = media.orientation == Orientation.landscape;
      final sheetHeight = media.size.height * (isLandscape ? 0.95 : 0.8);

      return SizedBox(
        height: sheetHeight,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
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
              Expanded(
                child: SfDateRangePicker(
                  selectionMode: DateRangePickerSelectionMode.range,
                  initialSelectedRange: initialRange,
                  minDate: minAllowedDate,
                  maxDate: now,
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
                    final end = tempRange.endDate ?? tempRange.startDate;

                    if (start != null && end != null) {
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);

                      final normalizedStart = DateTime(start.year, start.month, start.day);
                      final clampedStart = normalizedStart.isBefore(minAllowedDate)
                          ? minAllowedDate
                          : normalizedStart;

                      final endDate = DateTime(end.year, end.month, end.day);
                      final DateTime normalizedEnd;

                      if (endDate.isAtSameMomentAs(today)) {
                        normalizedEnd = now;
                      } else {
                        normalizedEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);
                      }

                      final normalizedRange = PickerDateRange(clampedStart, normalizedEnd);
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
        ),
      );
    },
  );
}
