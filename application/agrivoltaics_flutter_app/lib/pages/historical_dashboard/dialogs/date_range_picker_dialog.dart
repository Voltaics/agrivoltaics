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
    backgroundColor: Colors.white,
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
                  onApplied(tempRange);
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
