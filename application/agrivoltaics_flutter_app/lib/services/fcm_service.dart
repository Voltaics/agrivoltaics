import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Manages Firebase Cloud Messaging (FCM) token registration.
///
/// On app start (or when the user visits the Alerts page) call
/// [requestPermissionAndSaveToken] to prompt for notification permission and
/// persist the token to `users/{uid}/fcmToken`.
///
/// The service also listens for token refreshes and re-persists automatically.
class FcmService {
  static final FcmService _instance = FcmService._internal();

  factory FcmService() => _instance;

  FcmService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Whether the user has granted notification permission.
  bool _permissionGranted = false;

  bool get isPermissionGranted => _permissionGranted;

  /// Request notification permission and, if granted, save the FCM token to
  /// Firestore.  Returns `true` if permission was granted.
  Future<bool> requestPermissionAndSaveToken() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    _permissionGranted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    if (_permissionGranted) {
      await _saveCurrentToken();

      // Refresh the token automatically when it rotates.
      _messaging.onTokenRefresh.listen((newToken) async {
        await _persistToken(newToken);
      });
    }

    return _permissionGranted;
  }

  /// Fetch the current FCM token and persist it (no permission prompt).
  Future<void> refreshToken() async {
    await _saveCurrentToken();
  }

  /// Returns the current FCM token, or null if unavailable.
  Future<String?> getToken() async {
    try {
      if (kIsWeb) {
        return await _messaging.getToken(
          vapidKey: _vapidKey,
        );
      }
      return await _messaging.getToken();
    } catch (_) {
      return null;
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<void> _saveCurrentToken() async {
    final token = await getToken();
    if (token != null) {
      await _persistToken(token);
    }
  }

  Future<void> _persistToken(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _firestore.doc('users/$uid').update({
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// VAPID key for web push (replace with the actual key from Firebase console
  /// Project Settings → Cloud Messaging → Web configuration).
  static const String _vapidKey =
      'REPLACE_WITH_YOUR_VAPID_KEY';
}
