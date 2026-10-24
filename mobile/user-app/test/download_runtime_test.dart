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
  test('default quality respects ceiling and smart ask uses 480p', () {
    expect(selectDownloadRendition(qualities, 'ask'), isNull);
    expect(
      selectDownloadRendition(qualities, 'ask', automatic: true)!.quality,
      '480p',
    );
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
      Future<void> network(bool wifi) => manager.configurePolicy(
        connected: true,
        wifi: wifi,
        wifiOnly: true,
        smartEnabled: false,
        smartBudget: 128 * 1024 * 1024,
      );
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
  for (final oversized in [false, true]) {
    test(
      'smart downloads respect Wi-Fi, permissions, cap and storage; oversized=$oversized',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          AppPreferencesStore.downloadSmartKey: 'true',
          AppPreferencesStore.downloadRecommendationsKey: 'false',
          AppPreferencesStore.downloadSmartLimitKey: '128',
        });
        final root = await Directory.systemTemp.createTemp('hutube_smart_');
        final conditions = TestConditions()
          ..setState(connected: true, wifi: false);
        final created = <String>[];
        final client = MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/auth/refresh')) return jsonResponse(session());
          if (path.endsWith('/downloads') && request.method == 'GET') {
            return array([]);
          }
          if (path.endsWith('/feed/recommended')) {
            return jsonResponse({
              'items': [
                for (var i = 0; i < 6; i++)
                  {'videoId': 'v$i', 'title': 'Video $i'},
              ],
            });
          }
          if (path.endsWith('/download-options')) {
            if (path.contains('/v0/')) {
              return jsonResponse({'code': 'FORBIDDEN'}, 403);
            }
            return array([
              {
                'quality': '480p',
                'height': 480,
                'fileSize': oversized ? 200 * 1024 * 1024 : 8,
              },
            ]);
          }
          if (path.endsWith('/downloads') && request.method == 'POST') {
            final id = path.split('/').reversed.skip(1).first;
            created.add(id);
            expect((jsonDecode(request.body) as Map)['quality'], '480p');
            return jsonResponse({
              'videoDownloadId': id,
              'videoId': id,
              'title': id,
              'quality': '480p',
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
          authorize: (_) async => 'https://file.test/a',
        );
        final coordinator = DownloadCoordinator(
          auth,
          manager: manager,
          conditions: conditions,
        );
        try {
          await coordinator.initialize();
          await coordinator.smartIdle;
          expect(created, isEmpty);
          conditions.setState(connected: true, wifi: true);
          await coordinator.smartIdle;
          expect(created.length, oversized ? 0 : 3);
          expect(created, isNot(contains('v0')));
          expect(
            coordinator.suggestions,
            isEmpty,
            reason: 'Display preference does not enable/disable automatic jobs',
          );
          if (!oversized) {
            await waitFor(() => manager.items.every((d) => d.completed));
            expect(manager.items.every((d) => d.smart), isTrue);
            conditions.setState(connected: true, wifi: false);
            conditions.setState(connected: true, wifi: true);
            await coordinator.smartIdle;
            expect(created.length, 3);
          }
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
}
