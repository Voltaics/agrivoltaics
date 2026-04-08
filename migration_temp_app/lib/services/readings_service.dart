import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for a reading definition
class Reading {
  final String alias;
  final String name;
  final String description;
  final List<String> validUnits;
  final String defaultUnit;

  Reading({
    required this.alias,
    required this.name,
    required this.description,
    required this.validUnits,
    required this.defaultUnit,
  });

  factory Reading.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Reading(
      alias: data['alias'] ?? '',
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      validUnits: List<String>.from(data['validUnits'] ?? []),
      defaultUnit: data['defaultUnit'] ?? '',
    );
  }
}

/// Service for managing reading definitions
/// Caches readings in memory after first load since they change infrequently
class ReadingsService {
  static final ReadingsService _instance = ReadingsService._internal();
  
  factory ReadingsService() {
    return _instance;
  }
  
  ReadingsService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, Reading> _cache = {};
  bool _isLoaded = false;

  /// Load all readings into cache
  Future<void> loadReadings() async {
    if (_isLoaded) return; // Already loaded
    
    try {
      final snapshot = await _firestore.collection('readings').get();
      _cache = {};
      for (final doc in snapshot.docs) {
        final reading = Reading.fromFirestore(doc);
        _cache[reading.alias] = reading;
      }
      _isLoaded = true;
    } catch (e) {
      print('Error loading readings: $e');
      _isLoaded = false;
    }
  }

  /// Get reading definition by alias
  Reading? getReading(String alias) {
    return _cache[alias];
  }

  /// Get reading display name by alias
  /// Falls back to alias if reading not found
  String getReadingName(String alias) {
    return _cache[alias]?.name ?? alias;
  }

  /// Get valid units for a reading
  List<String> getValidUnits(String alias) {
    return _cache[alias]?.validUnits ?? [];
  }

  /// Get default unit for a reading
  String getDefaultUnit(String alias) {
    return _cache[alias]?.defaultUnit ?? '';
  }

  /// Check if alias is valid
  bool isValidAlias(String alias) {
    return _cache.containsKey(alias);
  }

  /// Get all readings
  Map<String, Reading> getAllReadings() {
    return Map.unmodifiable(_cache);
  }

  /// Clear cache (useful for testing or forcing reload)
  void clearCache() {
    _cache.clear();
    _isLoaded = false;
  }

  /// Check if readings are loaded
  bool get isLoaded => _isLoaded;

  /// Format a reading alias to display name
  /// Uses cached readings to get the proper name
  String formatFieldName(String alias) {
    return getReadingName(alias);
  }
}
