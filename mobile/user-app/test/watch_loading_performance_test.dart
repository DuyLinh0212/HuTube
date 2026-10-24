import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/features/content/content_service.dart';
import 'package:user_app/features/content/playback_session.dart';
import 'package:user_app/features/content/watch_screen.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse, session;

void main() {
  test('slow inference uses catalogue within the watch budget', () async {
    final ranking = Completer<http.Response>();
    var resolved = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        return jsonResponse(session());
      }
      if (request.url.path.endsWith('/feed/recommended')) return ranking.future;
      expect(request.url.path, endsWith('/feed/resolve'));
      resolved++;
      return jsonResponse({
        'items': [
          {'videoId': 'fallback'},
        ],
        'page': 1,
        'pageSize': 20,
        'total': 1,
      });
    });
    final auth = AuthController(
      ApiClient(client: client),
      MemoryStore('refresh'),
    );
    await auth.restore();
    final watch = ContentService(
      auth,
      recommendationApi: ApiClient(client: client),
    );
    final result = await watch
        .feed(
          explore: false,
          recommendationBudget: const Duration(milliseconds: 20),
        )
        .timeout(const Duration(seconds: 1));
    expect(result.items.single.id, 'fallback');
    expect(resolved, 1);
    ranking.complete(jsonResponse({'items': []}));
    auth.dispose();
    client.close();
  });

  testWidgets(
    'watch starts suggestions before playback finishes and caches filters on the left',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pendingPlayback = Completer<http.Response>();
      var feedCalls = 0, channelCalls = 0;
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/videos/video')) {
          return jsonResponse({
            'videoId': 'video',
            'channelId': 'channel',
            'title': 'Video',
          });
        }
        if (path.endsWith('/playback')) return pendingPlayback.future;
        if (path.endsWith('/feed/home')) feedCalls++;
        if (path.endsWith('/videos/search')) channelCalls++;
        return jsonResponse({
          'items': [
            {'videoId': 'other', 'title': 'Other'},
          ],
          'page': 1,
          'total': 1,
        });
      });
      final auth = AuthController(ApiClient(client: client), MemoryStore())
        ..restoring = false;
      final playback = PlaybackSession()
        ..videoId = 'video'
        ..ready = true;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                WatchScreen(auth: auth, playback: playback, videoId: 'video'),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        feedCalls,
        1,
        reason: 'Recommendations must not wait for playback metadata',
      );
      pendingPlayback.complete(jsonResponse({}));
      await tester.pumpAndSettle();
      final all = find.widgetWithText(ChoiceChip, AppStrings.t('parity.all'));
      final channel = find.widgetWithText(
        ChoiceChip,
        AppStrings.t('parity.channel'),
      );
      await tester.scrollUntilVisible(
        all,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.getTopLeft(all).dx, 20);
      await tester.tap(channel);
      await tester.pumpAndSettle();
      await tester.tap(all);
      await tester.pumpAndSettle();
      await tester.tap(channel);
      await tester.pumpAndSettle();
      expect(feedCalls, 1);
      expect(channelCalls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      playback.dispose();
      auth.dispose();
      client.close();
    },
  );
}
