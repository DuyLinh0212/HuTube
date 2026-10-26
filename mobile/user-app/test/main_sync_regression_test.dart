import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/channel/screens/channel_screen.dart';
import 'package:user_app/channel/screens/channel_settings_screen.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/core/network/read_cache.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/core/widgets/content_filters.dart';
import 'package:user_app/features/content/library_screen.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse, session;
import 'mobile_popup_regression_test.dart' show capture;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:user_app/features/account/account_settings_screen.dart';
import 'package:user_app/features/notifications/notification_center.dart';
import 'package:user_app/features/content/content_models.dart';
import 'package:user_app/features/content/explore_screen.dart';
import 'package:user_app/features/content/video_card.dart';

void main() {
  setUpAll(() async {
    final fonts = Platform.environment['MOBILE_AUDIT_FONT_DIR'];
    if (fonts == null) return;
    for (final family in ['Plus Jakarta Sans', 'Roboto', 'MaterialIcons']) {
      final file = family == 'MaterialIcons'
          ? 'materialicons-regular.otf'
          : 'roboto-regular.ttf';
      final loader = FontLoader(family);
      loader.addFont(
        File('$fonts/$file').readAsBytes().then(ByteData.sublistView),
      );
      await loader.load();
    }
  });
  setUp(() {
    ApiClient.invalidateReadCache();
    FlutterSecureStorage.setMockInitialValues({});
    AppStrings.currentLang.value = 'vi';
  });

  test('invalidated cache cannot be repopulated by an older request', () async {
    final uri = Uri.parse('https://api.test/api/v1/videos');
    final old = Completer<dynamic>();
    final first = ReadCache.read('GET', uri, null, null, () => old.future);
    final shared = ReadCache.read(
      'GET',
      uri,
      null,
      null,
      () => throw StateError('must deduplicate'),
    );
    ReadCache.clear();
    final fresh = await ReadCache.read(
      'GET',
      uri,
      null,
      null,
      () async => {'title': 'new'},
    );
    old.complete({'title': 'old'});
    expect(await first, {'title': 'old'});
    expect(await shared, {'title': 'old'});
    fresh['title'] = 'changed by consumer';
    expect(
      await ReadCache.read(
        'GET',
        uri,
        null,
        null,
        () => throw StateError('must use fresh snapshot'),
      ),
      {'title': 'new'},
    );
  });

  testWidgets('library loads pages on demand and retains history filters', (
    tester,
  ) async {
    final requests = <Uri>[];
    final client = MockClient((r) async {
      if (r.url.path.endsWith('/auth/refresh')) return jsonResponse(session());
      requests.add(r.url);
      final page = int.tryParse(r.url.queryParameters['page'] ?? '') ?? 1;
      return jsonResponse({
        'items': [
          {
            'videoId': '${r.url.path}-$page',
            'title': 'Page $page',
            'channelName': 'Channel',
          },
        ],
        'page': page,
        'pageSize': 1,
        'total': 2,
      });
    });
    final auth = AuthController(
      ApiClient(client: client),
      MemoryStore('refresh'),
    );
    await auth.restore();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: LibraryScreen(auth: auth)),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.queryParameters['page'] == '2'), isEmpty);
    tester.widget<ContentFilters>(find.byType(ContentFilters)).onChanged(
      'lessons',
      {'sort': 'oldest', 'dateRange': 'week'},
    );
    await tester.pumpAndSettle();
    final more = find.byKey(const ValueKey('library-load-more'));
    await tester.scrollUntilVisible(
      more,
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(more);
    await tester.pumpAndSettle();
    final historyPage = requests.singleWhere(
      (r) => r.path.endsWith('/history') && r.queryParameters['page'] == '2',
    );
    expect(historyPage.queryParameters['sort'], 'oldest');
    expect(historyPage.queryParameters['q'], 'lessons');
    expect(historyPage.queryParameters['dateRange'], 'week');
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-load-more')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    client.close();
  });

  for (final dark in [false, true]) {
    testWidgets('neutral channel manage row opens settings, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/auth/refresh')) {
          return jsonResponse(session());
        }
        if (r.url.path.contains('/channels/') &&
            !r.url.path.endsWith('/playlists')) {
          return jsonResponse({
            'channelId': 'one',
            'name': 'Kênh của bạn',
            'handle': 'danh',
            'isOwner': true,
          });
        }
        return jsonResponse({
          'items': [],
          'page': 1,
          'pageSize': 20,
          'total': 0,
        });
      });
      final auth = AuthController(
        ApiClient(client: client),
        MemoryStore('refresh'),
      );
      await auth.restore();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            home: ChannelScreen(auth: auth, channelOrHandle: 'danh'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final manage = find.byKey(const ValueKey('channel-manage-action'));
      expect(manage, findsOneWidget);
      expect(tester.widget(manage), isA<ListTile>());
      await tester.ensureVisible(manage);
      await capture(tester, 'channel-neutral-${dark ? 'dark' : 'light'}');
      await tester.tap(manage);
      await tester.pumpAndSettle();
      expect(find.byType(ChannelSettingsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    });
  }

  group('independent section loading', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));
    testWidgets(
      'account requests run together and channel failure does not hide counts',
      (tester) async {
        final channel = Completer<http.Response>();
        final paths = <String>[];
        final client = MockClient((r) async {
          final path = r.url.path;
          if (path.endsWith('/auth/refresh')) return jsonResponse(session());
          paths.add(path);
          if (path.endsWith('/channels/me')) return channel.future;
          if (path.endsWith('/account/profile')) {
            return jsonResponse({'displayName': 'Profile'});
          }
          if (path.endsWith('/playlists')) {
            return http.Response(
              jsonEncode(List.generate(11, (i) => {'playlistId': '$i'})),
              200,
            );
          }
          if (path.endsWith('/subscriptions')) {
            return http.Response(
              jsonEncode(List.generate(17, (i) => {'channelId': '$i'})),
              200,
            );
          }
          return jsonResponse({
            'items': [],
            'total': 29,
            'page': 1,
            'pageSize': 20,
          });
        });
        final auth = AuthController(
          ApiClient(client: client),
          MemoryStore('refresh'),
        );
        await auth.restore();
        final notifications = NotificationCenter(auth);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: AccountSettingsScreen(
              auth: auth,
              notifications: notifications,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(paths.any((p) => p.endsWith('/account/profile')), isTrue);
        expect(paths.any((p) => p.endsWith('/library/liked')), isTrue);
        channel.complete(jsonResponse({'code': 'FAILED'}, 500));
        await tester.pumpAndSettle();
        expect(find.text('11'), findsOneWidget);
        expect(find.text('17'), findsOneWidget);
        expect(find.text('29'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        notifications.dispose();
        auth.dispose();
        client.close();
      },
    );
    testWidgets('liked library starts while history is still pending', (
      tester,
    ) async {
      final history = Completer<http.Response>();
      var liked = 0;
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/auth/refresh')) {
          return jsonResponse(session());
        }
        if (r.url.path.endsWith('/history')) return history.future;
        if (r.url.path.endsWith('/liked')) liked++;
        return jsonResponse({
          'items': [],
          'page': 1,
          'pageSize': 20,
          'total': 0,
        });
      });
      final auth = AuthController(
        ApiClient(client: client),
        MemoryStore('refresh'),
      );
      await auth.restore();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: LibraryScreen(auth: auth)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(liked, 1);
      history.complete(
        jsonResponse({'items': [], 'page': 1, 'pageSize': 20, 'total': 0}),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    });
  });

  group('library and explore interactions', () {
    setUp(() {
      ApiClient.invalidateReadCache();
      AppStrings.currentLang.value = 'vi';
    });

    testWidgets(
      'history uses m:ss and h:mm:ss at minute and hour boundaries in both languages',
      (tester) async {
        tester.view.physicalSize = const Size(320, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final language in ['vi', 'en']) {
          AppStrings.currentLang.value = language;
          for (final entry in {
            59: '0:59',
            60: '1:00',
            3599: '59:59',
            3600: '1:00:00',
            3660: '1:01:00',
          }.entries) {
            final video = LibraryVideo.fromHistoryJson({
              'videoId': 'video',
              'channelId': 'channel',
              'channelName': 'Channel',
              'title': 'History video',
              'duration': 4000,
              'watchedSeconds': entry.key,
            });
            await tester.pumpWidget(
              MaterialApp(
                theme: language == 'vi'
                    ? AppTheme.lightTheme
                    : AppTheme.darkTheme,
                home: Scaffold(body: VideoCardTile(video: video)),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.textContaining(
                AppStrings.format('library.watchedFor', {'time': entry.value}),
              ),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'ranking topics scroll by touch and show the selected category without redundant view-all buttons',
      (tester) async {
        tester.view.physicalSize = const Size(360, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final categories = <String>[];
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/feed/explore-hub')) {
            return jsonResponse({
              'rankings': [
                for (var i = 0; i < 12; i++)
                  {
                    'categoryId': 'category-$i',
                    'categoryName': 'Category $i',
                    'videos': [],
                  },
              ],
            });
          }
          final category = request.url.queryParameters['categoryId'];
          if (category != null) {
            categories.add(category);
            return jsonResponse({
              'items': [
                {
                  'videoId': 'ranked',
                  'title': 'Selected category video',
                  'channelName': 'Channel',
                },
              ],
              'page': 1,
              'pageSize': 12,
              'total': 1,
            });
          }
          return jsonResponse({'items': []});
        });
        final auth = AuthController(ApiClient(client: client), MemoryStore());
        addTearDown(() {
          auth.dispose();
          client.close();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(body: ExploreScreen(auth: auth)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(AppStrings.t('explore.viewAll')), findsNothing);
        final tabs = find.byType(SingleChildScrollView).first;
        await tester.drag(tabs, const Offset(-2500, 0));
        await tester.pumpAndSettle();
        final last = find.widgetWithText(ChoiceChip, 'Category 11');
        expect(tester.getCenter(last).dx, inExclusiveRange(0, 360));
        await tester.tap(last);
        await tester.pumpAndSettle();
        expect(categories, ['category-11']);
        expect(find.text('Selected category video'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });
}
