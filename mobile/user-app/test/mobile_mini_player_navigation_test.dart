import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:user_app/app/mobile_scaffold.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/features/content/playback_session.dart';
import 'package:user_app/features/notifications/notification_center.dart';

class _MemoryStore implements TokenStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String token) async {}

  @override
  Future<void> clear() async {}
}

class _FakePlaybackSession extends PlaybackSession {
  bool active = false;
  bool restored = false;

  @override
  bool get hasVideo => active;

  @override
  void restore() {
    restored = true;
    minimized = false;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'Back restores a minimized video after switching shell pages',
    (tester) async {
      final auth = AuthController(
        ApiClient(client: http.Client()),
        _MemoryStore(),
      );
      final playback = _FakePlaybackSession()
        ..active = true
        ..videoId = 'video-a'
        ..minimized = true;
      final notifications = NotificationCenter(auth);
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          ShellRoute(
            builder: (context, state, child) => MobileScaffold(
              auth: auth,
              playback: playback,
              notifications: notifications,
              location: state.uri.path,
              child: child,
            ),
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) => const Text('home'),
              ),
              GoRoute(
                path: '/explore',
                builder: (_, _) => const Text('explore'),
              ),
              GoRoute(
                path: '/watch/:videoId',
                builder: (_, state) => Text(
                  'watch:${state.pathParameters['videoId']}',
                ),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.go('/explore');
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(playback.restored, isTrue);
      expect(router.state.uri.path, '/watch/video-a');
      expect(find.text('watch:video-a'), findsOneWidget);
    },
  );
}
