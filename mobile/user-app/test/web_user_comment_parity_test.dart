import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/features/content/playback_session.dart';
import 'package:user_app/features/content/watch_screen.dart';
import 'package:user_app/features/content/widgets/comment_sheets.dart';

import 'auth_test.dart' show MemoryStore, jsonResponse, session;

Map<String, dynamic> comment(String id, {int replies = 0}) => {
  'commentId': id,
  'videoId': 'video',
  'userId': 'user-1',
  'displayName': 'Viewer $id',
  'content': 'Content $id',
  'createdAt': '2026-10-25T00:00:00Z',
  'status': 'visible',
  'likes': 1200000,
  'dislikes': 987654,
  'replyCount': replies,
};

Future<void> openComments(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler, {
  bool dark = false,
  int replies = 5,
}) async {
  tester.view.physicalSize = const Size(360, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client = MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/auth/refresh')) return jsonResponse(session());
    if (path.endsWith('/videos/video')) {
      return jsonResponse({
        'videoId': 'video',
        'channelId': 'channel',
        'title': 'Video',
        'stats': {'comments': 1, 'likes': 1200000, 'dislikes': 987654},
      });
    }
    if (path.endsWith('/videos/video/comments') && request.method == 'GET') {
      return jsonResponse({
        'items': [comment('root', replies: replies)],
        'total': 1,
        'page': 1,
        'pageSize': 20,
      });
    }
    if (path.endsWith('/channels/me')) return jsonResponse({}, 404);
    return handler(request);
  });
  final auth = AuthController(
    ApiClient(client: client),
    MemoryStore('refresh'),
  );
  await auth.restore();
  final playback = PlaybackSession()
    ..videoId = 'video'
    ..ready = true;
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) =>
            WatchScreen(auth: auth, playback: playback, videoId: 'video'),
      ),
    ],
  );
  addTearDown(() {
    router.dispose();
    playback.dispose();
    auth.dispose();
    client.close();
  });
  await tester.pumpWidget(
    MaterialApp.router(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      routerConfig: router,
    ),
  );
  await tester.pumpAndSettle();
  final preview = find.byKey(const ValueKey('watch-comments-preview'));
  await tester.ensureVisible(preview);
  await tester.tap(preview);
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final list = find
        .descendant(
          of: find.byType(CommentThreadSheet).last,
          matching: find.byType(ListView),
        )
        .first;
    final scrollable = find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 100, scrollable: scrollable);
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    ApiClient.invalidateReadCache();
    FlutterSecureStorage.setMockInitialValues({});
    AppStrings.currentLang.value = 'vi';
  });

  test(
    'compact likes use Vietnamese and English units and promote rounded boundaries',
    () {
      for (final language in ['vi', 'en']) {
        AppStrings.currentLang.value = language;
        expect(
          AppStrings.compactLikeCount(1200000),
          language == 'vi' ? '1,2Tr' : '1.2M',
        );
        expect(
          AppStrings.compactLikeCount(1200),
          language == 'vi' ? '1,2N' : '1.2K',
        );
        expect(
          AppStrings.compactLikeCount(999950),
          language == 'vi' ? '1Tr' : '1M',
        );
        expect(
          AppStrings.compactLikeCount(1200000000),
          language == 'vi' ? '1,2T' : '1.2B',
        );
        expect(AppStrings.compactLikeCount(-1), '0');
        expect(AppStrings.compactLikeCount(double.nan), '0');
      }
      AppStrings.currentLang.value = 'vi';
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'three replies, load more, nested replies and reactions in ${dark ? 'dark' : 'light'} theme',
      (tester) async {
        final pages = <int>[];
        final reactions = <String>[];
        final parents = <String>[];
        await openComments(tester, (request) async {
          final path = request.url.path;
          if (path.endsWith('/root/replies')) {
            expect(request.url.queryParameters['pageSize'], '3');
            final page = int.parse(request.url.queryParameters['page']!);
            pages.add(page);
            return jsonResponse({
              'items': [
                for (var i = (page - 1) * 3 + 1; i <= (page == 1 ? 3 : 5); i++)
                  comment('r$i', replies: i == 1 ? 1 : 0),
              ],
              'page': page,
              'pageSize': 3,
              'total': 5,
            });
          }
          if (path.endsWith('/r1/replies')) {
            return jsonResponse({
              'items': [comment('nested')],
              'page': 1,
              'pageSize': 3,
              'total': 1,
            });
          }
          if (path.endsWith('/reaction')) {
            reactions.add(
              request.method == 'DELETE'
                  ? 'clear'
                  : '${jsonDecode(request.body)['type']}',
            );
            return jsonResponse({
              'likes': 1200000,
              'dislikes': 987654,
              'myReaction': request.method == 'DELETE'
                  ? null
                  : jsonDecode(request.body)['type'],
            });
          }
          if (request.method == 'POST' && path.endsWith('/comments')) {
            final body = jsonDecode(request.body) as Map;
            parents.add('${body['parentCommentId']}');
            return jsonResponse({
              ...comment('sent'),
              'content': body['content'],
            });
          }
          return jsonResponse({'items': [], 'total': 0});
        }, dark: dark);
        expect(pages, isEmpty);
        expect(find.text('1,2Tr'), findsWidgets);
        expect(find.text('987.654'), findsNothing);
        await tap(tester, find.byKey(const ValueKey('comment-replies-root')));
        expect(pages, [1]);
        for (final id in ['r1', 'r2', 'r3']) {
          await reveal(tester, find.text('Content $id'));
          expect(find.text('Content $id'), findsOneWidget);
        }
        expect(find.text('Content r4'), findsNothing);
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('r1'))).dx,
          greaterThan(tester.getTopLeft(find.byKey(const ValueKey('root'))).dx),
        );
        await tap(tester, find.byKey(const ValueKey('comment-dislike-r2')));
        await tap(tester, find.byKey(const ValueKey('comment-like-r2')));
        await tap(tester, find.byKey(const ValueKey('comment-like-r2')));
        expect(reactions, ['dislike', 'like', 'clear']);
        final r2 = find.byKey(const ValueKey('r2'));
        expect(
          find.descendant(
            of: r2,
            matching: find.byIcon(Icons.thumb_up_rounded),
          ),
          findsNothing,
        );
        await tap(tester, find.byKey(const ValueKey('comment-replies-r1')));
        final nested = find.byKey(const ValueKey('nested'));
        expect(find.text('Content nested'), findsOneWidget);
        final reply = find.descendant(
          of: nested,
          matching: find.widgetWithText(
            TextButton,
            AppStrings.t('common.reply'),
          ),
        );
        await tap(tester, reply);
        await tester.enterText(
          find.byKey(const ValueKey('thread-reply-input')).last,
          'Nested reply',
        );
        await tester.pump();
        await tap(tester, find.byTooltip(AppStrings.t('common.send')).last);
        expect(parents, ['nested']);
        expect(find.text('Nested reply'), findsOneWidget);
        await tap(tester, find.byTooltip(AppStrings.t('common.close')).last);
        await tap(tester, find.byTooltip(AppStrings.t('common.close')).last);
        await tap(tester, find.byKey(const ValueKey('comment-more-root')));
        expect(pages, [1, 2]);
        await reveal(tester, find.text('Content r5'));
        expect(find.text('Content r5'), findsOneWidget);
        await tap(tester, find.byTooltip(AppStrings.t('common.close')).last);
        expect(find.text('Content r1'), findsNothing);
        await tap(tester, find.byKey(const ValueKey('comment-replies-root')));
        expect(find.text('Content r1'), findsOneWidget);
        expect(find.text('Content r4'), findsNothing);
        expect(pages, [1, 2, 1]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'deleting a reply backfills the first page without skipping later replies',
    (tester) async {
      final rows = [for (var i = 1; i <= 5; i++) comment('r$i')];
      final pages = <int>[];
      await openComments(tester, (request) async {
        if (request.method == 'DELETE') {
          rows.removeWhere((row) => row['commentId'] == 'r1');
          return jsonResponse({});
        }
        if (request.url.path.endsWith('/root/replies')) {
          final page = int.parse(request.url.queryParameters['page']!);
          pages.add(page);
          return jsonResponse({
            'items': rows.skip((page - 1) * 3).take(3).toList(),
            'page': page,
            'pageSize': 3,
            'total': rows.length,
          });
        }
        return jsonResponse({'items': []});
      });
      await tap(tester, find.byKey(const ValueKey('comment-replies-root')));
      await tap(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('r1')),
          matching: find.byTooltip(AppStrings.t('watch.commentOptions')),
        ),
      );
      await tap(
        tester,
        find.widgetWithText(
          PopupMenuItem<String>,
          AppStrings.t('common.delete'),
        ),
      );
      await tap(
        tester,
        find.widgetWithText(FilledButton, AppStrings.t('common.delete')),
      );
      expect(find.text('Content r1'), findsNothing);
      expect(find.text('Content r4'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('comment-more-root')));
      expect(pages, [1, 1, 2]);
      for (var i = 2; i <= 5; i++) {
        await reveal(tester, find.text('Content r$i'));
        expect(find.text('Content r$i'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('failed reply page shows retry without skipping page one', (
    tester,
  ) async {
    var calls = 0;
    await openComments(tester, (request) async {
      if (request.url.path.endsWith('/root/replies')) {
        expect(request.url.queryParameters['page'], '1');
        if (++calls == 1) return jsonResponse({'code': 'REQUEST_FAILED'}, 503);
        return jsonResponse({
          'items': [comment('retried')],
          'page': 1,
          'pageSize': 3,
          'total': 1,
        });
      }
      return jsonResponse({'items': []});
    }, replies: 1);
    await tap(tester, find.byKey(const ValueKey('comment-replies-root')));
    expect(find.text(AppStrings.t('watch.replyLoadError')), findsOneWidget);
    await tap(
      tester,
      find.widgetWithText(TextButton, AppStrings.t('common.retry')),
    );
    expect(find.text('Content retried'), findsOneWidget);
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed send preserves reply text for retry to the same parent', (
    tester,
  ) async {
    var attempts = 0;
    await openComments(tester, (request) async {
      if (request.method == 'POST' && request.url.path.endsWith('/comments')) {
        final body = jsonDecode(request.body) as Map;
        expect(body['parentCommentId'], 'root');
        expect(body['content'], 'Keep my reply');
        if (++attempts == 1) {
          return jsonResponse({'code': 'REQUEST_FAILED'}, 400);
        }
        return jsonResponse({...comment('sent'), 'content': body['content']});
      }
      return jsonResponse({'items': []});
    }, replies: 0);
    final reply = find.descendant(
      of: find.byKey(const ValueKey('root')),
      matching: find.widgetWithText(TextButton, AppStrings.t('common.reply')),
    );
    await tap(tester, reply);
    await tester.enterText(
      find.byKey(const ValueKey('thread-reply-input')).last,
      'Keep my reply',
    );
    await tester.pump();
    await tap(tester, find.byTooltip(AppStrings.t('common.send')).last);
    await tap(tester, find.byTooltip(AppStrings.t('common.close')).last);
    await tap(tester, reply);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('thread-reply-input')).last,
          )
          .controller
          ?.text,
      'Keep my reply',
    );
    await tap(tester, find.byTooltip(AppStrings.t('common.send')).last);
    expect(attempts, 2);
    expect(find.text('Keep my reply'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
