import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/media/device_conditions.dart';
import 'package:user_app/core/storage/app_preferences.dart';
import 'package:user_app/features/content/content_models.dart';
import 'package:user_app/features/content/download_coordinator.dart';
import 'package:user_app/features/content/download_preferences.dart';
import 'package:user_app/features/content/local_download_manager.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse, session;
import 'download_security_test.dart' show waitFor;
import 'package:user_app/features/content/download_actions.dart';
import 'package:flutter/material.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/features/content/playback_session.dart';
import 'package:user_app/features/content/watch_screen.dart';

class TestConditions extends DeviceConditions {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> refresh() async {}
}

http.Response array(List<dynamic> items) => http.Response(
  jsonEncode(items),
  200,
  headers: {'content-type': 'application/json'},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  final qualities = [
    for (final height in [360, 480, 720])
      Rendition(
        quality: '${height}p',
        width: height * 16 ~/ 9,
        height: height,
        fileSize: 8,
        url: 'https://file.test/$height',
      ),
  ];
  test('default quality respects ceiling and asks when configured', () {
    expect(selectDownloadRendition(qualities, 'ask'), isNull);
    expect(selectDownloadRendition(qualities, '1080p')!.quality, '720p');
    expect(selectDownloadRendition(qualities, '360p')!.quality, '360p');
    expect(selectDownloadRendition([qualities.last], '360p'), isNull);
    expect(selectDownloadRendition([], '720p'), isNull);
  });
  for (final quality in ['720p', 'ask']) {
    test(
      'manual download uses preference $quality and only asks when needed',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          AppPreferencesStore.downloadQualityKey: quality,
        });
        final root = await Directory.systemTemp.createTemp(
          'hutube_default_quality_',
        );
        var choices = 0;
        final requested = <String>[];
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            return jsonResponse(session());
          }
          if (request.url.path.endsWith('/download-options')) {
            return array([
              for (final r in qualities)
                {
                  'quality': r.quality,
                  'height': r.height,
                  'fileSize': r.fileSize,
                },
            ]);
          }
          if (request.url.path.endsWith('/downloads')) {
            final selected =
                (jsonDecode(request.body) as Map)['quality'] as String;
            requested.add(selected);
            return jsonResponse({
              'videoDownloadId': 'manual',
              'quality': selected,
              'fileSize': 8,
            });
          }
          return jsonResponse({});
        });
        final auth = AuthController(
          ApiClient(client: client),
          MemoryStore('refresh'),
        );
        await auth.restore();
        final manager = LocalDownloadManager.test(
          rootDirectory: () async => root,
          clientFactory: () =>
              MockClient((_) async => http.Response('12345678', 200)),
        );
        await manager.bindUser(
          'user-1',
          authorize: (_) async => 'https://file.test/test',
        );
        final conditions = TestConditions()
          ..setState(connected: true, wifi: true);
        final coordinator = DownloadCoordinator(
          auth,
          manager: manager,
          conditions: conditions,
        );
        try {
          await coordinator.initialize();
          expect(
            await coordinator.download(
              VideoCard.fromJson({'videoId': 'manual', 'title': 'Manual'}),
              choose: (options) async {
                choices++;
                return options.first;
              },
            ),
            isTrue,
          );
          await waitFor(() => manager.items.single.completed);
          expect(choices, quality == 'ask' ? 1 : 0);
          expect(requested.single, quality == 'ask' ? '360p' : '720p');
        } finally {
          coordinator.dispose();
          conditions.dispose();
          await manager.bindUser(null);
          await manager.flush();
          manager.dispose();
          auth.dispose();
          client.close();
          await root.delete(recursive: true);
        }
      },
    );
  }
  test(
    'Wi-Fi gates bytes, interrupts mobile handover, resumes and preserves manual pause',
    () async {
      final root = await Directory.systemTemp.createTemp('hutube_wifi_');
      final pending = Completer<http.Response>();
      var calls = 0, authorizations = 0;
      final manager = LocalDownloadManager.test(
        rootDirectory: () async => root,
        clientFactory: () => MockClient((_) async {
          calls++;
          return calls == 1 ? pending.future : http.Response('video', 200);
        }),
      );
      Future<void> network(bool wifi) =>
          manager.configurePolicy(connected: true, wifi: wifi, wifiOnly: true);
      try {
        await manager.bindUser(
          'owner',
          authorize: (_) async {
            authorizations++;
            return 'https://file.test/a';
          },
        );
        await network(false);
        await manager.enqueue(
          id: 'one',
          videoId: 'a',
          title: 'A',
          quality: '480p',
          url: '',
          fileSize: 5,
        );
        await waitFor(() => manager.items.single.status == 'waiting_wifi');
        expect(calls, 0);
        expect(authorizations, 0);
        await network(true);
        await waitFor(() => calls == 1);
        await network(false);
        expect(manager.items.single.status, 'waiting_wifi');
        pending.complete(http.Response('video', 200));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(manager.items.single.completed, isFalse);
        await manager.pause('one');
        await network(true);
        expect(manager.items.single.status, 'paused');
        expect(calls, 1);
        await manager.retry('one');
        expect(manager.items.single.completed, isTrue);
        expect(authorizations, 2);
      } finally {
        await manager.bindUser(null);
        await manager.flush();
        manager.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  test('disabled recommendations perform no ranking request', () async {
    FlutterSecureStorage.setMockInitialValues({
      AppPreferencesStore.downloadRecommendationsKey: 'false',
    });
    final root = await Directory.systemTemp.createTemp('hutube_rec_');
    var ranking = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        return jsonResponse(session());
      }
      if (request.url.path.contains('/feed/')) ranking++;
      return jsonResponse({'items': []});
    });
    final auth = AuthController(
      ApiClient(client: client),
      MemoryStore('refresh'),
    );
    await auth.restore();
    final manager = LocalDownloadManager.test(rootDirectory: () async => root);
    await manager.bindUser('user-1');
    final conditions = TestConditions()..setState(connected: true, wifi: true);
    final coordinator = DownloadCoordinator(
      auth,
      manager: manager,
      conditions: conditions,
    );
    try {
      await coordinator.initialize();
      await coordinator.loadSuggestions();
      expect(ranking, 0);
      expect(coordinator.suggestions, isEmpty);
    } finally {
      coordinator.dispose();
      conditions.dispose();
      await manager.bindUser(null);
      await manager.flush();
      manager.dispose();
      auth.dispose();
      client.close();
      await root.delete(recursive: true);
    }
  });

  group('download action availability', () {
    test(
      'download actions follow every server status and deny revoked requests',
      () {
        expect(remoteDownloadActions('ready'), [
          'download',
          'cancel',
          'delete',
        ]);
        expect(remoteDownloadActions('pending'), ['pause', 'cancel', 'delete']);
        expect(remoteDownloadActions('processing'), [
          'pause',
          'cancel',
          'delete',
        ]);
        expect(remoteDownloadActions('cancelled'), [
          'resume',
          'retry',
          'delete',
        ]);
        expect(remoteDownloadActions('failed'), ['retry', 'cancel', 'delete']);
        expect(remoteDownloadActions('revoked'), ['delete']);
        expect(remoteDownloadActions('unrecognized'), ['delete']);
      },
    );
  });

  group('watch download flow', () {
    for (final scenario in [
      'empty',
      'plan-denied',
      'select-quality',
      'session-changed',
      'session-changed-in-sheet',
    ]) {
      testWidgets('watch download: $scenario', (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        ApiClient.invalidateReadCache();
        final pending = Completer<http.Response>();
        final qualities = <String>[];
        final options = http.Response(
          jsonEncode([
            {'quality': '480p', 'width': 854, 'height': 480},
            {'quality': '720p', 'width': 1280, 'height': 720},
          ]),
          200,
        );
        var optionsRequested = false;
        final client = MockClient((r) async {
          if (r.url.path.endsWith('/videos/video')) {
            return jsonResponse({
              'videoId': 'video',
              'title': 'Download test',
              'channelId': 'channel',
            });
          }
          if (r.url.path.endsWith('/download-options')) {
            optionsRequested = true;
            return switch (scenario) {
              'empty' => http.Response('[]', 200),
              'plan-denied' => jsonResponse({
                'code': 'DOWNLOAD_NOT_INCLUDED',
              }, 403),
              'session-changed' => pending.future,
              _ => options,
            };
          }
          if (r.method == 'POST' && r.url.path.endsWith('/downloads')) {
            qualities.add(jsonDecode(r.body)['quality'] as String);
            return jsonResponse({'code': 'DOWNLOAD_QUALITY_DENIED'}, 403);
          }
          return jsonResponse({'items': []});
        });
        final auth = AuthController(ApiClient(client: client), MemoryStore())
          ..user = {'userId': 'viewer'};
        final playback = PlaybackSession()
          ..videoId = 'video'
          ..ready = true;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: WatchScreen(auth: auth, playback: playback, videoId: 'video'),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.widgetWithText(
          ActionChip,
          AppStrings.t('watch.downloadAction'),
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(optionsRequested, isTrue);
        if (scenario == 'session-changed') {
          await auth.clearSession();
          pending.complete(options);
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsNothing);
          expect(qualities, isEmpty);
        } else if (scenario == 'session-changed-in-sheet') {
          await auth.clearSession();
          await tester.tap(find.text('720p'));
          await tester.pumpAndSettle();
          expect(qualities, isEmpty);
        } else if (scenario == 'select-quality') {
          expect(find.text('720p'), findsOneWidget);
          await tester.tap(find.text('720p'));
          await tester.pumpAndSettle();
          expect(qualities, ['720p']);
          expect(
            find.text(AppStrings.t('downloads.qualityDenied')),
            findsOneWidget,
          );
        } else {
          expect(find.byType(BottomSheet), findsNothing);
          expect(
            find.text(
              AppStrings.t(
                scenario == 'empty' ? 'downloads.notReady' : 'media.planTitle',
              ),
            ),
            findsOneWidget,
          );
          expect(qualities, isEmpty);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        playback.dispose();
        auth.dispose();
        client.close();
      });
    }
  });
}
