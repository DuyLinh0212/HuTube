import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/media/device_conditions.dart';
import 'package:user_app/core/storage/app_preferences.dart';
import 'package:user_app/features/content/content_models.dart';
import 'package:user_app/features/content/media_entitlements.dart';
import 'package:user_app/features/content/playback_session.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse, session;

class LocalConditions extends DeviceConditions {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> refresh() async {}
}

void main() {
  for (final mode in ['off', 'always', 'headphones']) {
    for (final permitted in [false, true]) {
      testWidgets('background policy $mode, entitlement=$permitted', (
        tester,
      ) async {
        FlutterSecureStorage.setMockInitialValues({
          AppPreferencesStore.backgroundPlaybackModeKey: mode,
          AppPreferencesStore.playbackPipKey: '${mode != 'off'}',
        });
        await tester.pumpWidget(const MaterialApp(home: Text('Native host')));
        final context = tester.element(find.text('Native host'));
        await tester.runAsync(() async {
          final commands = <String>[];
          final messenger = tester.binding.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(
            const MethodChannel('native_video_player'),
            (call) async {
              commands.add(call.method);
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
            const MethodChannel('native_video_player_44003'),
            (_) async => null,
          );
          final client = MockClient((_) async => jsonResponse({}));
          final auth = AuthController(ApiClient(client: client), MemoryStore())
            ..restoring = false
            ..user = Map<String, dynamic>.from(session()['user'] as Map);
          final conditions = LocalConditions()
            ..setState(connected: true, wifi: true);
          final playback = PlaybackSession(conditions: conditions);
          final native = await playback.start(
            auth: auth,
            video: VideoDetail.fromJson({
              'videoId': 'test',
              'title': 'Test',
              'duration': 100,
            }),
            videoRenditions: [],
            mediaEntitlements: MediaEntitlements(
              backgroundPlayback: permitted,
              pictureInPicture: permitted,
            ),
            sourceUrl: 'https://file.test/test',
            resumeAt: 0,
          );
          expect(native.allowsPictureInPicture, permitted);
          expect(
            native.canStartPictureInPictureAutomatically,
            permitted && mode != 'off',
          );
          await native.onPlatformViewCreated(44003, context);
          playback.didChangeAppLifecycleState(AppLifecycleState.paused);
          playback.didChangeAppLifecycleState(AppLifecycleState.resumed);
          expect(
            identical(playback.player, native),
            isTrue,
            reason: 'Lock/unlock keeps the same player',
          );
          expect(
            playback.backgroundPlaybackEnabled,
            permitted && mode == 'always',
          );
          conditions.setState(connected: true, wifi: true, externalAudio: true);
          expect(
            playback.backgroundPlaybackEnabled,
            permitted && mode != 'off',
          );
          if (permitted && mode == 'headphones') {
            playback.didChangeAppLifecycleState(AppLifecycleState.paused);
            conditions.setState(
              connected: true,
              wifi: true,
              externalAudio: false,
            );
            await Future<void>.delayed(const Duration(milliseconds: 20));
            expect(playback.backgroundPlaybackEnabled, isFalse);
            expect(commands, contains('pause'));
            expect(playback.waitingForExternalAudio, isTrue);
            expect(await playback.setBackgroundPlaybackEnabled(false), isTrue);
            expect(playback.backgroundPlaybackRequested, isFalse);
            expect(await playback.setBackgroundPlaybackEnabled(true), isFalse);
            expect(playback.waitingForExternalAudio, isTrue);
          }
          if (permitted && mode == 'off') {
            expect(await playback.setBackgroundPlaybackEnabled(true), isTrue);
            expect(playback.backgroundPlaybackEnabled, isTrue);
            expect(await playback.setBackgroundPlaybackEnabled(false), isTrue);
          }
          if (permitted && mode == 'always') {
            await const AppPreferencesStore().writeBackgroundPlaybackMode(
              'off',
            );
            await Future<void>.delayed(const Duration(milliseconds: 20));
            expect(playback.backgroundPlaybackEnabled, isFalse);
          }
          if (!permitted) {
            expect(await playback.setBackgroundPlaybackEnabled(true), isFalse);
          }
          playback.dispose();
          conditions.dispose();
          auth.dispose();
          client.close();
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
