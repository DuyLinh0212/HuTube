import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/features/content/explore_screen.dart';
import 'package:user_app/features/content/playback_session.dart';
import 'package:user_app/features/content/watch_screen.dart';
import 'package:user_app/features/creator/creator_hub_screen.dart';

import 'package:user_app/features/creator/video_upload_screen.dart';
import 'package:user_app/features/moderation/moderation_screen.dart';
import 'package:user_app/channel/models/channel_models.dart';

import 'auth_test.dart' show MemoryStore, jsonResponse;

void main() {
  const capture = bool.fromEnvironment('CAPTURE_MOBILE_UI');
  setUpAll(() async {
    if (!capture) return;
    for (final font in {
      'Plus Jakarta Sans': 'C:/Windows/Fonts/arial.ttf',
      'MaterialIcons':
          'D:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = await File(font.value).readAsBytes();
      await (FontLoader(
        font.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  setUp(() {
    ApiClient.invalidateReadCache();
    FlutterSecureStorage.setMockInitialValues({});
    AppStrings.currentLang.value = 'vi';
  });

  for (final scenario in ['suspended', 'missing', 'network']) {
    testWidgets(
      'upload entry distinguishes suspended, missing and lookup error: $scenario',
      (tester) async {
        var writes = 0;
        final owned = {
          'channelId': 'mine',
          'name': 'My channel',
          'handle': 'mine',
          'status': 'suspended',
          'isOwner': true,
        };
        final client = MockClient((r) async {
          if (r.method != 'GET') writes++;
          if (r.url.path.endsWith('/channels/accessible') ||
              r.url.path.endsWith('/appeals/my')) {
            return http.Response('[]', 200);
          }
          if (r.url.path.endsWith('/channels/me')) {
            return scenario == 'suspended'
                ? jsonResponse(owned)
                : jsonResponse({
                    'code': scenario == 'missing'
                        ? 'CHANNEL_NOT_FOUND'
                        : 'INTERNAL_ERROR',
                  }, scenario == 'missing' ? 404 : 500);
          }
          return jsonResponse({'strikes': [], 'isSuspended': true});
        });
        final auth = AuthController(ApiClient(client: client), MemoryStore())
          ..user = {'userId': 'owner'};
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CreatorHubScreen(auth: auth, openUpload: true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(VideoUploadScreen), findsNothing);
        if (scenario == 'suspended') {
          expect(
            find.text(AppStrings.t('creator.uploadSuspended')),
            findsOneWidget,
          );
          expect(find.text(AppStrings.t('creator.noChannel')), findsNothing);
          expect(
            find.text(AppStrings.t('creator.createChannel')),
            findsNothing,
          );
          await tester.tap(find.text(AppStrings.t('channel.statusAndAppeal')));
          await tester.pumpAndSettle();
          expect(find.byType(ModerationScreen), findsOneWidget);
        } else if (scenario == 'missing') {
          expect(find.text(AppStrings.t('creator.noChannel')), findsOneWidget);
        } else {
          expect(find.text(AppStrings.t('creator.noChannel')), findsNothing);
          expect(find.text(AppStrings.t('common.retry')), findsOneWidget);
        }
        expect(writes, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        auth.dispose();
      },
    );
  }
  testWidgets(
    'direct upload route explains suspended channel before showing a form',
    (tester) async {
      final client = MockClient((_) async => http.Response('[]', 200));
      final auth = AuthController(ApiClient(client: client), MemoryStore());
      await tester.pumpWidget(
        MaterialApp(
          home: VideoUploadScreen(
            auth: auth,
            channel: ChannelDetail.fromJson({
              'channelId': 'mine',
              'isOwner': true,
              'status': 'suspended',
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(AppStrings.t('creator.uploadSuspended')),
        findsOneWidget,
      );
      expect(find.text(AppStrings.t('upload.chooseVideo')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    },
  );

  for (final explore in [true, false]) {
    testWidgets(
      '${explore ? 'explore' : 'watch'} waits for identity and replaces self-subscribe',
      (tester) async {
        final owner = Completer<http.Response>();
        var subscriptions = 0;
        final client = MockClient((r) async {
          if (r.url.path.endsWith('/channels/me')) return owner.future;
          if (r.url.path.endsWith('/subscribe')) subscriptions++;
          if (r.url.path.endsWith('/feed/explore-hub')) {
            return jsonResponse({
              'creators': [
                {'channelId': 'mine', 'name': 'My channel', 'handle': 'mine'},
              ],
            });
          }
          if (r.url.path.endsWith('/videos/video')) {
            return jsonResponse({
              'videoId': 'video',
              'channelId': 'mine',
              'channelHandle': 'mine',
              'channelName': 'My channel',
              'title': 'My video',
            });
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
            home: Scaffold(
              body: explore
                  ? ExploreScreen(auth: auth)
                  : WatchScreen(
                      auth: auth,
                      playback: playback,
                      videoId: 'video',
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final label = AppStrings.t(
          explore ? 'explore.subscribe' : 'watch.follow',
        );
        final button = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, label),
        );
        expect(button.onPressed, isNull);
        owner.complete(
          jsonResponse({
            'channelId': 'mine',
            'handle': 'mine',
            'isOwner': true,
          }),
        );
        await tester.pumpAndSettle();
        expect(find.widgetWithText(OutlinedButton, label), findsNothing);
        expect(find.text(AppStrings.t('channel.yourChannel')), findsOneWidget);
        expect(subscriptions, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        playback.dispose();
        auth.dispose();
        client.close();
      },
    );
  }

  for (final dark in [false, true]) {
    for (final size in [const Size(375, 812), const Size(640, 360)]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('creator layout dark=$dark size=$size scale=$scale', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final client = MockClient(
            (_) async => http.Response(
              jsonEncode([
                {
                  'channelId': 'mine',
                  'name': 'FanLiverpool',
                  'handle': 'lynwa',
                  'subscriberCount': 111,
                  'videoCount': 75,
                  'viewCount': 1525,
                  'isOwner': true,
                },
                {
                  'channelId': 'managed',
                  'name': 'Managed channel',
                  'handle': 'managed',
                  'myRole': 'editor',
                },
              ]),
              200,
            ),
          );
          final auth = AuthController(ApiClient(client: client), MemoryStore())
            ..user = {'userId': 'viewer'};
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: boundary,
                child: Scaffold(body: CreatorHubScreen(auth: auth)),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.widgetWithText(FilledButton, AppStrings.t('creator.upload')),
            100,
          );
          await tester.pumpAndSettle();
          expect(find.text('FanLiverpool'), findsWidgets);
          expect(
            find.widgetWithText(FilledButton, AppStrings.t('creator.upload')),
            findsOneWidget,
          );
          if (capture && size.width == 375 && scale == 1) {
            final scroll = tester.state<ScrollableState>(
              find.byType(Scrollable).first,
            );
            scroll.position.jumpTo(0);
            await tester.pumpAndSettle();
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final folder = Directory('../../outputs/mobile-fixes')
                ..createSync(recursive: true);
              await File(
                '${folder.path}/creator-${dark ? 'dark' : 'light'}.png',
              ).writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.drag(find.byType(ListView), const Offset(0, -800));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          auth.dispose();
          client.close();
        });
      }
    }
  }
}
