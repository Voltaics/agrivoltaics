import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a field/output from a sensor (e.g., temperature, humidity)
class SensorField {
  final double? currentValue;
  final String unit;
  final DateTime? lastUpdated;

  SensorField({
    this.currentValue,
    required this.unit,
    this.lastUpdated,
  });

  factory SensorField.fromMap(Map<String, dynamic> map) {
    return SensorField(
      currentValue: map['currentValue']?.toDouble(),
      unit: map['unit'] ?? '',
      lastUpdated: map['lastUpdated'] != null
          ? (map['lastUpdated'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'currentValue': currentValue,
      'unit': unit,
      'lastUpdated': lastUpdated != null ? Timestamp.fromDate(lastUpdated!) : null,
    };
  }

  SensorField copyWith({
    double? currentValue,
    String? unit,
    DateTime? lastUpdated,
  }) {
    return SensorField(
      currentValue: currentValue ?? this.currentValue,
      unit: unit ?? this.unit,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

/// Sensor document - represents a physical sensor with multiple output fields
class Sensor {
  final String id;
  final String name;
  final String model;
  final GeoPoint? location;
  final Map<String, SensorField> fields; // e.g., {"temperature": {...}, "humidity": {...}}
  final String status; // "active" | "inactive" | "maintenance" | "error"
  final bool isOnline;
  final DateTime? lastReading;
  final DateTime createdAt;
  final DateTime updatedAt;

  Sensor({
    required this.id,
    required this.name,
    required this.model,
    this.location,
    required this.fields,
    required this.status,
    required this.isOnline,
    this.lastReading,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Sensor.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Parse fields map
    final fieldsMap = <String, SensorField>{};
    if (data['fields'] != null) {
      final rawFields = data['fields'] as Map<String, dynamic>;
      rawFields.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          fieldsMap[key] = SensorField.fromMap(value);
        }
      });
    }

    return Sensor(
      id: doc.id,
      name: data['name'] ?? '',
      model: data['model'] ?? '',
      location: data['location'] as GeoPoint?,
      fields: fieldsMap,
      status: data['status'] ?? 'inactive',
      isOnline: data['isOnline'] ?? false,
      lastReading: data['lastReading'] != null
          ? (data['lastReading'] as Timestamp).toDate()
          : null,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    // Convert fields map to Firestore format
    final fieldsMap = <String, dynamic>{};
    fields.forEach((key, value) {
      fieldsMap[key] = value.toMap();
    });

    return {
      'name': name,
      'model': model,
      'location': location,
      'fields': fieldsMap,
      'status': status,
      'isOnline': isOnline,
      'lastReading': lastReading != null ? Timestamp.fromDate(lastReading!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Sensor copyWith({
    String? name,
    String? model,
    GeoPoint? location,
    Map<String, SensorField>? fields,
    String? status,
    bool? isOnline,
    DateTime? lastReading,
    DateTime? updatedAt,
  }) {
    return Sensor(
      id: id,
      name: name ?? this.name,
      model: model ?? this.model,
      location: location ?? this.location,
      fields: fields ?? this.fields,
      status: status ?? this.status,
      isOnline: isOnline ?? this.isOnline,
      lastReading: lastReading ?? this.lastReading,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
