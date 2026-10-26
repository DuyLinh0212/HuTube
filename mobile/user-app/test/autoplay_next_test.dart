import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/features/content/content_models.dart';
import 'package:user_app/features/content/media_entitlements.dart';
import 'package:user_app/features/content/playback_session.dart';
import 'package:user_app/features/content/watch_screen.dart';
import 'package:user_app/features/content/widgets/autoplay_next_notice.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse;
import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:user_app/features/content/video_card.dart';

class _UnusedNativeController implements NativeVideoPlayerController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingPlayback extends PlaybackSession {
  final opened = <(String, bool, int)>[];
  @override
  Future<NativeVideoPlayerController> start({
    required AuthController auth,
    required VideoDetail video,
    required List<Rendition> videoRenditions,
    required MediaEntitlements mediaEntitlements,
    required String sourceUrl,
    required int resumeAt,
  }) async {
    videoId = video.id;
    ready = false;
    return _UnusedNativeController();
  }

  @override
  Future<void> initialize(
    String url, {
    required int resumeAt,
    bool playWhenReady = false,
  }) async {
    opened.add((videoId!, playWhenReady, resumeAt));
    ready = true;
    notifyListeners();
  }
}

Map<String, dynamic> _video(String id) => {
  'videoId': id,
  'title': 'Video $id',
  'channelName': 'Channel',
  'videoUrl': 'https://video.test/$id',
  'duration': 100,
};

class IntentPlayback extends PlaybackSession {
  int intent = 0;
  @override
  int get playbackIntentGeneration => intent;
  void simulateSeek() {
    intent++;
    notifyListeners();
  }
}

Map<String, dynamic> video(String id) => {
  'videoId': id,
  'title': 'Video $id',
  'channelName': 'Channel',
  'duration': 100,
  'videoUrl': 'https://video.test/$id',
};

