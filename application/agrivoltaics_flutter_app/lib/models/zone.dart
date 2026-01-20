import 'package:cloud_firestore/cloud_firestore.dart';

class Zone {
  final String id;
  final String name;
  final String description;
  final GeoPoint? location;
  final bool zoneChecked;
  final Map<String, String> readings; // Map of reading field name -> sensorId
  final DateTime createdAt;
  final DateTime updatedAt;

  Zone({
    required this.id,
    required this.name,
    required this.description,
    this.location,
    required this.zoneChecked,
    Map<String, String>? readings,
    required this.createdAt,
    required this.updatedAt,
  }) : readings = readings ?? {};

  // Convert from Firestore document
  factory Zone.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Zone(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      location: data['location'] as GeoPoint?,
      zoneChecked: data['zoneChecked'] ?? true,
      readings: data['readings'] != null
          ? Map<String, String>.from(data['readings'] as Map)
          : {},
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'location': location,
      'zoneChecked': zoneChecked,
      'readings': readings,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Zone copyWith({
    String? id,
    String? name,
    String? description,
    GeoPoint? location,
    bool? zoneChecked,
    Map<String, String>? readings,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Zone(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      location: location ?? this.location,
      zoneChecked: zoneChecked ?? this.zoneChecked,
      readings: readings ?? this.readings,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Helper method to get primary sensor for a reading type
  String? getPrimarySensor(String readingFieldName) {
    return readings[readingFieldName];
  }

  // Helper method to check if a reading type has a primary sensor
  bool hasReadingType(String readingFieldName) {
    return readings.containsKey(readingFieldName);
  }
}
