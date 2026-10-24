import 'dart:async';
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
import 'package:user_app/channel/services/channel_service.dart';
import 'package:user_app/channel/state/channel_controller.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/core/storage/app_preferences.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/core/widgets/hutube_widgets.dart';
import 'package:user_app/features/content/content_models.dart';
import 'package:user_app/features/content/explore_screen.dart';
import 'package:user_app/features/content/home_screen.dart';
import 'package:user_app/features/content/video_card.dart';
import 'package:user_app/features/search/search_screen.dart';

import 'auth_test.dart' show MemoryStore, jsonResponse;

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('search filter heading is localized in Vietnamese and English', () {
    final previous = AppStrings.currentLang.value;
    addTearDown(() => AppStrings.currentLang.value = previous);
    AppStrings.currentLang.value = 'vi';
    expect(AppStrings.t('search.sort.title'), 'Sắp xếp theo');
    AppStrings.currentLang.value = 'en';
    expect(AppStrings.t('search.sort.title'), 'Sort by');
  });
  setUpAll(() async {
    // Capture with Android's fallback font instead of the test-only Ahem font.
    final fontDirectory = Platform.environment['MOBILE_AUDIT_FONT_DIR'];
    if (fontDirectory == null) return;
    for (final family in ['Plus Jakarta Sans', 'Roboto', 'MaterialIcons']) {
      final loader = FontLoader(family);
      final filename = family == 'MaterialIcons'
          ? 'materialicons-regular.otf'
          : 'roboto-regular.ttf';
      loader.addFont(
        File(
          '$fontDirectory/$filename',
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
      await loader.load();
    }
  });
  setUp(() {
    ApiClient.invalidateReadCache();
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('returning to a category ignores its older in-flight response', (
    tester,
  ) async {
    final alpha = <Completer<http.Response>>[];
    final beta = Completer<http.Response>();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/feed/explore-hub')) {
        return jsonResponse({
          'rankings': [
            {'categoryId': 'a', 'categoryName': 'Alpha', 'videos': []},
            {'categoryId': 'b', 'categoryName': 'Beta', 'videos': []},
          ],
        });
      }
      if (request.url.queryParameters['categoryId'] == 'a') {
        final response = Completer<http.Response>();
        alpha.add(response);
        return response.future;
      }
      return beta.future;
    });
    final auth = AuthController(ApiClient(client: client), MemoryStore());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: ExploreScreen(auth: auth)),
      ),
    );
    await tester.pumpAndSettle();
    for (final name in ['Alpha', 'Beta', 'Alpha']) {
      // Force a fresh request to exercise generation guards independently of
      // main's intentional in-flight read deduplication.
      ApiClient.invalidateReadCache();
      await tester.tap(find.text(name));
      await tester.pump();
    }
    expect(alpha, hasLength(2));
    Map<String, dynamic> result(String title) => {
      'items': [
        {
          'videoId': title,
          'title': title,
          'channelName': 'Channel',
          'duration': 100,
        },
      ],
      'page': 1,
      'pageSize': 20,
      'total': 1,
    };
    alpha.last.complete(jsonResponse(result('Newest result')));
    await tester.pumpAndSettle();
    alpha.first.complete(jsonResponse(result('Stale result')));
    beta.complete(jsonResponse(result('Other category')));
    await tester.pumpAndSettle();
    expect(find.text('Newest result'), findsOneWidget);
    expect(find.text('Stale result'), findsNothing);
    expect(find.text('Other category'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    client.close();
  });

  test(
    'successful HTML response is an error instead of an empty feed',
    () async {
      final client = MockClient(
        (_) async => http.Response('<html>Proxy</html>', 200),
      );
      addTearDown(client.close);
      final api = ApiClient(client: client);
      await expectLater(
        api.request('GET', '/feed/home'),
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
    },
  );

  test('empty 204 response remains valid for delete operations', () async {
    final client = MockClient((_) async => http.Response('', 204));
    addTearDown(client.close);
    expect(await ApiClient(client: client).request('DELETE', '/item'), isEmpty);
  });

  test('malformed error metadata still preserves HTTP error status', () async {
    final client = MockClient(
      (_) async => jsonResponse({'code': 42, 'traceId': {}, 'detail': []}, 403),
    );
    addTearDown(client.close);
    await expectLater(
      ApiClient(client: client).request('GET', '/private'),
      throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 403)),
    );
  });

  test('pagination stops with an error if the server repeats a page', () async {
    var requests = 0;
    await expectLater(
      loadAllPages<int>((_) async {
        requests++;
        return const PageResult(items: [1], page: 1, pageSize: 1, total: 5);
      }),
      throwsStateError,
    );
    expect(requests, 2);
  });

  test('channel request finishing after disposal does not notify', () async {
    final response = Completer<http.Response>();
    final client = MockClient((_) => response.future);
    final auth = AuthController(ApiClient(client: client), MemoryStore());
    final controller = ChannelController(ChannelService(auth));
    final loading = controller.loadMyChannel();
    controller.dispose();
    response.complete(jsonResponse({'channelId': 'one', 'name': 'One'}));
    await loading;
    auth.dispose();
    client.close();
  });

  test('late channel response cannot overwrite the latest channel', () async {
    final first = Completer<http.Response>();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/first')) return first.future;
      return jsonResponse({'channelId': 'second', 'name': 'Second'});
    });
    final auth = AuthController(ApiClient(client: client), MemoryStore());
    final controller = ChannelController(ChannelService(auth));
    final older = controller.loadChannel('first');
    await controller.loadChannel('second');
    first.complete(jsonResponse({'channelId': 'first', 'name': 'First'}));
    await older;
    expect(controller.viewingChannel?.id, 'second');
    expect(controller.loadingChannel, isFalse);
    controller.dispose();
    auth.dispose();
    client.close();
  });

  for (final dark in [false, true]) {
    final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
    test('readable text and filled buttons, dark=$dark', () {
      final scheme = theme.colorScheme;
      expect(
        contrast(scheme.onSurfaceVariant, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.onSurfaceVariant, scheme.surfaceContainerLow),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.primary, scheme.onPrimary),
        greaterThanOrEqualTo(4.5),
      );
    });

    testWidgets('long pills and emoji avatars support large text, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  HuTubeAvatar(label: ' 👩‍💻 Creator'),
                  HuTubePill(
                    label: 'Nội dung đã lưu trong danh sách phát của bạn',
                    icon: Icons.bookmark_outline,
                  ),
                  HuTubeStateView(
                    icon: Icons.video_library_outlined,
                    title: 'Chưa có video',
                    message: 'Khám phá nội dung yêu thích và lưu để xem sau.',
                    compact: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('👩‍💻'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'recent searches fit a narrow screen with large text, dark=$dark',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({
          AppPreferencesStore.recentSearchesKey:
              '["Flutter","Những chuyến đi và trải nghiệm thật đáng nhớ trong mùa hè"]',
        });
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = MockClient((_) async => jsonResponse({}));
        final auth = AuthController(ApiClient(client: client), MemoryStore());
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(body: SearchScreen(auth: auth)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(AppStrings.t('search.recent')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        auth.dispose();
        client.close();
      },
    );

    testWidgets('home content, video controls and partial errors, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = MockClient((request) async {
        if (request.url.queryParameters['sort'] == 'random') {
          return jsonResponse({'code': 'UNAVAILABLE'}, 503);
        }
        return jsonResponse({
          'items': [
            {
              'videoId': 'video-1',
              'title': 'Một ngày khám phá những điều mới',
              'channelName': 'Dalitu Studio',
              'channelHandle': 'dalitu',
              'duration': 3661,
              'stats': {'views': 12500},
            },
          ],
          'page': 1,
          'pageSize': 20,
          'total': 1,
        });
      });
      final auth = AuthController(ApiClient(client: client), MemoryStore());
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            theme: theme,
            home: Scaffold(
              appBar: AppBar(title: const Text('Dalitu')),
              body: HomeScreen(auth: auth),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(VideoCardTile), findsOneWidget);
      expect(find.byType(HuTubeNotice), findsOneWidget);
      expect(find.text('1:01:01'), findsOneWidget);
      final menu = find.byType(PopupMenuButton<String>);
      final menuSize = tester.getSize(menu);
      expect(menuSize.width, greaterThanOrEqualTo(48));
      expect(menuSize.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
      if (Platform.environment['CAPTURE_MOBILE_AUDIT'] == 'true') {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('../../.work/mobile-audit');
          await directory.create(recursive: true);
          await File(
            '${directory.path}/home-${dark ? 'dark' : 'light'}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    });
  }
}
