import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/features/content/playback_session.dart';
import 'package:user_app/features/content/watch_screen.dart';

import 'auth_test.dart' show MemoryStore, jsonResponse;

void main() {
  setUp(ApiClient.invalidateReadCache);
  for (final dark in [false, true]) {
    testWidgets('watch comments retry and themed action icons, dark=$dark', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var fail = true;
      final commentRequests = <String>[];
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/videos/video-a')) {
          return jsonResponse({
            'videoId': 'video-a',
            'channelName': 'Channel',
            'title': 'Video',
            'stats': {'comments': 64},
          });
        }
        if (path.endsWith('/comments')) {
          commentRequests.add(
            '${request.url.queryParameters['sort']}:${request.url.queryParameters['page']}',
          );
          if (fail) return jsonResponse({'code': 'INTERNAL_ERROR'}, 500);
          final page = int.parse(request.url.queryParameters['page']!);
          return jsonResponse({
            'items': List.generate(
              20,
              (i) => {
                'commentId': 'comment-${(page - 1) * 20 + i}',
                'videoId': 'video-a',
                'displayName': 'Viewer',
                'content': 'Comment ${(page - 1) * 20 + i}',
              },
            ),
            'page': page,
            'pageSize': 20,
            'total': 64,
          });
        }
        return jsonResponse({'items': []});
      });
      final auth = AuthController(ApiClient(client: client), MemoryStore());
      auth.restoring = false;
      final playback = PlaybackSession()
        ..videoId = 'video-a'
        ..ready = true;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                WatchScreen(auth: auth, playback: playback, videoId: 'video-a'),
          ),
        ],
      );
      final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
      await tester.pumpWidget(
        MaterialApp.router(theme: theme, routerConfig: router),
      );
      await tester.pumpAndSettle();

      // Asset and vector watch icons share a size and readable themed foreground.
      final actions = find.byType(ActionChip);
      expect(actions, findsWidgets);
      for (final element in actions.evaluate()) {
        final chip = element.widget as ActionChip;
        expect(chip.shape, isA<StadiumBorder>());
        final avatar = chip.avatar!;
        final Color? foreground;
        if (avatar is Image) {
          expect(avatar.width, 18);
          expect(avatar.height, 18);
          expect((avatar.image as AssetImage).assetName, endsWith('.webp'));
          foreground = avatar.color;
        } else {
          expect(avatar, isA<Icon>());
          final icon = avatar as Icon;
          expect(icon.size, 18);
          foreground = icon.color;
        }
        expect(foreground, chip.labelStyle!.color);
        expect(
          foreground,
          anyOf(theme.colorScheme.onSurface, theme.colorScheme.primary),
        );
      }

      final preview = find.byKey(const ValueKey('watch-comments-preview'));
      await tester.scrollUntilVisible(
        preview,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(
        find.text(AppStrings.t('watch.commentsServerError')),
        findsOneWidget,
      );
      expect(find.text(AppStrings.t('creator.noComments')), findsNothing);
      expect(find.text(AppStrings.t('watch.noComments')), findsNothing);
      for (final element in find.byType(ChoiceChip).evaluate()) {
        final chip = element.widget as ChoiceChip;
        expect(
          chip.shape ?? Theme.of(element).chipTheme.shape,
          isA<StadiumBorder>(),
        );
      }
      fail = false;
      final retry = find.byKey(const ValueKey('watch-comments-retry-more'));
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('watch-comments-panel')),
          matching: find.text('Comment 0'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(AppStrings.t('watch.commentsServerError')),
        findsNothing,
      );

      // An unsuccessful sort change must retry page 1 even with old items present.
      fail = true;
      await tester.tap(
        find.widgetWithText(
          ChoiceChip,
          AppStrings.t('creator.commentSortNewest'),
        ),
      );
      await tester.pumpAndSettle();
      expect(commentRequests.last, 'newest:1');
      fail = false;
      await tester.scrollUntilVisible(
        retry,
        350,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('watch-comments-panel')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(commentRequests.last, 'newest:1');
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(commentRequests.last, 'newest:2');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      playback.dispose();
      auth.dispose();
      client.close();
    });

    testWidgets('selection chips use pill borders across screens, dark=$dark', (
      tester,
    ) async {
      final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Wrap(
              children: [
                ChoiceChip(
                  label: const Text('Choice'),
                  selected: true,
                  onSelected: (_) {},
                ),
                FilterChip(
                  label: const Text('Filter'),
                  selected: false,
                  onSelected: (_) {},
                ),
                InputChip(label: const Text('Input'), onDeleted: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(theme.chipTheme.shape, isA<StadiumBorder>());
      expect(tester.takeException(), isNull);
    });
  }
}
