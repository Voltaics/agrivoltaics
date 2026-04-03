import 'dart:html' as html;

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

      // On web, foreground messages are delivered to onMessage but do NOT
      // automatically show an OS notification — show one manually.
      if (kIsWeb) {
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          final title = message.notification?.title ?? 'Vinovoltaics Alert';
          final body = message.notification?.body ?? '';
          html.Notification(title, body: body, icon: '/icons/Icon-192.png');
        });
      }
    }

    return _permissionGranted;
  }

  /// Fetch the current FCM token and persist it (no permission prompt).
  Future<void> refreshToken() async {
    await _saveCurrentToken();
  }

  /// Check whether the user has granted notification permission without
  /// needing to fetch a token (safe to call before the VAPID key is set).
  Future<bool> checkPermissionStatus() async {
    final settings = await _messaging.getNotificationSettings();
    _permissionGranted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    return _permissionGranted;
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
      debugPrint('FCM token saved: ${token.substring(0, 20)}...');
    } else {
      debugPrint('FCM: getToken() returned null — check VAPID key and browser permissions');
    }
  }

  Future<void> _persistToken(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // Store as an array so a user can have tokens on multiple devices.
    // arrayUnion is idempotent — safe to call on every launch.
    await _firestore.doc('users/$uid').set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  /// VAPID key for web push (replace with the actual key from Firebase console
  /// Project Settings → Cloud Messaging → Web configuration).
  static const String _vapidKey =
      'BJC9Xd0dX9_wZZDwBKnxw1SvU7TzOI73LRp2bXsvz-231lowd-Gzaa_6oojJ04juy7MCJUi65ziEbz1CuPDj788';
}
