import 'package:intl/intl.dart';
import 'readings_service.dart';

/// Service for centralizing formatting utilities across the application.
/// Reduces code duplication and ensures consistency in how data is displayed.
class FormattersService {
  // Singleton instance
  static final FormattersService _instance = FormattersService._internal();

  factory FormattersService() {
    return _instance;
  }

  FormattersService._internal();

  // Lazy initialization of dependencies
  late final ReadingsService _readingsService = ReadingsService();

  /// Format a reading alias (e.g., "soilMoisture") into display name
  /// Tries to get from ReadingsService first, falls back to camelCase conversion
  /// Example: "soilMoisture" -> "Soil Moisture"
  String formatReadingName(String alias) {
    // Try to get the display name from ReadingsService
    final reading = _readingsService.getReading(alias);
    if (reading != null) {
      return reading.name;
    }

    // Fallback: Convert camelCase to Title Case if reading not found
    if (alias.isEmpty) return alias;

    final words = alias.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );

    return words[0].toUpperCase() + words.substring(1);
  }

  /// Format a field/reading alias into display name
  /// Delegates to ReadingsService.formatFieldName
  /// Example: "temperature" -> "Temperature"
  String formatFieldName(String alias) {
    return _readingsService.formatFieldName(alias);
  }

  /// Format a DateTime into a relative time string
  /// Example: "2026-01-29 14:30:00" -> "2:30 PM" or "Jan 29, 2:30 PM"
  String formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    // If within last minute
    if (difference.inSeconds < 60) {
      return 'just now';
    }

    // If within last hour
    if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes minute${minutes > 1 ? 's' : ''} ago';
    }

    // If within last day
    if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours hour${hours > 1 ? 's' : ''} ago';
    }

    // If within last 7 days
    if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days day${days > 1 ? 's' : ''} ago';
    }

    // Otherwise, show formatted date and time
    return DateFormat('MMM dd, h:mm a').format(dateTime);
  }

  /// Format a DateTime to only show time (HH:mm or h:mm a)
  /// Example: "2026-01-29 14:30:00" -> "2:30 PM"
  String formatTime(DateTime dateTime) {
    return DateFormat('h:mm a').format(dateTime);
  }

  /// Format a DateTime to show date only
  /// Example: "2026-01-29 14:30:00" -> "Jan 29, 2026"
  String formatDate(DateTime dateTime) {
    return DateFormat('MMM dd, yyyy').format(dateTime);
  }

  /// Format a DateTime to show date and time
  /// Example: "2026-01-29 14:30:00" -> "Jan 29, 2:30 PM"
  String formatDateAndTime(DateTime dateTime) {
    return DateFormat('MMM dd, h:mm a').format(dateTime);
  }

  /// Format a double value with specified decimal places
  /// Example: 23.456789 with 2 decimals -> "23.46"
  String formatNumber(double value, {int decimals = 1}) {
    return value.toStringAsFixed(decimals);
  }

  /// Format a temperature value (typically 1 decimal place)
  /// Example: 23.456 -> "23.5°C"
  String formatTemperature(double value, {String unit = '°C'}) {
    return '${value.toStringAsFixed(1)}$unit';
  }

  /// Format a percentage value
  /// Example: 0.856 -> "85.6%"
  String formatPercentage(double value, {int decimals = 1}) {
    return '${(value * 100).toStringAsFixed(decimals)}%';
  }

  /// Format a duration
  /// Example: Duration(hours: 1, minutes: 30) -> "1h 30m"
  String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final parts = <String>[];
    if (hours > 0) parts.add('${hours}h');
    if (minutes > 0) parts.add('${minutes}m');
    if (seconds > 0 && hours == 0 && minutes < 10) parts.add('${seconds}s');

    return parts.isEmpty ? '0s' : parts.join(' ');
  }

  /// Format file size from bytes
  /// Example: 1024 -> "1.0 KB", 1048576 -> "1.0 MB"
  String formatFileSize(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();

    for (final suffix in suffixes) {
      if (size < 1024) {
        if (size < 10) {
          return '${size.toStringAsFixed(1)} $suffix';
        }
        return '${size.toStringAsFixed(0)} $suffix';
      }
      size /= 1024;
    }

    return '${size.toStringAsFixed(1)} PB';
  }
}
