import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/features/content/local_download_manager.dart';
import 'package:user_app/features/content/offline_player_screen.dart';
import 'package:user_app/channel/channel_handle.dart';
import 'auth_test.dart' show jsonResponse, session;
import 'download_security_test.dart' show waitFor;

class LocalFilePlayer extends NativeVideoPlayerController {
  LocalFilePlayer() : super(id: 998);
  String? path;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> loadFile({required String path}) async {
    this.path = path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'offline identity is bound to the current stored session and cleared at logout',
    () async {
      const store = SecureTokenStore();
      await store.write('refresh');
      await store.writeOfflineUser(
        'refresh',
        session()['user'] as Map<String, dynamic>,
      );
      expect((await store.readOfflineUser('refresh'))?['userId'], 'user-1');
      expect(await store.readOfflineUser('another-account-session'), isNull);
      await store.clear();
      expect(await store.read(), isNull);
      expect(await store.readOfflineUser('refresh'), isNull);
    },
  );

  for (final rejected in [false, true]) {
    test(
      'cold start preserves local identity only for network failure; rejected=$rejected',
      () async {
        const store = SecureTokenStore();
        await store.write('refresh');
        await store.writeOfflineUser(
          'refresh',
          session()['user'] as Map<String, dynamic>,
        );
        final client = MockClient((_) async {
          if (rejected) {
            return jsonResponse({'code': 'INVALID_REFRESH_TOKEN'}, 401);
          }
          throw const SocketException('offline');
        });
        final auth = AuthController(ApiClient(client: client), store);
        await auth.restore();
        expect(auth.authenticated, !rejected);
        expect(auth.offlineSession, !rejected);
        expect(auth.accessToken, isNull);
        if (!rejected) {
          expect(auth.user?['userId'], 'user-1');
        } else {
          expect(await store.readOfflineUser('refresh'), isNull);
        }
        await auth.clearSession();
        auth.dispose();
        client.close();
      },
    );
  }

  test(
    'cached local identity is ready before a slow refresh and is removed if the server rejects it',
    () async {
      const store = SecureTokenStore();
      await store.write('refresh');
      await store.writeOfflineUser(
        'refresh',
        session()['user'] as Map<String, dynamic>,
      );
      final response = Completer<http.Response>();
      final client = MockClient((_) => response.future);
      final auth = AuthController(ApiClient(client: client), store);
      final restoring = auth.restore();
      await waitFor(() => auth.offlineSession);
      expect(auth.restoring, isFalse);
      expect(auth.user?['userId'], 'user-1');
      response.complete(jsonResponse({'code': 'INVALID_REFRESH_TOKEN'}, 401));
      await restoring;
      expect(auth.authenticated, isFalse);
      expect(await store.readOfflineUser('refresh'), isNull);
      auth.dispose();
      client.close();
    },
  );

  test(
    'retired automatic queue stays paused while completed files remain usable after restart',
    () async {
      final root = await Directory.systemTemp.createTemp('dalitu_offline_');
      final manager = LocalDownloadManager.test(
        rootDirectory: () async => root,
        clientFactory: () =>
            MockClient((_) async => http.Response('video', 200)),
      );
      try {
        await manager.bindUser(
          'owner',
          authorize: (_) async => 'https://file.test/video',
        );
        await manager.enqueue(
          id: 'complete',
          videoId: 'video',
          title: 'Saved video',
          quality: '720p',
          url: '',
          fileSize: 5,
        );
        await waitFor(() => manager.items.single.completed);
        await manager.flush();
        final path = manager.items.single.filePath!;
        await manager.bindUser(null);
        final manifest = File('${root.path}/downloads/owner/manifest.json');
        final saved = jsonDecode(await manifest.readAsString()) as List;
        saved.add({
          'id': 'retired',
          'videoId': 'old',
          'title': 'Old automatic queue',
          'smart': true,
          'status': 'waiting_wifi',
        });
        await manifest.writeAsString(jsonEncode(saved));
        var network = 0;
        final restarted = LocalDownloadManager.test(
          rootDirectory: () async => root,
          clientFactory: () => MockClient((_) async {
            network++;
            throw const SocketException('offline');
          }),
        );
        try {
          await restarted.bindUser('owner');
          await restarted.configurePolicy(
            connected: true,
            wifi: true,
            wifiOnly: false,
          );
          expect(restarted.items.first.completed, isTrue);
          expect(restarted.items.last.status, 'paused');
          expect(await File(path).readAsString(), 'video');
          expect(network, 0);
          await restarted.bindUser('another-owner');
          expect(restarted.items, isEmpty);
        } finally {
          await restarted.bindUser(null);
          await restarted.flush();
          restarted.dispose();
        }
      } finally {
        await manager.bindUser(null);
        await manager.flush();
        manager.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'offline player loads the saved local file without a plan or media network request',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final fixture = await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp(
          'dalitu_local_player_',
        );
        final manager = LocalDownloadManager.test(
          rootDirectory: () async => root,
          clientFactory: () =>
              MockClient((_) async => http.Response('video', 200)),
        );
        await manager.bindUser(
          'user-1',
          authorize: (_) async => 'https://file.test/video',
        );
        await manager.enqueue(
          id: 'local',
          videoId: 'video',
          title: 'Offline video',
          quality: '720p',
          url: '',
          fileSize: 5,
        );
        await waitFor(() => manager.items.single.completed);
        return (root, manager, manager.items.single);
      });
      final (root, manager, item) = fixture!;
      var network = 0;
      final client = MockClient((_) async {
        network++;
        throw const SocketException('offline');
      });
      final auth = AuthController(
        ApiClient(client: client),
        const SecureTokenStore(),
      )..user = session()['user'] as Map<String, dynamic>;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('native_video_player'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(
        MethodChannel('native_video_player_controller_998'),
        (call) async {
          return null;
        },
      );
      final player = LocalFilePlayer();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: OfflinePlayerScreen(
              auth: auth,
              download: item,
              manager: manager,
              playerFactory: () => player,
            ),
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        });
        await tester.pump(const Duration(milliseconds: 100));
        expect(player.path, item.filePath!);
        expect(find.text('Offline video'), findsOneWidget);
        expect(network, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await manager.bindUser(null);
          await manager.flush();
          manager.dispose();
          auth.dispose();
          client.close();
          await root.delete(recursive: true);
        });
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  test(
    'channel suggestions fit the handle format and preserve Vietnamese names',
    () {
      expect(
        suggestChannelHandle('Kí sự Jura', '12345678'),
        'ki-su-jura-12345678',
      );
      expect(suggestChannelHandle('a' * 100, '12345678').length, 50);
    },
  );
}
