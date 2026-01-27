import 'dart:async';
import 'dart:convert';

import 'package:agrivoltaics_flutter_app/app_state.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/*

Notifications Drawer
- Drawer on Home page that extends from right side to display unread notifications

*/
class NotificationsDrawer extends StatefulWidget {
  const NotificationsDrawer({
    super.key
  });

  @override
  State<NotificationsDrawer> createState() => _NotificationsDrawerState();
}

class _NotificationsDrawerState extends State<NotificationsDrawer> {
  @override
  Widget build(BuildContext context) {
    AppState appState = context.read<AppState>();
    return Drawer(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              for (AppNotification notification in appState.notifications)...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Wrap(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(DateFormat('yyyy-MM-dd').format(notification.body.time)),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(notification.body.phenomenon),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(notification.body.significance),
                        )
                      ],
                    ),
                  )
                )
              ]
            ]
          ),
        )
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      AppState appState = context.read<AppState>();
      await readNotifications(FirebaseAuth.instance.currentUser?.email);
      appState.notifications = [];
      appState.finalizeState();
    });
  }
}

/*

Notifications Button
- Opens drawer containing notifications
- Alerts user if there are unread notifications

*/
class NotificationsButton extends StatefulWidget {
  const NotificationsButton({
    super.key,
  });

  @override
  State<NotificationsButton> createState() => _NotificationsButtonState();
}

class _NotificationsButtonState extends State<NotificationsButton> {
  bool newNotifications = false;
  
  @override
  Widget build(BuildContext context) {
    // Regularly refresh widget to check for new notifications
    Timer.periodic(const Duration(minutes: 1), (Timer t) {if (this.mounted) setState((){});});
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return FutureBuilder<List<AppNotification>>(
          future: getNotifications(FirebaseAuth.instance.currentUser?.email),
          builder: (BuildContext context, AsyncSnapshot<List<AppNotification>> snapshot) {
            if (snapshot.hasData) {
              appState.notifications = snapshot.data!;
              newNotifications = appState.notifications.isEmpty ? false : true;
            }
            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: IconButton(
                onPressed: () async {
                  Scaffold.of(context).openEndDrawer();
                },
                icon: Stack(
                  children: [
                    const Icon(
                      Icons.notifications,
                    ),
                    if (newNotifications)
                    const Positioned(
                      child: Icon(
                        Icons.brightness_1,
                        color: Colors.red,
                        size: 9.0
                      )
                    )
                  ]
                )
              ),
            );
          }
        );
      },
    );
  }
}

class AppNotificationBody {
  AppNotificationBody(this.phenomenon, this.significance, this.time);
  String phenomenon;
  String significance;
  DateTime time;

  factory AppNotificationBody.fromJson(Map<String, dynamic> json) {
    return AppNotificationBody(
      json['phenomenon'],
      json['significance'],
      DateTime.parse(json['time'].toString().split('/')[0])
    );
  }
}

class AppNotification {
  AppNotification(this.body, this.timestamp);
  AppNotificationBody body;
  DateTime timestamp;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      AppNotificationBody.fromJson(json['body']),
      DateTime.parse(json['timestamp'].toString().split('/')[0])
    );
  }
}

Future<List<AppNotification>> getNotifications(String? email) async {
  http.Response response = await http.get(Uri.parse('https://vinovoltaics-notification-api-6ajy6wk4ca-ul.a.run.app/getNotifications?email=$email'));
  List<AppNotification> notifications = [];
  if (response.statusCode == 200) {
    for (var notification in jsonDecode(response.body)['notifications']) {
      notifications.add(AppNotification.fromJson(notification));
    }
  }
  return notifications;
}

Future<void> readNotifications(String? email) async {
  await http.post(Uri.parse('https://vinovoltaics-notification-api-6ajy6wk4ca-ul.a.run.app/readNotifications?email=$email'));
  return;
}