import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/features/creator/creator_hub_screen.dart';
import 'package:user_app/features/creator/video_upload_screen.dart';
import 'package:user_app/features/playlists/playlists_screen.dart';

import 'auth_test.dart' show MemoryStore, jsonResponse, session;

void main() {
  testWidgets('create playlist opens the form and saves through the API', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    var created = false;
    final auth = AuthController(
      ApiClient(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            return jsonResponse(session());
          }
          if (request.url.path.endsWith('/playlists') &&
              request.method == 'POST') {
            expect(jsonDecode(request.body)['name'], 'Danh sách mới');
            created = true;
            return jsonResponse({
              'playlistId': 'new-playlist',
              'name': 'Danh sách mới',
              'userId': 'user-1',
              'items': [],
            });
          }
          return jsonResponse({'items': []});
        }),
      ),
      MemoryStore('refresh'),
    );
    await auth.restore();
    final router = GoRouter(
      initialLocation: '/playlists?create=true',
      routes: [
        GoRoute(
          path: '/playlists',
          builder: (_, state) => Scaffold(
            body: PlaylistsScreen(
              auth: auth,
              openCreate: state.uri.queryParameters['create'] == 'true',
            ),
          ),
        ),
        GoRoute(
          path: '/playlists/:id',
          builder: (_, _) => const Scaffold(body: Text('Created playlist')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
    );
    await tester.pumpAndSettle();
    final name = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(name, 'Danh sách mới');
    final submit = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.widgetWithText(FilledButton, 'Tạo playlist'),
    );
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(created, isTrue);
    expect(router.state.uri.path, '/playlists/new-playlist');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    auth.dispose();
  });

  testWidgets('create video opens upload after resolving the managed channel', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final auth = AuthController(
      ApiClient(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            return jsonResponse(session());
          }
          if (request.url.path.endsWith('/channels/accessible')) {
            return http.Response(
              jsonEncode([
                {
                  'channelId': 'channel-1',
                  'name': 'Kênh của tôi',
                  'handle': 'my-channel',
                  'isOwner': true,
                },
              ]),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return jsonResponse({'items': []});
        }),
      ),
      MemoryStore('refresh'),
    );
    await auth.restore();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: CreatorHubScreen(auth: auth, openUpload: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(VideoUploadScreen), findsOneWidget);
    // Flutter 3.47 reports this paint obstruction itself. Check it explicitly
    // so older local SDKs also catch file-picker ink hidden by a background.
    final uploadTiles = find.descendant(
      of: find.byType(VideoUploadScreen),
      matching: find.byType(ListTile),
    );
    expect(uploadTiles, findsWidgets);
    for (final element in uploadTiles.evaluate()) {
      Widget? obstruction;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is Material) return false;
        final color = switch (ancestor.widget) {
          ColoredBox(:final color) => color,
          DecoratedBox(decoration: BoxDecoration(:final color)) => color,
          DecoratedBox(decoration: ShapeDecoration(:final color)) => color,
          _ => null,
        };
        if (color != null && color.a > 0) {
          obstruction = ancestor.widget;
          return false;
        }
        return true;
      });
      expect(
        obstruction,
        isNull,
        reason: 'Upload picker ink must remain visible',
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    auth.dispose();
  });
}
