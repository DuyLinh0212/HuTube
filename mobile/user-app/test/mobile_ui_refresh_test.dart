import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/app/mobile_scaffold.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/channel/screens/create_channel_screen.dart';
import 'package:user_app/channel/screens/channel_screen.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/features/content/content_models.dart';
import 'package:user_app/features/content/content_service.dart';
import 'package:user_app/features/content/library_screen.dart';
import 'package:user_app/features/content/playback_session.dart';
import 'package:user_app/features/content/widgets/comment_sheets.dart';
import 'package:user_app/features/moderation/appeal_composer.dart';
import 'package:user_app/features/moderation/moderation_screen.dart';
import 'package:user_app/features/notifications/notification_center.dart';
import 'package:user_app/features/playlists/playlists_screen.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse, session;

const coverUrl = 'https://preview.test/cover.jpg';
const ownedId = '78e93a91-f2e7-46ad-bf36-cb381cd8eb61';
Map<String, dynamic> get channelData => {
  'channelId': ownedId,
  'name': 'DanhHiHi',
  'handle': 'danh0311',
  'status': 'suspended',
  'isOwner': true,
};
Map<String, dynamic> get videoData => {
  'videoId': 'v',
  'channelId': 'c',
  'channelName': 'Dalitu Music',
  'title': 'Một chuyến đi để nhớ – Những điều đẹp nhất',
  'thumbnailUrl': coverUrl,
  'duration': 254,
  'progress': .4,
  'watchedSeconds': 102,
  'activityAt': '2026-10-26T08:00:00Z',
};
Map<String, dynamic> get commentData => {
  'commentId': 'root',
  'videoId': 'v',
  'displayName': 'Minh Anh',
  'content': 'Video hay quá, mong sớm được xem phần tiếp theo!',
  'replyCount': 1,
};
http.Response list(List<dynamic> value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response fixture(http.Request r) {
  final path = r.url.path;
  if (path.endsWith('/auth/refresh')) return jsonResponse(session());
  if (path.endsWith('/channels/me') || path.endsWith('/channels/$ownedId')) {
    return jsonResponse(channelData);
  }
  if (path.endsWith('/strikes')) {
    return jsonResponse({
      'isSuspended': true,
      'activeStrikesCount': 1,
      'strikes': [
        {
          'reason': 'Nội dung đang được xem xét',
          'severity': 'low',
          'createdAt': '2026-10-25T08:41:00Z',
        },
      ],
    });
  }
  if (path.endsWith('/appeals/my')) return list([]);
  if (path.endsWith('/playlists')) {
    return list([
      {
        'playlistId': 'p',
        'name': 'Những video yêu thích',
        'visibility': 'public',
        'itemCount': 3,
        'coverUrl': coverUrl,
        'previewItems': [],
      },
    ]);
  }
  if (path.endsWith('/replies')) {
    return jsonResponse({
      'items': [
        {
          ...commentData,
          'commentId': 'reply',
          'displayName': 'Công Danh',
          'content': 'Cảm ơn bạn, mình đang chuẩn bị phần mới.',
          'replyCount': 0,
        },
      ],
      'page': 1,
      'total': 1,
      'pageSize': 20,
    });
  }
  return jsonResponse({
    'items': [videoData],
    'page': 1,
    'total': 1,
    'pageSize': 20,
  });
}

Widget threadTile(
  CommentItem item,
  ValueChanged<CommentItem> update,
  VoidCallback? reply,
) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 12),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(radius: 15, child: Text(item.displayName[0])),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.displayName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(item.content),
            TextButton(
              onPressed: reply,
              child: Text(AppStrings.t('common.reply')),
            ),
          ],
        ),
      ),
    ],
  ),
);

