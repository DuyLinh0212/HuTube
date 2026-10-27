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
import 'dart:io';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/features/content/content_models.dart';
import 'package:user_app/features/creator/video_frame_picker.dart';
import 'profile_links_parity_test.dart' show profileData, openPage;
import 'package:http/http.dart' as http;
import 'package:user_app/app/mobile_scaffold.dart';
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
      await tester.dragFrom(image.center, const Offset(-180, -120));
      await tester.pumpAndSettle();
      final moved = tester.getRect(
        find.byKey(const ValueKey('mini-player-video')),
      );
      expect(moved.left, lessThan(image.left));
      expect(moved.top, lessThan(image.top));
      expect(playback.minimized, isTrue);
      // Clamp large drags to the viewport and preserve tap-to-restore.
      await tester.dragFrom(moved.center, const Offset(-2000, -2000));
      await tester.pumpAndSettle();
      final clamped = tester.getRect(
        find.byKey(const ValueKey('mini-player-video')),
      );
      expect(clamped.left, greaterThanOrEqualTo(0));
      expect(clamped.top, greaterThanOrEqualTo(0));
      await tester.tapAt(clamped.topLeft + const Offset(8, 8));
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
        await tester.scrollUntilVisible(
          replyButton,
          80,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('watch-comments-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(replyButton);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('thread-reply-input')),
          'Phản hồi mới',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Gửi').last);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('thread-reply-input')),
          findsOneWidget,
        );
        expect(find.text('Phản hồi mới'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Đóng').last);
        await tester.pumpAndSettle();
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

  group('subscription notifications and frame selection', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      ApiClient.invalidateReadCache();
    });
    testWidgets('watch toggles notifications for an active subscription', (
      tester,
    ) async {
      var patches = 0;
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/channels/me')) return jsonResponse({}, 404);
        if (r.url.path.endsWith('/subscribe-status')) {
          return jsonResponse({
            'status': 'active',
            'notificationsEnabled': false,
          });
        }
        if (r.url.path.endsWith('/subscribe-notifications')) {
          patches++;
          expect(r.method, 'PATCH');
          expect(r.body, contains('"enabled":true'));
          return jsonResponse({'notificationsEnabled': true});
        }
        if (r.url.path.endsWith('/videos/video')) {
          return jsonResponse({
            'videoId': 'video',
            'channelId': 'other',
            'channelName': 'Channel',
            'channelHandle': 'other',
            'title': 'Video',
          });
        }
        return jsonResponse({'items': []});
      });
      final auth = AuthController(ApiClient(client: client), MemoryStore())
        ..user = profileData;
      final playback = PlaybackSession()
        ..videoId = 'video'
        ..ready = true;
      await tester.pumpWidget(
        MaterialApp(
          home: WatchScreen(auth: auth, playback: playback, videoId: 'video'),
        ),
      );
      await tester.pumpAndSettle();
      final bell = find.byKey(
        const ValueKey('watch-subscription-notifications'),
      );
      await tester.scrollUntilVisible(
        bell,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(bell);
      await tester.pumpAndSettle();
      expect(patches, 1);
      expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      playback.dispose();
      auth.dispose();
      client.close();
    });
    testWidgets(
      'thumbnail frame picker requests selected timestamp and keeps chosen file for upload',
      (tester) async {
        final root = (await tester.runAsync(() async {
          final directory = await Directory.systemTemp.createTemp(
            'dalitu-frames-',
          );
          for (final index in [1, 2]) {
            await File(
              'test/fixtures/thumbnail-frame.jpg',
            ).copy('${directory.path}/frame-$index.jpg');
          }
          return directory;
        }))!;
        final requested = <double>[];
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          const MethodChannel('hutube/media_tools'),
          (call) async {
            expect(call.method, 'extractFrame');
            requested.add((call.arguments['seconds'] as num).toDouble());
            return '${root.path}/frame-${requested.length}.jpg';
          },
        );
        final client = MockClient(
          (_) async => jsonResponse({
            'renditions': [
              {
                'quality': '720p',
                'height': 720,
                'url': 'https://media.test/video.mp4',
              },
            ],
          }),
        );
        final auth = AuthController(ApiClient(client: client), MemoryStore())
          ..user = profileData;
        await openPage(
          tester,
          VideoFramePicker(
            auth: auth,
            video: VideoDetail.fromJson({'videoId': 'video', 'duration': 120}),
          ),
        );
        await tester.pumpAndSettle();
        expect(requested, [0]);
        await tester.scrollUntilVisible(
          find.byType(Slider),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        final slider = tester.widget<Slider>(find.byType(Slider));
        slider.onChanged!(45);
        slider.onChangeEnd!(45);
        await tester.pumpAndSettle();
        expect(requested, [0, 45]);
        await tester.tap(
          find.widgetWithText(FilledButton, AppStrings.t('creator.useFrame')),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          expect(await File('${root.path}/frame-2.jpg').exists(), isTrue);
          expect(
            root.absolute.path.startsWith(
              '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}',
            ),
            isTrue,
          );
          await root.delete(recursive: true);
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        auth.dispose();
        client.close();
        messenger.setMockMethodCallHandler(
          const MethodChannel('hutube/media_tools'),
          null,
        );
      },
    );
  });

  group('mini-player back navigation', () {
    testWidgets('Back restores a minimized video after switching shell pages', (
      tester,
    ) async {
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
              GoRoute(path: '/home', builder: (_, _) => const Text('home')),
              GoRoute(
                path: '/explore',
                builder: (_, _) => const Text('explore'),
              ),
              GoRoute(
                path: '/watch/:videoId',
                builder: (_, state) =>
                    Text('watch:${state.pathParameters['videoId']}'),
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
    });
  });
}
