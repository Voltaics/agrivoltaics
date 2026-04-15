import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ─── Legacy types kept for AppState backward compatibility ───────────────────

class AppNotificationBody {
  AppNotificationBody(this.phenomenon, this.significance, this.time);
  String phenomenon;
  String significance;
  DateTime time;
}

class AppNotification {
  AppNotification(this.body, this.timestamp);
  AppNotificationBody body;
  DateTime timestamp;
}

// ─── Firestore notification model ────────────────────────────────────────────

class FirestoreNotification {
  final String id;
  final String title;
  final String body;
  final String type; // 'alert' | 'system'
  final bool isRead;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const FirestoreNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.expiresAt,
  });

  factory FirestoreNotification.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FirestoreNotification(
      id: doc.id,
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      type: data['type'] as String? ?? 'alert',
      isRead: data['isRead'] as bool? ?? false,
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
    );
  }
}

// ─── Firestore stream helper ──────────────────────────────────────────────────

Stream<List<FirestoreNotification>> notificationsStream(String userId) {
  return FirebaseFirestore.instance
      .collection('notifications')
      .where('userId', isEqualTo: userId)
      .snapshots()
      .map((snap) {
        final list = snap.docs
            .map(FirestoreNotification.fromFirestore)
            .where((n) =>
                n.expiresAt == null ||
                n.expiresAt!.isAfter(DateTime.now()))
            .toList();
        // Sort client-side — avoids needing a composite index
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });
}

Future<void> markNotificationRead(String notificationId) async {
  await FirebaseFirestore.instance
      .doc('notifications/$notificationId')
      .update(
          {'isRead': true, 'readAt': FieldValue.serverTimestamp()});
}

// ─── Notifications button with unread badge ───────────────────────────────────

/// Bell icon with a red unread-count badge. Place in the sidebar above Sign Out.
class NotificationsButton extends StatelessWidget {
  final Color iconColor;

  const NotificationsButton({
    super.key,
    this.iconColor = AppColors.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<List<FirestoreNotification>>(
      stream: notificationsStream(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('NotificationsButton stream error: ${snapshot.error}');
        }
        final items = snapshot.data ?? [];
        final unread = items.where((n) => !n.isRead).length;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Notifications',
              icon: Icon(Icons.notifications, color: iconColor),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    NotificationsDialog(notifications: items),
              ),
            ),
            if (unread > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                      minWidth: 16, minHeight: 16),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─── Notifications dialog ─────────────────────────────────────────────────────

class NotificationsDialog extends StatelessWidget {
  final List<FirestoreNotification> notifications;
  const NotificationsDialog({super.key, required this.notifications});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screenSize.width < 520 ? screenSize.width * 0.92 : 480,
          maxHeight: screenSize.height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.notifications,
                      color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Notifications',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textOnLight)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(),
            Flexible(
              child: notifications.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none,
                              size: 48,
                              color: AppColors.textMuted),
                          SizedBox(height: 12),
                          Text('No notifications',
                              style: TextStyle(
                                  color: AppColors.textMuted)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding:
                          const EdgeInsets.symmetric(vertical: 8),
                      itemCount: notifications.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (context, i) =>
                          _NotificationTile(
                              notification: notifications[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Individual notification tile ─────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  final FirestoreNotification notification;
  const _NotificationTile({required this.notification});

  Color get _accentColor => notification.type == 'system'
      ? AppColors.warning
      : AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: notification.isRead
          ? null
          : () => markNotificationRead(notification.id),
      child: Container(
        decoration: BoxDecoration(
          color: notification.isRead
              ? null
              : AppColors.primary.withAlpha(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 4, height: 72, color: _accentColor),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontWeight: notification.isRead
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                              color: AppColors.textOnLight,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          DateFormat('MMM d, h:mm a')
                              .format(notification.createdAt),
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!notification.isRead)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () =>
                              markNotificationRead(notification.id),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Mark as read',
                              style: TextStyle(fontSize: 11)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

