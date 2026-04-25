import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import '../../../services/formatters_service.dart';

/// Widget for displaying a single sensor reading card
class ReadingCard extends StatelessWidget {
  static const Duration _staleThreshold = Duration(minutes: 30);

  final String orgId;
  final String siteId;
  final String zoneId;
  final String readingName;
  final double? value;
  final String? unit;
  final DateTime? readingLastUpdated;
  final DateTime zoneDataDateTime;
  final bool isLoading;
  final String? error;

  const ReadingCard({
    required this.orgId,
    required this.siteId,
    required this.zoneId,
    required this.readingName,
    required this.value,
    required this.unit,
    required this.readingLastUpdated,
    required this.zoneDataDateTime,
    this.isLoading = false,
    this.error,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final formattersService = FormattersService();

    return _buildReadingCardUI(
      readingName,
      value,
      unit,
      formattersService,
      readingLastUpdated: readingLastUpdated,
      zoneDataDateTime: zoneDataDateTime,
      isLoading: isLoading,
      error: error,
    );
  }

  /// Build the UI for the reading card
  static Widget _buildReadingCardUI(
    String readingName,
    double? value,
    String? unit,
    FormattersService formattersService, {
    DateTime? readingLastUpdated,
    DateTime? zoneDataDateTime,
    bool isLoading = false,
    String? error,
  }) {
    final bool isStale = !isLoading &&
        error == null &&
        zoneDataDateTime != null &&
        (readingLastUpdated == null ||
            zoneDataDateTime.difference(readingLastUpdated) > _staleThreshold);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.scaffoldBackground),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Reading name
            Text(
              formattersService.formatReadingName(readingName),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),

            // Value and unit
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (error != null)
              Text(
                error,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              )
            else if (value != null)
              Row(
                children: [
                  if (isStale) ...[
                    Tooltip(
                      message: readingLastUpdated == null
                          ? 'Reading out of sync: this reading has no update timestamp.'
                          : 'Reading out of sync: last updated ${formattersService.formatDateAndTime(readingLastUpdated)}.',
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    formattersService.formatNumber(value),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textOnLight,
                    ),
                  ),
                  if (unit != null && unit.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(
                      unit,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              )
            else
              Row(
                children: [
                  if (isStale) ...[
                    Tooltip(
                      message: readingLastUpdated == null
                          ? 'Reading out of sync: this reading has no update timestamp.'
                          : 'Reading out of sync: last updated ${formattersService.formatDateAndTime(readingLastUpdated)}.',
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Text(
                    'No data',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
