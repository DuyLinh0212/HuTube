import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/features/account/account_settings_screen.dart';
import 'package:user_app/features/content/library_screen.dart';
import 'package:user_app/features/notifications/notification_center.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse, session;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'account requests run together and channel failure does not hide counts',
    (tester) async {
      final channel = Completer<http.Response>();
      final paths = <String>[];
      final client = MockClient((r) async {
        final path = r.url.path;
        if (path.endsWith('/auth/refresh')) return jsonResponse(session());
        paths.add(path);
        if (path.endsWith('/channels/me')) return channel.future;
        if (path.endsWith('/account/profile')) {
          return jsonResponse({'displayName': 'Profile'});
        }
        if (path.endsWith('/playlists')) {
          return http.Response(
            jsonEncode(List.generate(11, (i) => {'playlistId': '$i'})),
            200,
          );
        }
        if (path.endsWith('/subscriptions')) {
          return http.Response(
            jsonEncode(List.generate(17, (i) => {'channelId': '$i'})),
            200,
          );
        }
        return jsonResponse({
          'items': [],
          'total': 29,
          'page': 1,
          'pageSize': 20,
        });
      });
      final auth = AuthController(
        ApiClient(client: client),
        MemoryStore('refresh'),
      );
      await auth.restore();
      final notifications = NotificationCenter(auth);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: AccountSettingsScreen(auth: auth, notifications: notifications),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(paths.any((p) => p.endsWith('/account/profile')), isTrue);
      expect(paths.any((p) => p.endsWith('/library/liked')), isTrue);
      channel.complete(jsonResponse({'code': 'FAILED'}, 500));
      await tester.pumpAndSettle();
      expect(find.text('11'), findsOneWidget);
      expect(find.text('17'), findsOneWidget);
      expect(find.text('29'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      notifications.dispose();
      auth.dispose();
      client.close();
    },
  );
  testWidgets('liked library starts while history is still pending', (
    tester,
  ) async {
    final history = Completer<http.Response>();
    var liked = 0;
    final client = MockClient((r) async {
      if (r.url.path.endsWith('/auth/refresh')) return jsonResponse(session());
      if (r.url.path.endsWith('/history')) return history.future;
      if (r.url.path.endsWith('/liked')) liked++;
      return jsonResponse({'items': [], 'page': 1, 'pageSize': 20, 'total': 0});
    });
    final auth = AuthController(
      ApiClient(client: client),
      MemoryStore('refresh'),
    );
    await auth.restore();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: LibraryScreen(auth: auth)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(liked, 1);
    history.complete(
      jsonResponse({'items': [], 'page': 1, 'pageSize': 20, 'total': 0}),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    client.close();
  });
}
