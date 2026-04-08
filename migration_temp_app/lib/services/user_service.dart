import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user's document
  Future<AppUser?> getCurrentUser() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return null;
    
    final doc = await _firestore.doc('users/$userId').get();
    if (!doc.exists) return null;
    
    return AppUser.fromFirestore(doc);
  }

  // Stream current user's document
  Stream<AppUser?> getCurrentUserStream() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return Stream.value(null);
    
    return _firestore
        .doc('users/$userId')
        .snapshots()
        .map((doc) => doc.exists ? AppUser.fromFirestore(doc) : null);
  }

  // Get user by ID
  Future<AppUser?> getUser(String userId) async {
    final doc = await _firestore.doc('users/$userId').get();
    if (!doc.exists) return null;
    return AppUser.fromFirestore(doc);
  }

  // Create or update user document (call after authentication)
  Future<void> createOrUpdateUser({
    String? displayName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userDoc = await _firestore.doc('users/${user.uid}').get();

    if (!userDoc.exists) {
      // Create new user document
      await _firestore.doc('users/${user.uid}').set({
        'uid': user.uid,
        'email': user.email ?? '',
        'displayName': displayName ?? user.displayName ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      });
    } else {
      // Update existing user document
      final updates = <String, dynamic>{
        'lastLogin': FieldValue.serverTimestamp(),
      };
      
      if (displayName != null) updates['displayName'] = displayName;
      
      await _firestore.doc('users/${user.uid}').update(updates);
    }
  }

  // Update profile information
  Future<void> updateProfile({
    String? displayName,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    final updates = <String, dynamic>{};
    if (displayName != null) updates['displayName'] = displayName;

    if (updates.isNotEmpty) {
      await _firestore.doc('users/$userId').update(updates);
    }
  }

  // Delete user document
  Future<void> deleteUser() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    await _firestore.doc('users/$userId').delete();
  }

  // Check if user document exists
  Future<bool> userExists(String userId) async {
    final doc = await _firestore.doc('users/$userId').get();
    return doc.exists;
  }

  // Get multiple users by IDs
  Future<List<AppUser>> getUsers(List<String> userIds) async {
    if (userIds.isEmpty) return [];

    final docs = await Future.wait(
      userIds.map((id) => _firestore.doc('users/$id').get())
    );

    return docs
        .where((doc) => doc.exists)
        .map((doc) => AppUser.fromFirestore(doc))
        .toList();
  }
}
