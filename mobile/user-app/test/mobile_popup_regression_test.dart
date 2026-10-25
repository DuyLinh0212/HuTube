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
import 'package:user_app/auth.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/core/media/picture_in_picture.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/core/widgets/confirmation_dialog.dart';
import 'package:user_app/core/widgets/text_entry_dialog.dart';
import 'package:user_app/features/content/widgets/rating_sheet.dart';
import 'package:user_app/features/playlists/playlists_screen.dart';
import 'package:user_app/features/playlists/save_playlist_sheet.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse, session;

Future<void> capture(WidgetTester tester, String name) async {
  if (Platform.environment['CAPTURE_MOBILE_AUDIT'] != 'true') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '../../.work/mobile-audit/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final fonts = Platform.environment['MOBILE_AUDIT_FONT_DIR'];
    if (fonts == null) return;
    for (final name in ['Plus Jakarta Sans', 'Roboto', 'MaterialIcons']) {
      final loader = FontLoader(name);
      final file = name == 'MaterialIcons'
          ? 'materialicons-regular.otf'
          : 'roboto-regular.ttf';
      loader.addFont(
        File('$fonts/$file').readAsBytes().then(ByteData.sublistView),
      );
      await loader.load();
    }
  });
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AppStrings.currentLang.value = 'vi';
  });

  testWidgets('existing playlist keeps create action and opens creation form', (
    tester,
  ) async {
    final client = MockClient((r) async {
      if (r.url.path.endsWith('/auth/refresh')) return jsonResponse(session());
      if (r.url.path.endsWith('/playlists')) {
        return http.Response(
          jsonEncode([
            {
              'playlistId': 'one',
              'name': 'My playlist',
              'visibility': 'private',
              'itemCount': 0,
            },
          ]),
          200,
        );
      }
      return jsonResponse({
        'playlistId': 'one',
        'name': 'My playlist',
        'items': [],
      });
    });
    final auth = AuthController(
      ApiClient(client: client),
      MemoryStore('refresh'),
    );
    await auth.restore();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: PlaylistsScreen(auth: auth)),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
    );
    await tester.pumpAndSettle();
    expect(find.text('My playlist'), findsOneWidget);
    final create = find.byKey(const ValueKey('playlist-create-always'));
    expect(create, findsOneWidget);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('playlist-name')), findsOneWidget);
    await tester.tap(find.byTooltip(AppStrings.t('common.close')));
    await tester.pumpAndSettle();
    expect(find.text('My playlist'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    auth.dispose();
    client.close();
  });

  for (final mode in ['existing', 'new', 'duplicate']) {
    testWidgets('playlist save sheet $mode works with a populated list', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final writes = <String>[];
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/auth/refresh')) {
          return jsonResponse(session());
        }
        if (r.method == 'GET') {
          return http.Response(
            jsonEncode(
              List.generate(
                20,
                (i) => {
                  'playlistId': 'list-$i',
                  'name': 'Playlist $i',
                  'visibility': 'private',
                  'itemCount': i,
                },
              ),
            ),
            200,
          );
        }
        writes.add(r.url.path);
        if (r.url.path.endsWith('/playlists')) {
          expect((jsonDecode(r.body) as Map)['name'], 'New playlist');
          return jsonResponse({
            'playlistId': 'new',
            'name': 'New playlist',
            'items': [],
          });
        }
        expect((jsonDecode(r.body) as Map)['videoId'], 'video');
        if (mode == 'duplicate') {
          return jsonResponse({'code': 'PLAYLIST_VIDEO_EXISTS'}, 409);
        }
        return jsonResponse({});
      });
      final auth = AuthController(
        ApiClient(client: client),
        MemoryStore('refresh'),
      );
      await auth.restore();
      bool? saved;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () async {
                      saved = await showSavePlaylistSheet(
                        context,
                        auth: auth,
                        videoId: 'video',
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('save-playlist-create')),
        findsOneWidget,
      );
      if (mode == 'new') {
        await capture(tester, 'playlist-picker-light');
        await tester.tap(find.byKey(const ValueKey('save-playlist-create')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('text-entry-input')),
          'New playlist',
        );
        await tester.pump();
        await tester.tap(
          find.widgetWithText(FilledButton, AppStrings.t('common.create')),
        );
      } else {
        await tester.tap(find.byKey(const ValueKey('save-playlist-list-0')));
      }
      await tester.pumpAndSettle();
      expect(find.byType(SavePlaylistSheet), findsNothing);
      expect(saved, mode != 'duplicate');
      expect(writes.length, mode == 'new' ? 2 : 1);
      if (mode == 'new') expect(writes.last, endsWith('/playlists/new/videos'));
      if (mode == 'duplicate') {
        expect(
          find.text(AppStrings.t('playlists.videoAlreadySaved')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    });
  }

  for (final dark in [false, true]) {
    testWidgets('compact popups remain usable with large text, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.8)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    TextButton(
                      onPressed: () => showModalBottomSheet<int>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => const RatingSheet(currentRating: 3),
                      ),
                      child: const Text('Rate'),
                    ),
                    TextButton(
                      onPressed: () => showDialog<bool>(
                        context: context,
                        builder: (_) => ConfirmationDialog(
                          title: 'Xóa bình luận',
                          message: 'Bình luận sẽ được xóa khỏi video này.',
                          confirmLabel: AppStrings.t('common.delete'),
                          destructive: true,
                        ),
                      ),
                      child: const Text('Delete'),
                    ),
                    TextButton(
                      onPressed: () => showDialog<String>(
                        context: context,
                        builder: (_) => TextEntryDialog(
                          title: 'Trả lời bình luận',
                          submitLabel: AppStrings.t('common.send'),
                        ),
                      ),
                      child: const Text('Reply'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Rate'));
      await tester.pumpAndSettle();
      await capture(tester, 'rating-${dark ? 'dark' : 'light'}');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip(AppStrings.t('common.close')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await capture(tester, 'confirm-${dark ? 'dark' : 'light'}');
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.widgetWithText(OutlinedButton, AppStrings.t('common.cancel')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('text-entry-input')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('text-entry-input')),
        'Một phản hồi mới',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetViewInsets();
    });
  }

  test('unsupported PiP reports failure without throwing', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      AppPictureInPicture.channel,
      (_) async => throw PlatformException(code: 'unsupported'),
    );
    expect(await AppPictureInPicture.available(), isFalse);
    expect(await AppPictureInPicture.enter(), isFalse);
    await AppPictureInPicture.configure(automatic: false);
    messenger.setMockMethodCallHandler(AppPictureInPicture.channel, null);
  });
}
