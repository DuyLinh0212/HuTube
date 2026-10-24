import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/features/content/content_models.dart';
import 'package:user_app/features/content/media_entitlements.dart';
import 'package:user_app/features/content/playback_session.dart';
import 'package:user_app/features/content/video_card.dart';
import 'package:user_app/features/content/watch_screen.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse;

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

void main() {
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
                body: VideoCardTile(video: VideoCard.fromJson(_video('first'))),
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
          MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
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
}
