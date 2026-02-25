import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/training_image.dart';

class ImageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── Firestore path helper ───────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> _col(String orgId) =>
      _firestore.collection('organizations/$orgId/trainingImages');

  // ── Queries ─────────────────────────────────────────────────────────

  /// Stream of all training images for an organization, newest first.
  Stream<List<TrainingImage>> getImages(String orgId) {
    return _col(orgId)
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => TrainingImage.fromFirestore(d)).toList());
  }

  /// Returns every distinct label used across all images in the organization.
  Stream<List<String>> getAvailableLabels(String orgId) {
    return getImages(orgId).map((images) {
      final labels = <String>{};
      for (final img in images) {
        labels.addAll(img.labels);
      }
      final sorted = labels.toList()..sort();
      return sorted;
    });
  }

  // ── Upload ───────────────────────────────────────────────────────────

  /// Uploads [bytes] to Firebase Storage and saves metadata to Firestore.
  /// Returns the created [TrainingImage].
  Future<TrainingImage> uploadImage({
    required String orgId,
    required Uint8List bytes,
    required String fileName,
    required List<String> labels,
    String? notes,
    String? siteId,
    String? zoneId,
  }) async {
    final userId = _auth.currentUser!.uid;

    // Generate a Firestore doc ID first so Storage and Firestore share the same key.
    final docRef = _col(orgId).doc();
    final imageId = docRef.id;

    // Derive a safe content type from the file extension.
    final ext = fileName.split('.').last.toLowerCase();
    final contentType = _contentTypeFor(ext);

    final storagePath = 'organizations/$orgId/training-images/$imageId';
    final storageRef = _storage.ref(storagePath);

    // Upload bytes.
    final uploadTask = await storageRef.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );

    final downloadUrl = await uploadTask.ref.getDownloadURL();

    final image = TrainingImage(
      id: imageId,
      organizationId: orgId,
      storagePath: storagePath,
      downloadUrl: downloadUrl,
      fileName: fileName,
      labels: labels,
      uploadedBy: userId,
      uploadedAt: DateTime.now(),
      notes: notes,
      siteId: siteId,
      zoneId: zoneId,
    );

    await docRef.set(image.toFirestore());
    return image;
  }

  // ── Update ───────────────────────────────────────────────────────────

  /// Updates the labels (and optional notes) of an existing image.
  Future<void> updateImage(
    String orgId,
    String imageId, {
    List<String>? labels,
    String? notes,
  }) async {
    final updates = <String, dynamic>{};
    if (labels != null) updates['labels'] = labels;
    if (notes != null) updates['notes'] = notes;
    if (updates.isNotEmpty) {
      await _col(orgId).doc(imageId).update(updates);
    }
  }

  // ── Delete ───────────────────────────────────────────────────────────

  /// Deletes the image from both Firebase Storage and Firestore.
  Future<void> deleteImage(String orgId, String imageId, String storagePath) async {
    await _storage.ref(storagePath).delete();
    await _col(orgId).doc(imageId).delete();
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  String _contentTypeFor(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }
}
