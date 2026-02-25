import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a training image stored in Firebase Storage with metadata in Firestore.
///
/// Storage path: organizations/{organizationId}/training-images/{id}
/// Firestore path: organizations/{organizationId}/trainingImages/{id}
class TrainingImage {
  final String id;
  final String organizationId;

  /// Firebase Storage path for the image file.
  final String storagePath;

  /// Cached public download URL (nullable — fetched on first use).
  final String? downloadUrl;

  final String fileName;

  /// User-defined labels used for filtering and ML model training.
  final List<String> labels;

  final String uploadedBy;
  final DateTime uploadedAt;

  /// Optional free-text notes about the image.
  final String? notes;

  final String? siteId;
  final String? zoneId;

  TrainingImage({
    required this.id,
    required this.organizationId,
    required this.storagePath,
    this.downloadUrl,
    required this.fileName,
    required this.labels,
    required this.uploadedBy,
    required this.uploadedAt,
    this.notes,
    this.siteId,
    this.zoneId,
  });

  factory TrainingImage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TrainingImage(
      id: doc.id,
      organizationId: data['organizationId'] ?? '',
      storagePath: data['storagePath'] ?? '',
      downloadUrl: data['downloadUrl'],
      fileName: data['fileName'] ?? '',
      labels: List<String>.from(data['labels'] ?? []),
      uploadedBy: data['uploadedBy'] ?? '',
      uploadedAt: (data['uploadedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notes: data['notes'],
      siteId: data['siteId'],
      zoneId: data['zoneId'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'organizationId': organizationId,
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'fileName': fileName,
      'labels': labels,
      'uploadedBy': uploadedBy,
      'uploadedAt': Timestamp.fromDate(uploadedAt),
      'notes': notes,
      'siteId': siteId,
      'zoneId': zoneId,
    };
  }

  TrainingImage copyWith({
    String? downloadUrl,
    List<String>? labels,
    String? notes,
  }) {
    return TrainingImage(
      id: id,
      organizationId: organizationId,
      storagePath: storagePath,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      fileName: fileName,
      labels: labels ?? this.labels,
      uploadedBy: uploadedBy,
      uploadedAt: uploadedAt,
      notes: notes ?? this.notes,
      siteId: siteId,
      zoneId: zoneId,
    );
  }
}
