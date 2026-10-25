import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/features/content/content_models.dart';
import 'package:user_app/features/content/explore_screen.dart';
import 'package:user_app/features/content/video_card.dart';

import 'auth_test.dart' show MemoryStore, jsonResponse;

void main() {
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
}
