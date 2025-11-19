import 'package:cloud_firestore/cloud_firestore.dart';

/// Lookup table for sensor metadata
/// Document ID = sensorId
class SensorLookup {
  final String id; // Document ID = sensorId
  final String sensorDocPath;
  final String organizationId;
  final String siteId;
  final String zoneId;
  final String sensorId;
  final String sensorModel;
  final String sensorName;
  final List<String> fields; // Array of field names this sensor provides
  final bool isActive;
  final DateTime? lastDataReceived;
  final DateTime registeredAt;
  final DateTime updatedAt;

  SensorLookup({
    required this.id,
    required this.sensorDocPath,
    required this.organizationId,
    required this.siteId,
    required this.zoneId,
    required this.sensorId,
    required this.sensorModel,
    required this.sensorName,
    required this.fields,
    required this.isActive,
    this.lastDataReceived,
    required this.registeredAt,
    required this.updatedAt,
  });

  factory SensorLookup.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return SensorLookup(
      id: doc.id,
      sensorDocPath: data['sensorDocPath'] ?? '',
      organizationId: data['organizationId'] ?? '',
      siteId: data['siteId'] ?? '',
      zoneId: data['zoneId'] ?? '',
      sensorId: data['sensorId'] ?? '',
      sensorModel: data['sensorModel'] ?? '',
      sensorName: data['sensorName'] ?? '',
      fields: List<String>.from(data['fields'] ?? []),
      isActive: data['isActive'] ?? false,
      lastDataReceived: data['lastDataReceived'] != null
          ? (data['lastDataReceived'] as Timestamp).toDate()
          : null,
      registeredAt: (data['registeredAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'sensorDocPath': sensorDocPath,
      'organizationId': organizationId,
      'siteId': siteId,
      'zoneId': zoneId,
      'sensorId': sensorId,
      'sensorModel': sensorModel,
      'sensorName': sensorName,
      'fields': fields,
      'isActive': isActive,
      'lastDataReceived': lastDataReceived != null 
          ? Timestamp.fromDate(lastDataReceived!) 
          : null,
      'registeredAt': Timestamp.fromDate(registeredAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  SensorLookup copyWith({
    String? id,
    String? sensorDocPath,
    String? organizationId,
    String? siteId,
    String? zoneId,
    String? sensorId,
    String? sensorModel,
    String? sensorName,
    List<String>? fields,
    bool? isActive,
    DateTime? lastDataReceived,
    DateTime? updatedAt,
  }) {
    return SensorLookup(
      id: id ?? this.id,
      sensorDocPath: sensorDocPath ?? this.sensorDocPath,
      organizationId: organizationId ?? this.organizationId,
      siteId: siteId ?? this.siteId,
      zoneId: zoneId ?? this.zoneId,
      sensorId: sensorId ?? this.sensorId,
      sensorModel: sensorModel ?? this.sensorModel,
      sensorName: sensorName ?? this.sensorName,
      fields: fields ?? this.fields,
      isActive: isActive ?? this.isActive,
      lastDataReceived: lastDataReceived ?? this.lastDataReceived,
      registeredAt: registeredAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
