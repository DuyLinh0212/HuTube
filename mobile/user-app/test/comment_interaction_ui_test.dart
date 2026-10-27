import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'mobile_popup_regression_test.dart' show capture;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/core/widgets/confirmation_dialog.dart';
import 'package:user_app/features/content/playback_session.dart';
import 'package:user_app/features/content/watch_screen.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse, session;

void main() {
  setUpAll(() async {
    final fonts = Platform.environment['MOBILE_AUDIT_FONT_DIR'];
    if (fonts != null) {
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
    }
  });
  testWidgets(
    'comments compose, reply, edit and cancel/delete preserve correct content',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      AppStrings.currentLang.value = 'vi';
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final writes = <String>[];
      Map<String, dynamic> comment(String id, String text) => {
        'commentId': id,
        'videoId': 'video',
        'displayName': 'Linh',
        'userId': 'user-1',
        'content': text,
        'status': 'visible',
        'createdAt': '2026-10-24T01:00:00Z',
        'replyCount': 0,
      };
      final client = MockClient((r) async {
        final path = r.url.path;
        if (path.endsWith('/auth/refresh')) return jsonResponse(session());
        if (r.method != 'GET') {
          writes.add('${r.method} $path');
          if (r.method == 'POST') {
            final body = jsonDecode(r.body) as Map;
            return jsonResponse(
              comment(
                body['parentCommentId'] == null ? 'sent' : 'reply',
                body['content'],
              ),
            );
          }
          if (r.method == 'PATCH') {
            return jsonResponse(
              comment('own', (jsonDecode(r.body) as Map)['content']),
            );
          }
          return jsonResponse({});
        }
        if (path.endsWith('/videos/video')) {
          return jsonResponse({
            'videoId': 'video',
            'title': 'Video',
            'channelId': 'channel',
            'stats': {'comments': 1},
          });
        }
        if (path.endsWith('/videos/video/comments')) {
          return jsonResponse({
            'items': [comment('own', 'Original comment')],
            'page': 1,
            'pageSize': 20,
            'total': 1,
          });
        }
        if (path.endsWith('/channels/me')) return jsonResponse({}, 404);
        return jsonResponse({'items': [], 'page': 1, 'total': 0});
      });
      final auth = AuthController(
        ApiClient(client: client),
        MemoryStore('refresh'),
      );
      await auth.restore();
      // Avoid platform playback; this test exercises the complete social UI/API contract.
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
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final preview = find.byKey(const ValueKey('watch-comments-preview'));
      await tester.ensureVisible(preview);
      await tester.tap(preview);
      await tester.pumpAndSettle();
      await capture(tester, 'comments-light');
      final input = find.byKey(const ValueKey('watch-comment-input'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.enterText(input, 'New comment');
      await tester.pump();
      await tester.tap(find.byTooltip(AppStrings.t('common.send')));
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.text('New comment'), findsWidgets);
      final own = find.byKey(const ValueKey('own'));
      final reply = find.descendant(
        of: own,
        matching: find.widgetWithText(TextButton, AppStrings.t('common.reply')),
      );
      await tester.ensureVisible(reply);
      await tester.tap(reply);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('thread-reply-input')),
        'A reply',
      );
      await tester.pump();
      await tester.tap(find.byTooltip(AppStrings.t('common.send')).last);
      await tester.pumpAndSettle();
      expect(writes.where((p) => p.startsWith('POST')).length, 2);
      expect(find.text('A reply'), findsOneWidget);
      await tester.tap(find.byTooltip(AppStrings.t('common.close')).last);
      await tester.pumpAndSettle();
      Future<void> option(String label) async {
        final menu = find
            .descendant(
              of: own,
              matching: find.byTooltip(AppStrings.t('watch.commentOptions')),
            )
            .first;
        await tester.ensureVisible(menu);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(PopupMenuItem<String>, label));
        await tester.pumpAndSettle();
      }

      await option(AppStrings.t('common.edit'));
      await tester.enterText(
        find.byKey(const ValueKey('text-entry-input')),
        'Updated comment',
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, AppStrings.t('common.save')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Updated comment'), findsWidgets);
      await option(AppStrings.t('common.delete'));
      expect(find.byType(ConfirmationDialog), findsOneWidget);
      await tester.tap(
        find.widgetWithText(OutlinedButton, AppStrings.t('common.cancel')),
      );
      await tester.pumpAndSettle();
      expect(writes.where((p) => p.startsWith('DELETE')), isEmpty);
      await option(AppStrings.t('common.delete'));
      await tester.tap(
        find.widgetWithText(FilledButton, AppStrings.t('common.delete')),
      );
      await tester.pumpAndSettle();
      expect(writes.where((p) => p.startsWith('DELETE')).length, 1);
      expect(find.byKey(const ValueKey('own')), findsNothing);
      expect(find.text('Updated comment'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      playback.dispose();
      auth.dispose();
      client.close();
    },
  );
}
