import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Public Firebase app identifiers are injected at build time. Server service
// account credentials must never be included in the APK.
class FirebasePush {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  bool ready = false;

  Future<bool> initialize() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return false;
    }
    try {
      Map<String, dynamic> values = {};
      try {
        if (defaultTargetPlatform == TargetPlatform.android) {
          values = Map<String, dynamic>.from(
            jsonDecode(
                  await rootBundle.loadString('assets/firebase.public.json'),
                )
                as Map,
          );
        }
      } catch (_) {
        /* Builds without Firebase assets keep push disabled. */
      }
      values.addAll({
        if (apiKey.isNotEmpty) 'FIREBASE_API_KEY': apiKey,
        if (appId.isNotEmpty) 'FIREBASE_APP_ID': appId,
        if (projectId.isNotEmpty) 'FIREBASE_PROJECT_ID': projectId,
        if (senderId.isNotEmpty) 'FIREBASE_MESSAGING_SENDER_ID': senderId,
      });
      if (!firebaseSettingsComplete(values)) return false;
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: values['FIREBASE_API_KEY'] as String,
            appId: values['FIREBASE_APP_ID'] as String,
            projectId: values['FIREBASE_PROJECT_ID'] as String,
            messagingSenderId: values['FIREBASE_MESSAGING_SENDER_ID'] as String,
            iosBundleId: const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
          ),
        );
      }
      // NotificationCenter presents one foreground alert, shared with SignalR.
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: false,
            badge: false,
            sound: false,
          );
      ready = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> token() => FirebaseMessaging.instance.getToken();
  Stream<String> get tokenChanges => FirebaseMessaging.instance.onTokenRefresh;
  Stream<Map<String, dynamic>> get messages =>
      FirebaseMessaging.onMessage.map(payload);
  Stream<Map<String, dynamic>> get opened =>
      FirebaseMessaging.onMessageOpenedApp.map(payload);
  Future<Map<String, dynamic>?> initialMessage() async {
    final message = await FirebaseMessaging.instance.getInitialMessage();
    return message == null ? null : payload(message);
  }

  static Map<String, dynamic> payload(RemoteMessage message) => {
    ...message.data,
    'title': message.notification?.title ?? message.data['title'] ?? 'Dalitu',
    'content': message.notification?.body ?? message.data['content'] ?? '',
  };
}

bool firebaseSettingsComplete(Map<String, dynamic> values) =>
    const [
      'FIREBASE_API_KEY',
      'FIREBASE_APP_ID',
      'FIREBASE_PROJECT_ID',
      'FIREBASE_MESSAGING_SENDER_ID',
    ].every(
      (key) =>
          values[key] is String && (values[key] as String).trim().isNotEmpty,
    );

// RabbitMQ/FCM/SignalR may redeliver after a connection interruption. Keep the
// inbox id stable and show just one local alert while this app is running.
class NotificationEventTracker {
  final _seen = <String>{};
  bool accept(Map<String, dynamic> item, String? userId) {
    final recipient = '${item['recipientId'] ?? ''}';
    if (userId == null || (recipient.isNotEmpty && recipient != userId)) {
      return false;
    }
    final id = '${item['notificationId'] ?? ''}';
    if (id.isEmpty) return true;
    if (!_seen.add(id)) return false;
    if (_seen.length > 256) _seen.remove(_seen.first);
    return true;
  }

  void clear() => _seen.clear();
}

// The server rotates session IDs on refresh. This value is only a client-side
// change detector; authorization remains on the server.
String? notificationSessionId(String? token) {
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token!.split('.')[1]))),
    );
    return payload is Map ? payload['sid'] as String? : null;
  } catch (_) {
    return null;
  }
}