void main() {
  const capture = bool.fromEnvironment('CAPTURE_MOBILE_UI');
  setUp(() {
    ApiClient.invalidateReadCache();
    FlutterSecureStorage.setMockInitialValues({});
    AppStrings.currentLang.value = 'vi';
  });
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
  test(
    'server category labels follow selected language without changing IDs',
    () {
      const category = Category(
        id: 'football-id',
        name: 'Football',
        slug: 'football',
      );
      expect(category.displayName, 'Bóng đá');
      expect(AppStrings.categoryLabel('Daily'), 'Đời sống');
      expect(AppStrings.categoryLabel('Entertainment'), 'Giải trí');
      AppStrings.currentLang.value = 'en';
      expect(category.displayName, 'Football');
      expect(AppStrings.categoryLabel('Đời sống', 'daily'), 'Daily');
      expect(category.id, 'football-id');
      AppStrings.currentLang.value = 'vi';
      expect(category.displayName, 'Bóng đá');
      expect(
        AppStrings.categoryLabel('Tên do người dùng đặt', 'custom-topic'),
        'Tên do người dùng đặt',
      );
    },
  );

  for (final exists in [false, true]) {
    testWidgets('create menu knows current channel, exists=$exists', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/auth/refresh')) {
          return jsonResponse(session());
        }
        if (r.url.path.endsWith('/channels/me')) {
          return exists
              ? jsonResponse(channelData)
              : jsonResponse({'code': 'CHANNEL_NOT_FOUND'}, 404);
        }
        return jsonResponse({'items': []});
      });
      final auth = AuthController(
        ApiClient(client: client),
        MemoryStore('refresh'),
      );
      await auth.restore();
      final playback = PlaybackSession();
      final notifications = NotificationCenter(auth);
      final router = GoRouter(
        routes: [
          ShellRoute(
            builder: (_, state, child) => MobileScaffold(
              auth: auth,
              playback: playback,
              notifications: notifications,
              location: state.uri.path,
              child: child,
            ),
            routes: [
              GoRoute(path: '/', builder: (_, _) => const SizedBox()),
              GoRoute(
                path: '/channels/:id',
                builder: (_, state) =>
                    Text('opened ${state.pathParameters['id']}'),
              ),
              GoRoute(
                path: '/create-channel',
                builder: (_, _) => const Text('new channel form'),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.t('app.createButton')));
      await tester.pumpAndSettle();
      final label = AppStrings.t(
        exists ? 'app.create.existingChannel' : 'app.create.channelTitle',
      );
      expect(find.text(label), findsOneWidget);
      if (exists) {
        expect(
          find.text(AppStrings.t('app.create.channelTitle')),
          findsNothing,
        );
      }
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(
        find.text(exists ? 'opened $ownedId' : 'new channel form'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      playback.dispose();
      notifications.dispose();
      auth.dispose();
      client.close();
    });
  }

  testWidgets(
    'direct create route redirects existing suspended channel without creation request',
    (tester) async {
      var posts = 0;
      final client = MockClient((r) async {
        if (r.method == 'POST') posts++;
        return jsonResponse(channelData);
      });
      final auth = AuthController(ApiClient(client: client), MemoryStore());
      await tester.pumpWidget(
        MaterialApp(home: CreateChannelScreen(auth: auth)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChannelScreen), findsOneWidget);
      expect(find.text(AppStrings.t('channel.suspendedTitle')), findsOneWidget);
      expect(posts, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    },
  );

  testWidgets(
    'reply send retains draft on failure and stays in thread after success',
    (tester) async {
      var posts = 0;
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/auth/refresh')) {
          return jsonResponse(session());
        }
        if (r.method == 'POST') {
          posts++;
          final data = jsonDecode(r.body) as Map;
          expect(data['parentCommentId'], 'root');
          expect(data['content'], 'Cảm ơn bạn!');
          return posts == 1
              ? jsonResponse({'code': 'TEMPORARY_ERROR'}, 503)
              : jsonResponse({
                  ...commentData,
                  'commentId': 'new',
                  'displayName': 'Linh',
                  'content': data['content'],
                  'replyCount': 0,
                });
        }
        return fixture(r);
      });
      final auth = AuthController(
        ApiClient(client: client),
        MemoryStore('refresh'),
      );
      await auth.restore();
      CommentItem? updated;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentThreadSheet(
              auth: auth,
              content: ContentService(auth),
              parent: CommentItem.fromJson(commentData),
              tileBuilder: threadTile,
              onParentChanged: (item) => updated = item,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('thread-reply-input')),
        'Cảm ơn bạn!',
      );
      await tester.pump();
      await tester.tap(find.byTooltip(AppStrings.t('common.send')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('thread-reply-input')))
            .controller!
            .text,
        'Cảm ơn bạn!',
      );
      await tester.tap(find.byTooltip(AppStrings.t('common.send')));
      await tester.pumpAndSettle();
      expect(posts, 2);
      expect(find.text('Cảm ơn bạn!'), findsOneWidget);
      expect(updated?.replyCount, 2);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('thread-reply-input')))
            .controller!
            .text,
        '',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    },
  );

  testWidgets(
    'appeal from moderation uses loaded channel without asking for raw ID',
    (tester) async {
      final client = MockClient((r) async => fixture(r));
      final auth = AuthController(
        ApiClient(client: client),
        MemoryStore('refresh'),
      );
      await auth.restore();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ModerationScreen(auth: auth)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.t('moderation.sendAppeal')));
      await tester.pumpAndSettle();
      expect(find.byType(AppealComposer), findsOneWidget);
      expect(find.text('DanhHiHi'), findsWidgets);
      expect(find.byKey(const ValueKey('appeal-target')), findsNothing);
      expect(find.byKey(const ValueKey('appeal-reason')), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    },
  );

  testWidgets(
    'comment edit sheet preserves draft after failure and closes only after save',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => CommentEditorSheet(
                    initialValue: 'Bình luận cũ',
                    onSubmit: (text) async {
                      attempts++;
                      expect(text, 'Bình luận đã sửa');
                      if (attempts == 1) {
                        throw const ApiFailure(503, 'TEMPORARY_ERROR', 'test');
                      }
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('text-entry-input')),
        'Bình luận đã sửa',
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, AppStrings.t('common.save')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('text-entry-input')))
            .controller!
            .text,
        'Bình luận đã sửa',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, AppStrings.t('common.save')),
      );
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.byType(CommentEditorSheet), findsNothing);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(640, 360),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('refreshed screens dark=$dark size=$size scale=$scale', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          final client = MockClient((r) async => fixture(r));
          final auth = AuthController(
            ApiClient(client: client),
            MemoryStore('refresh'),
          );
          await auth.restore();
          await tester.runAsync(() async {
            final bytes = await File(
              '../../assets/auth/card_explore.jpg',
            ).readAsBytes();
            final codec = await ui.instantiateImageCodec(
              bytes,
              targetWidth: 640,
            );
            final frame = await codec.getNextFrame();
            for (final provider in <ImageProvider>[
              const NetworkImage(coverUrl),
              const ResizeImage(NetworkImage(coverUrl), width: 480),
              const ResizeImage(NetworkImage(coverUrl), width: 720),
            ]) {
              final key = await provider.obtainKey(ImageConfiguration.empty);
              PaintingBinding.instance.imageCache.putIfAbsent(
                key,
                () => OneFrameImageStreamCompleter(
                  Future.value(ImageInfo(image: frame.image.clone())),
                ),
              );
            }
            frame.image.dispose();
            codec.dispose();
          });
          for (final entry in <String, Widget>{
            'playlists': PlaylistsScreen(auth: auth),
            'library': LibraryScreen(auth: auth),
            'moderation': ModerationScreen(auth: auth),
            'appeal': AppealComposer(
              auth: auth,
              targetId: ownedId,
              targetType: 'channel',
              targetLabel: 'DanhHiHi',
            ),
            'edit-comment': CommentEditorSheet(
              initialValue: 'Video hay quá!',
              onSubmit: (_) async {},
            ),
            'replies': CommentThreadSheet(
              auth: auth,
              content: ContentService(auth),
              parent: CommentItem.fromJson(commentData),
              tileBuilder: threadTile,
              onParentChanged: (_) {},
            ),
          }.entries) {
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
                  home: Scaffold(
                    resizeToAvoidBottomInset: false,
                    body: entry.value,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: entry.key);
            if (capture && size.width == 390 && scale == 1) {
              await tester.runAsync(() async {
                final image =
                    await (boundary.currentContext!.findRenderObject()
                            as RenderRepaintBoundary)
                        .toImage();
                final data = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final folder = Directory('../../outputs/mobile-ui-refresh')
                  ..createSync(recursive: true);
                await File(
                  '${folder.path}/${entry.key}-${dark ? 'dark' : 'light'}.png',
                ).writeAsBytes(data!.buffer.asUint8List());
                image.dispose();
              });
            }
            if (['appeal', 'edit-comment', 'replies'].contains(entry.key)) {
              tester.view.viewInsets = const FakeViewPadding(bottom: 160);
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '${entry.key} keyboard',
              );
              tester.view.resetViewInsets();
              await tester.pumpAndSettle();
            }
            await tester.pumpWidget(const SizedBox.shrink());
          }
          auth.dispose();
          client.close();
        });
      }
    }
  }
}
