import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/notifications/firebase_push.dart';

void main() {
  test(
    'session rotation is detected without treating the JWT as authorization',
    () {
      String token(String sid) =>
          'header.${base64Url.encode(utf8.encode(jsonEncode({'sid': sid})))}.signature';
      expect(notificationSessionId(token('old-session')), 'old-session');
      expect(notificationSessionId(token('new-session')), 'new-session');
      expect(notificationSessionId('invalid-token'), isNull);
      expect(notificationSessionId(null), isNull);
    },
  );
  test('one local alert for duplicate SignalR and FCM inbox ids', () {
    final tracker = NotificationEventTracker();
    final item = {'notificationId': 'stable-inbox-id', 'recipientId': 'alice'};
    expect(tracker.accept(item, 'alice'), isTrue);
    expect(tracker.accept(item, 'alice'), isFalse);
    tracker.clear();
    expect(tracker.accept(item, 'alice'), isTrue);
  });
  test('old account messages are ignored after logout or account switch', () {
    final tracker = NotificationEventTracker();
    final item = {'notificationId': 'private-id', 'recipientId': 'alice'};
    expect(tracker.accept(item, null), isFalse);
    expect(tracker.accept(item, 'bob'), isFalse);
    expect(tracker.accept(item, 'alice'), isTrue);
  });
  test('normalizes Firebase notification and routing data', () {
    final item = FirebasePush.payload(
      const RemoteMessage(
        data: {
          'notificationId': 'id',
          'actionUrl': '/watch/video',
          'recipientId': 'alice',
        },
        notification: RemoteNotification(
          title: 'New video',
          body: 'Video title',
        ),
      ),
    );
    expect(item['notificationId'], 'id');
    expect(item['actionUrl'], '/watch/video');
    expect(item['title'], 'New video');
    expect(item['content'], 'Video title');
  });
  test('FCM stays optional without complete public app configuration', () {
    expect(firebaseSettingsComplete({}), isFalse);
    expect(
      firebaseSettingsComplete({'FIREBASE_PROJECT_ID': 'project'}),
      isFalse,
    );
    expect(
      firebaseSettingsComplete({
        'FIREBASE_API_KEY': 'public-key',
        'FIREBASE_APP_ID': 'app',
        'FIREBASE_PROJECT_ID': 'project',
        'FIREBASE_MESSAGING_SENDER_ID': '123',
      }),
      isTrue,
    );
  });
}
