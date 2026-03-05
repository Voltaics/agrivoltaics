import 'package:cloud_firestore/cloud_firestore.dart';

class Zone {
  final String id;
  final String name;
  final String description;
  final GeoPoint? location;
  final bool zoneChecked;
  final DateTime createdAt;
  final DateTime updatedAt;

  Zone({
    required this.id,
    required this.name,
    required this.description,
    this.location,
    required this.zoneChecked,
    required this.createdAt,
    required this.updatedAt,
  });

  // Convert from Firestore document
  factory Zone.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Zone(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      location: data['location'] as GeoPoint?,
      zoneChecked: data['zoneChecked'] ?? true,
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
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Zone(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      location: location ?? this.location,
      zoneChecked: zoneChecked ?? this.zoneChecked,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
