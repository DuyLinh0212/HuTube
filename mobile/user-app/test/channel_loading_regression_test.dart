import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:user_app/features/account/account_hub_screen.dart';
import 'package:user_app/features/notifications/notification_center.dart';
import 'package:user_app/features/moderation/moderation_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/channel/screens/channel_screen.dart';
import 'package:user_app/channel/services/channel_service.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse, session;

const channelId = '1609e9a9-fbc5-4afb-b82e-cda58280fd00';
Map<String, dynamic> detail({bool owner = true}) => {
  'channelId': channelId,
  'name': 'My channel',
  'handle': 'danh',
  'isOwner': owner,
  'subscriberCount': 45,
  'videoCount': 13,
};
http.Response lists(List<dynamic> values) => http.Response(
  jsonEncode(values),
  200,
  headers: {'content-type': 'application/json'},
);
Future<AuthController> login(http.Client client) async {
  final auth = AuthController(
    ApiClient(client: client),
    MemoryStore('refresh'),
  );
  await auth.restore();
  return auth;
}

void main() {
  const capture = bool.fromEnvironment('CAPTURE_MOBILE_UI');
  setUpAll(() async {
    if (!capture) return;
    for (final entry in {
      'Plus Jakarta Sans': File('C:/Windows/Fonts/arial.ttf'),
      'MaterialIcons': File(
        'D:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    }.entries) {
      final bytes = await entry.value.readAsBytes();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  setUp(() {
    ApiClient.invalidateReadCache();
    FlutterSecureStorage.setMockInitialValues({});
  });
  testWidgets(
    'owner channel uses public playlists and survives their failure',
    (tester) async {
      final requests = <String>[];
      final client = MockClient((r) async {
        requests.add(r.url.path);
        if (r.url.path.endsWith('/auth/refresh')) {
          return jsonResponse(session());
        }
        if (r.url.path.contains('/channels/')) return jsonResponse(detail());
        if (r.url.path.contains('/playlists/')) {
          return jsonResponse({'code': 'PLAYLIST_UNAVAILABLE'}, 500);
        }
        return jsonResponse({
          'items': [
            {'videoId': 'v1', 'title': 'Public video'},
          ],
          'page': 1,
          'total': 1,
        });
      });
      final auth = await login(client);
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelScreen(auth: auth, channelOrHandle: 'danh'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('My channel'), findsWidgets);
      expect(find.text('Public video'), findsWidgets);
      expect(requests, contains('/api/v1/playlists/channel/$channelId'));
      expect(requests.any((p) => p.endsWith('/mine')), isFalse);
      await tester.tap(find.text(AppStrings.t('channel.playlists')));
      await tester.pumpAndSettle();
      expect(
        find.text(AppStrings.t('channel.playlistsLoadError')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    },
  );

  test(
    'stable ID, explicit handles and normalized handles use correct API routes',
    () async {
      final paths = <String>[];
      final client = MockClient((r) async {
        paths.add(r.url.path);
        return jsonResponse(detail());
      });
      final auth = AuthController(ApiClient(client: client), MemoryStore());
      final service = ChannelService(auth);
      await service.getChannel(channelId);
      await service.getChannel('@$channelId');
      await service.getChannel('  @@DaNh  ');
      expect(paths, [
        '/api/v1/channels/$channelId',
        '/api/v1/channels/handle/$channelId',
        '/api/v1/channels/handle/danh',
      ]);
      auth.dispose();
      client.close();
    },
  );

  testWidgets('slow playlist never blocks channel profile or videos', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final client = MockClient((r) async {
      if (r.url.path.contains('/channels/')) return jsonResponse(detail());
      if (r.url.path.contains('/playlists/')) return pending.future;
      return jsonResponse({
        'items': [
          {'videoId': 'v', 'title': 'Loaded video'},
        ],
        'total': 1,
      });
    });
    final auth = AuthController(ApiClient(client: client), MemoryStore());
    await tester.pumpWidget(
      MaterialApp(
        home: ChannelScreen(auth: auth, channelOrHandle: 'danh'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('My channel'), findsWidgets);
    expect(find.text('Loaded video'), findsWidgets);
    pending.complete(lists([]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    client.close();
  });

  testWidgets('playlist retry reloads only its section', (tester) async {
    var profileLoads = 0, playlistLoads = 0;
    final client = MockClient((r) async {
      if (r.url.path.contains('/channels/')) {
        profileLoads++;
        return jsonResponse(detail());
      }
      if (r.url.path.contains('/playlists/')) {
        playlistLoads++;
        return playlistLoads == 1
            ? jsonResponse({'code': 'SERVER_ERROR'}, 500)
            : lists([
                {'playlistId': 'p', 'name': 'Recovered playlist'},
              ]);
      }
      return jsonResponse({'items': []});
    });
    final auth = AuthController(ApiClient(client: client), MemoryStore());
    await tester.pumpWidget(
      MaterialApp(
        home: ChannelScreen(auth: auth, channelOrHandle: 'danh'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.t('channel.playlists')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.t('channel.retry')));
    await tester.pumpAndSettle();
    expect(find.text('Recovered playlist'), findsOneWidget);
    expect(profileLoads, 1);
    expect(playlistLoads, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    client.close();
  });

  testWidgets(
    'subscription failure does not block channel and has independent retry',
    (tester) async {
      var statusCalls = 0;
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/auth/refresh')) {
          return jsonResponse(session());
        }
        if (r.url.path.endsWith('/subscribe-status')) {
          statusCalls++;
          return statusCalls == 1
              ? jsonResponse({'code': 'SERVER_ERROR'}, 500)
              : jsonResponse({
                  'status': 'active',
                  'notificationsEnabled': true,
                });
        }
        if (r.url.path.contains('/channels/')) {
          return jsonResponse(detail(owner: false));
        }
        if (r.url.path.contains('/playlists/')) return lists([]);
        return jsonResponse({'items': []});
      });
      final auth = await login(client);
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelScreen(auth: auth, channelOrHandle: 'danh'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('My channel'), findsWidgets);
      expect(
        find.text(AppStrings.t('channel.subscriptionLoadError')),
        findsOneWidget,
      );
      final subscribe = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, AppStrings.t('channel.subscribe')),
      );
      expect(subscribe.onPressed, isNull);
      await tester.ensureVisible(find.text(AppStrings.t('channel.retry')));
      await tester.tap(find.text(AppStrings.t('channel.retry')));
      await tester.pumpAndSettle();
      expect(
        find.text(AppStrings.t('channel.subscriptionLoadError')),
        findsNothing,
      );
      expect(statusCalls, 2);
      await tester.drag(find.byType(NestedScrollView), const Offset(0, 700));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(AppStrings.t('channel.subscribed')),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    },
  );

  testWidgets('video failure preserves channel and public playlists', (
    tester,
  ) async {
    final client = MockClient((r) async {
      if (r.url.path.contains('/channels/')) return jsonResponse(detail());
      if (r.url.path.contains('/playlists/')) {
        return lists([
          {'playlistId': 'p', 'name': 'Public playlist'},
        ]);
      }
      return jsonResponse({'code': 'SEARCH_FAILED'}, 500);
    });
    final auth = AuthController(ApiClient(client: client), MemoryStore());
    await tester.pumpWidget(
      MaterialApp(
        home: ChannelScreen(auth: auth, channelOrHandle: 'danh'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('My channel'), findsWidgets);
    expect(find.text(AppStrings.t('channel.videosLoadError')), findsOneWidget);
    expect(find.text(AppStrings.t('channel.noPublicVideos')), findsNothing);
    await tester.tap(find.text(AppStrings.t('channel.playlists')));
    await tester.pumpAndSettle();
    expect(find.text('Public playlist'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    client.close();
  });

  testWidgets('old route failure cannot overwrite a newer channel', (
    tester,
  ) async {
    final old = Completer<http.Response>();
    final client = MockClient((r) async {
      if (r.url.path.endsWith('/handle/old')) return old.future;
      if (r.url.path.contains('/channels/')) {
        return jsonResponse({...detail(), 'name': 'New channel'});
      }
      if (r.url.path.contains('/playlists/')) return lists([]);
      return jsonResponse({'items': []});
    });
    final auth = AuthController(ApiClient(client: client), MemoryStore());
    Widget screen(String handle) => MaterialApp(
      home: ChannelScreen(auth: auth, channelOrHandle: handle),
    );
    await tester.pumpWidget(screen('old'));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpWidget(screen('new'));
    await tester.pumpAndSettle();
    old.complete(jsonResponse({'code': 'CHANNEL_NOT_FOUND'}, 404));
    await tester.pumpAndSettle();
    expect(find.text('New channel'), findsWidgets);
    expect(find.text(AppStrings.t('channel.notFound')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    client.close();
  });

  testWidgets(
    'channel failure reports specific not-found and safe API reference',
    (tester) async {
      final client = MockClient(
        (r) async => jsonResponse({
          'code': 'CHANNEL_NOT_FOUND',
          'traceId': 'trace-example',
        }, 404),
      );
      final auth = AuthController(ApiClient(client: client), MemoryStore());
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelScreen(auth: auth, channelOrHandle: 'missing'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.t('channel.notFound')), findsOneWidget);
      expect(
        find.text('HTTP 404 · CHANNEL_NOT_FOUND · trace-example'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    },
  );

  testWidgets(
    'You to Channel opens stable channel ID instead of stale handle',
    (tester) async {
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/auth/refresh')) {
          return jsonResponse(session());
        }
        if (r.url.path.endsWith('/channels/me')) {
          return jsonResponse({...detail(), 'handle': 'outdated/handle'});
        }
        if (r.url.path.endsWith('/playlists') ||
            r.url.path.endsWith('/downloads')) {
          return lists([]);
        }
        return jsonResponse({'items': [], 'page': 1, 'total': 0});
      });
      final auth = await login(client);
      final notifications = NotificationCenter(auth);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                AccountHubScreen(auth: auth, notifications: notifications),
          ),
          GoRoute(
            path: '/channels/:id',
            builder: (_, state) =>
                Scaffold(body: Text('Opened ${state.pathParameters['id']}')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xem kênh'));
      await tester.pumpAndSettle();
      expect(find.text('Opened $channelId'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      notifications.dispose();
      auth.dispose();
      client.close();
    },
  );

  for (final owner in [false, true]) {
    for (final reason in [null, 'Reason provided by moderation']) {
      testWidgets(
        'suspended channel is explicit; owner=$owner reason=$reason',
        (tester) async {
          final requests = <String>[];
          final client = MockClient((r) async {
            requests.add(r.url.path);
            return jsonResponse({
              ...detail(owner: owner),
              'name': 'DanhHiHi',
              'handle': 'danh0311',
              'status': 'suspended',
              'statusReason': reason,
            });
          });
          final auth = AuthController(ApiClient(client: client), MemoryStore());
          await tester.pumpWidget(
            MaterialApp(
              home: ChannelScreen(auth: auth, channelOrHandle: 'danh0311'),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(AppStrings.t('channel.suspendedTitle')),
            findsOneWidget,
          );
          expect(find.text('DanhHiHi'), findsWidgets);
          expect(find.text(AppStrings.t('common.error')), findsNothing);
          expect(requests, ['/api/v1/channels/handle/danh0311']);
          expect(
            find.text(AppStrings.t('channel.statusAndAppeal')),
            owner ? findsOneWidget : findsNothing,
          );
          if (owner) {
            expect(
              find.text(
                reason == null
                    ? AppStrings.t('channel.suspensionReasonMissing')
                    : AppStrings.format('channel.suspensionReason', {
                        'reason': reason,
                      }),
              ),
              findsOneWidget,
            );
          } else {
            expect(find.textContaining('Reason provided'), findsNothing);
            final subscribe = tester.widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                AppStrings.t('channel.subscribe'),
              ),
            );
            expect(subscribe.onPressed, isNull);
          }
          if (owner && reason == null) {
            await tester.tap(
              find.text(AppStrings.t('channel.statusAndAppeal')),
            );
            await tester.pumpAndSettle();
            expect(find.byType(ModerationScreen), findsOneWidget);
            expect(find.byType(AppBar), findsOneWidget);
            await tester.pageBack();
            await tester.pumpAndSettle();
            expect(
              find.text(AppStrings.t('channel.suspendedTitle')),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          auth.dispose();
          client.close();
        },
      );
    }
  }

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'suspended notice fits narrow screen dark=$dark scale=$scale',
        (tester) async {
          tester.view.physicalSize = const Size(375, 812);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final client = MockClient(
            (r) async => jsonResponse({
              ...detail(),
              'name': 'DanhHiHi',
              'handle': 'danh0311',
              'status': 'suspended',
            }),
          );
          final auth = AuthController(ApiClient(client: client), MemoryStore());
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: ChannelScreen(auth: auth, channelOrHandle: 'danh0311'),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (capture && scale == 1) {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final folder = Directory('../../outputs/channel-status')
                ..createSync(recursive: true);
              await File(
                '${folder.path}/suspended-${dark ? 'dark' : 'light'}.png',
              ).writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox.shrink());
          auth.dispose();
          client.close();
        },
      );
    }
  }
}
