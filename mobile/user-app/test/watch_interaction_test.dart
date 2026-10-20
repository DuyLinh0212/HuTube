import 'dart:async';
import 'dart:convert';

import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/features/content/mini_player.dart';
import 'package:user_app/features/content/playback_session.dart';
import 'package:user_app/features/content/watch_screen.dart';

import 'auth_test.dart' show MemoryStore, jsonResponse, session;

void main() {
  testWidgets(
    'tapping mini-player image restores watch route; close stays independent',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('native_video_player'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('native_video_player_controller_992'),
        (_) async => null,
      );
      final playback = PlaybackSession()
        ..player = NativeVideoPlayerController(id: 992)
        ..videoId = 'current'
        ..title = 'Current video'
        ..ready = true
        ..minimized = true;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Stack(
                children: [
                  const SizedBox.expand(),
                  MiniPlayer(session: playback),
                ],
              ),
            ),
          ),
          GoRoute(
            path: '/watch/:id',
            builder: (_, state) =>
                Scaffold(body: Text('Watching ${state.pathParameters['id']}')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      // Tap the image away from the close control and title, including its blank edge.
      final image = tester.getRect(
        find.byKey(const ValueKey('mini-player-video')),
      );
      await tester.tapAt(image.topLeft + const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('Watching current'), findsOneWidget);
      expect(playback.minimized, isFalse);
      router.go('/');
      playback.minimize();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Watching current'), findsNothing);
      expect(playback.minimized, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      playback.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('mini-player leaves feed scrolling and video taps reachable', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('native_video_player'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('native_video_player_controller_991'),
      (_) async => null,
    );
    final native = NativeVideoPlayerController(id: 991);
    final playback = PlaybackSession()
      ..player = native
      ..videoId = 'current'
      ..title = 'Current video'
      ..ready = true
      ..minimized = true;
    final scroll = ScrollController();
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              ListView.builder(
                controller: scroll,
                itemCount: 50,
                itemBuilder: (_, index) => ListTile(
                  title: Text('Video $index'),
                  onTap: () => selected = true,
                ),
              ),
              MiniPlayer(session: playback),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.dragFrom(const Offset(30, 250), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    await tester.tapAt(const Offset(40, 70));
    expect(selected, isTrue);
    expect(playback.minimized, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await playback.dismiss();
    playback.dispose();
    scroll.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  for (final viewport in [const Size(360, 780), const Size(640, 360)]) {
    testWidgets(
      'comments open separately, sort on API, paginate and send at $viewport',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final requests = <String>[];
        final recommendationGate = Completer<Map<String, dynamic>>();
        final auth = AuthController(
          ApiClient(
            client: MockClient((request) async {
              final path = request.url.path;
              requests.add('${request.method} ${request.url}');
              if (path.endsWith('/auth/refresh')) {
                return jsonResponse(session());
              }
              if (path.endsWith('/videos/video-a')) {
                return jsonResponse({
                  'videoId': 'video-a',
                  'channelId': 'channel-a',
                  'channelName': 'Kênh thử nghiệm',
                  'channelHandle': 'linh',
                  'title': 'Video đang xem',
                  'stats': {'comments': 21},
                });
              }
              if (path.contains('/feed/')) {
                return jsonResponse(await recommendationGate.future);
              }
              if (path.endsWith('/comments') && request.method == 'POST') {
                final body = jsonDecode(request.body) as Map;
                expect(
                  body['content'],
                  body['parentCommentId'] == null
                      ? 'Bình luận mới'
                      : 'Phản hồi mới',
                );
                return jsonResponse({
                  'commentId': 'new',
                  'videoId': 'video-a',
                  'displayName': 'Linh',
                  'content': body['content'],
                });
              }
              if (path.endsWith('/comments')) {
                final page = int.parse(request.url.queryParameters['page']!);
                return jsonResponse({
                  'items': [
                    for (
                      var i = (page - 1) * 20;
                      i < (page == 1 ? 20 : 21);
                      i++
                    )
                      {
                        'commentId': 'comment-$i',
                        'videoId': 'video-a',
                        'displayName': 'Người xem $i',
                        'content': 'Bình luận số $i',
                        'likes': i,
                      },
                  ],
                  'page': page,
                  'pageSize': 20,
                  'total': 21,
                });
              }
              return jsonResponse({});
            }),
          ),
          MemoryStore('refresh'),
        );
        await auth.restore();
        final playback = PlaybackSession()
          ..videoId = 'video-a'
          ..ready = true;
        final router = GoRouter(
          initialLocation: '/watch/video-a',
          routes: [
            GoRoute(
              path: '/watch/:id',
              builder: (_, _) => WatchScreen(
                auth: auth,
                playback: playback,
                videoId: 'video-a',
              ),
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        // A slow recommendation service must not delay the player and comments.
        expect(find.text('Video đang xem'), findsOneWidget);
        final preview = find.byKey(const ValueKey('watch-comments-preview'));
        await tester.scrollUntilVisible(
          preview,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byKey(const ValueKey('watch-comment-input')), findsNothing);
        await tester.tap(preview);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('watch-comments-list')),
          findsOneWidget,
        );
        expect(
          tester
              .getRect(find.byKey(const ValueKey('watch-comments-panel')))
              .top,
          greaterThanOrEqualTo(
            tester.getRect(find.byKey(const ValueKey('watch-player'))).bottom -
                1,
          ),
        );
        final newest = find.widgetWithText(ChoiceChip, 'Mới nhất');
        await tester.tap(newest);
        await tester.pumpAndSettle();
        expect(requests.any((r) => r.contains('sort=newest')), isTrue);
        final replyButton = find.widgetWithText(TextButton, 'Trả lời').first;
        await tester.ensureVisible(replyButton);
        await tester.pumpAndSettle();
        await tester.tap(replyButton);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('text-entry-input')),
          'Phản hồi mới',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Gửi'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('text-entry-input')), findsNothing);
        expect(find.text('Phản hồi mới'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final list = find
            .descendant(
              of: find.byKey(const ValueKey('watch-comments-list')),
              matching: find.byType(Scrollable),
            )
            .first;
        final more = find.widgetWithText(TextButton, 'Tải thêm');
        await tester.scrollUntilVisible(more, 250, scrollable: list);
        await tester.tap(more);
        await tester.pumpAndSettle();
        expect(requests.any((r) => r.contains('page=2')), isTrue);
        final input = find.byKey(const ValueKey('watch-comment-input'));
        await tester.tap(input);
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 160);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.enterText(input, 'Bình luận mới');
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Gửi'));
        await tester.pumpAndSettle();
        expect(
          requests.any((r) => r.startsWith('POST ') && r.contains('/comments')),
          isTrue,
        );
        await tester.tap(find.byKey(const ValueKey('watch-comments-close')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('watch-comments-list')), findsNothing);
        expect(tester.takeException(), isNull);
        recommendationGate.complete({
          'items': [],
          'page': 1,
          'pageSize': 20,
          'total': 0,
        });
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        playback.dispose();
        auth.dispose();
      },
    );
  }
}
