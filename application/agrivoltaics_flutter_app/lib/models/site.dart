import 'package:cloud_firestore/cloud_firestore.dart';

class Site {
  final String id;
  final String name;
  final String description;
  final GeoPoint? location;
  final String address;
  final String timezone;
  final DateTime? lastDataReceived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final bool siteChecked;

  Site({
    required this.id,
    required this.name,
    required this.description,
    this.location,
    required this.address,
    required this.timezone,
    this.lastDataReceived,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.siteChecked,
  });

  // Convert from Firestore document
  factory Site.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Site(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      location: data['location'] as GeoPoint?,
      address: data['address'] ?? '',
      timezone: data['timezone'] ?? 'America/New_York',
      lastDataReceived: (data['lastDataReceived'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      siteChecked: data['siteChecked'] ?? true,
    );
  }

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'location': location,
      'address': address,
      'timezone': timezone,
      'lastDataReceived': lastDataReceived != null 
          ? Timestamp.fromDate(lastDataReceived!) 
          : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdBy': createdBy,
      'siteChecked': siteChecked,
    };
  }

  Site copyWith({
    String? id,
    String? name,
    String? description,
    GeoPoint? location,
    String? address,
    String? timezone,
    DateTime? lastDataReceived,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    bool? siteChecked,
  }) {
    return Site(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      location: location ?? this.location,
      address: address ?? this.address,
      timezone: timezone ?? this.timezone,
      lastDataReceived: lastDataReceived ?? this.lastDataReceived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      siteChecked: siteChecked ?? this.siteChecked,
    );
  }
}