void main() {
  setUp(() {
    ApiClient.invalidateReadCache();
    FlutterSecureStorage.setMockInitialValues({});
  });
  for (final action in [
    'advance',
    'native-reset',
    'cancel',
    'disable',
    'seek',
    'leave',
    'dispose',
  ]) {
    testWidgets('autoplay notice: $action', (tester) async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/videos/current')) {
          return jsonResponse(video('current'));
        }
        return jsonResponse({
          'items': [video('next')],
          'total': 1,
        });
      });
      final auth = AuthController(ApiClient(client: client), MemoryStore())
        ..restoring = false;
      final playback = IntentPlayback()
        ..videoId = 'current'
        ..ready = true
        ..duration = const Duration(seconds: 100)
        ..position = const Duration(seconds: 100);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                WatchScreen(auth: auth, playback: playback, videoId: 'current'),
          ),
          GoRoute(
            path: '/watch/:id',
            builder: (_, _) => const Scaffold(body: Text('Next video')),
          ),
          GoRoute(
            path: '/elsewhere',
            builder: (_, _) => const Scaffold(body: Text('Elsewhere')),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
      );
      await tester.pumpAndSettle();
      playback.onVideoCompleted!();
      await tester.pump();
      expect(find.byType(AutoplayNextNotice), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      playback
          .onVideoCompleted!(); // Duplicate completion must not restart timer.
      if (action == 'cancel') {
        await tester.tap(
          find.widgetWithText(TextButton, AppStrings.t('common.cancel')),
        );
        expect(playback.autoplayNext, isTrue);
      } else if (action == 'disable') {
        playback.toggleAutoplay();
      } else if (action == 'seek') {
        playback.position = const Duration(seconds: 10);
        playback.simulateSeek();
      } else if (action == 'native-reset') {
        playback.position = Duration.zero;
        playback
            .toggleShuffle(); // Publish Android's reset without user intent.
      } else if (action == 'leave') {
        router.go('/elsewhere');
      } else if (action == 'dispose') {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      await tester.pump(const Duration(milliseconds: 999));
      final advances = action == 'advance' || action == 'native-reset';
      if (advances) {
        expect(find.byType(AutoplayNextNotice), findsOneWidget);
      }
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(AutoplayNextNotice), findsNothing);
      expect(find.text('Next video'), advances ? findsOneWidget : findsNothing);
      if (advances) {
        expect(
          router.routeInformationProvider.value.uri.queryParameters['autoplay'],
          'true',
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      playback.dispose();
      auth.dispose();
      client.close();
    });
  }
  for (final dark in [false, true]) {
    testWidgets('autoplay card at large text, dark=$dark', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AutoplayNextNotice(
                  video: VideoCard.fromJson(
                    video('A long title that wraps across several lines'),
                  ),
                  onCancel: () => cancelled = true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(AppStrings.t('common.cancel')));
      expect(cancelled, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('native autoplay occurs after loading and respects dismissal', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Text('Player host')));
    final context = tester.element(find.text('Player host'));
    await tester.runAsync(() async {
      final messenger = tester.binding.defaultBinaryMessenger;
      final commands = <String>[];
      Completer<void>? pendingLoad;
      messenger.setMockMethodCallHandler(
        const MethodChannel('native_video_player'),
        (call) async {
          if ((call.arguments as Map?)?['viewId'] == 44002) {
            commands.add(call.method);
            if (call.method == 'load') await pendingLoad?.future;
          }
          if (call.method == 'setupControllerEventChannel') {
            messenger.setMockMethodCallHandler(
              MethodChannel(
                'native_video_player_controller_${(call.arguments as Map)['controllerId']}',
              ),
              (_) async => null,
            );
          }
          return null;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('native_video_player_44002'),
        (call) async {
          return null;
        },
      );
      final client = MockClient((_) async => jsonResponse({}));
      final auth = AuthController(ApiClient(client: client), MemoryStore());
      final playback = PlaybackSession();
      Future<void> prepare(String id) async {
        final controller = await playback.start(
          auth: auth,
          video: VideoDetail.fromJson(video(id)),
          videoRenditions: [],
          mediaEntitlements: const MediaEntitlements.none(),
          sourceUrl: 'https://video.test/$id',
          resumeAt: 0,
        );
        await controller.onPlatformViewCreated(44002, context);
      }

      await prepare('next');
      await playback.initialize('https://video.test/next', resumeAt: 0);
      expect(commands, contains('play'));
      expect(commands.indexOf('play'), greaterThan(commands.indexOf('load')));
      await playback.dismiss();
      await prepare('superseded');
      commands.clear();
      pendingLoad = Completer<void>();
      final initialization = playback.initialize(
        'https://video.test/superseded',
        resumeAt: 0,
        playWhenReady: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands, contains('load'));
      await playback.dismiss();
      pendingLoad.complete();
      await initialization;
      expect(commands, isNot(contains('play')));
      playback.dispose();
      auth.dispose();
      client.close();
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  group('opening a video starts native playback', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));
    for (final restart in [false, true]) {
      testWidgets(
        'opening a video autoplays and restart=$restart preserves correct progress',
        (tester) async {
          tester.view.physicalSize = const Size(375, 812);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final client = MockClient((request) async {
            final path = request.url.path;
            if (path.endsWith('/playback')) {
              return jsonResponse({'resumeAtSeconds': 25});
            }
            if (path.endsWith('/videos/first')) {
              return jsonResponse(_video('first'));
            }
            if (path.endsWith('/videos/second')) {
              return jsonResponse(_video('second'));
            }
            return jsonResponse({
              'items': [_video('second')],
              'page': 1,
              'total': 1,
            });
          });
          final auth = AuthController(ApiClient(client: client), MemoryStore())
            ..restoring = false;
          final playback = _RecordingPlayback()..autoplayNext = false;
          final router = GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => Scaffold(
                  body: VideoCardTile(
                    video: VideoCard.fromJson(_video('first')),
                  ),
                ),
              ),
              GoRoute(
                path: '/watch/:id',
                builder: (_, state) => WatchScreen(
                  auth: auth,
                  playback: playback,
                  videoId: state.pathParameters['id']!,
                  restartFromBeginning:
                      state.uri.queryParameters['autoplay'] == 'true',
                ),
              ),
            ],
          );
          await tester.pumpWidget(
            MaterialApp.router(
              theme: AppTheme.lightTheme,
              routerConfig: router,
            ),
          );
          await tester.pumpAndSettle();
          if (restart) {
            router.go('/watch/first?autoplay=true');
          } else {
            await tester.tap(find.byType(VideoCardTile));
          }
          await tester.pumpAndSettle();
          expect(playback.opened.single, ('first', true, restart ? 0 : 25));
          // Selecting a suggested video also starts it without a Play tap.
          final suggestion = find.text('Video second');
          await tester.scrollUntilVisible(
            suggestion,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(suggestion);
          await tester.pumpAndSettle();
          await tester.tap(suggestion);
          await tester.pumpAndSettle();
          expect(playback.opened.last, ('second', true, 25));
          expect(playback.opened.length, 2);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          router.dispose();
          playback.dispose();
          auth.dispose();
          client.close();
        },
      );
    }
  });
}
