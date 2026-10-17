import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/features/playlists/playlists_screen.dart';

import 'auth_test.dart' show MemoryStore, jsonResponse;

void main() {
  late AuthController auth;
  late List<List<String>> savedOrders;

  setUp(() {
    savedOrders = [];
    final playlist = {
      'playlistId': 'playlist-1',
      'userId': 'owner',
      'name': 'My playlist',
      'visibility': 'private',
      'items': [
        for (var i = 1; i <= 3; i++)
          {
            'videoId': 'v$i',
            'title': 'Video $i',
            'duration': 60,
            'available': true,
          },
      ],
    };
    auth = AuthController(
      ApiClient(
        client: MockClient((request) async {
          if (request.method == 'PUT') {
            expectSync(request.url.path, '/api/v1/playlists/playlist-1/order');
            savedOrders.add(
              List<String>.from(jsonDecode(request.body)['videoIds'] as List),
            );
          } else {
            expectSync(request.url.path, '/api/v1/playlists/playlist-1');
          }
          return jsonResponse(playlist);
        }),
      ),
      MemoryStore(),
    );
    auth.user = {'userId': 'owner'};
  });

  tearDown(() {
    auth.dispose();
    auth.api.client.close();
  });

  Future<void> showPlaylist(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaylistsScreen(auth: auth, playlistId: 'playlist-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final scenario in [
    (
      name: 'drag first video to end',
      from: 0,
      to: 3,
      expected: ['v2', 'v3', 'v1'],
    ),
    (
      name: 'drag last video to start',
      from: 2,
      to: 0,
      expected: ['v3', 'v1', 'v2'],
    ),
    (name: 'drag down one place', from: 0, to: 2, expected: ['v2', 'v1', 'v3']),
  ]) {
    testWidgets(scenario.name, (tester) async {
      await showPlaylist(tester);
      tester
          .widget<SliverReorderableList>(find.byType(SliverReorderableList))
          // Nullable in newer Flutter; required by the Flutter 3.38 constructor.
          // ignore: deprecated_member_use, unnecessary_non_null_assertion
          .onReorder!(scenario.from, scenario.to);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(savedOrders, [scenario.expected]);
    });
  }

  testWidgets('dropping at the original position does not save a new order', (
    tester,
  ) async {
    await showPlaylist(tester);
    tester
        .widget<SliverReorderableList>(find.byType(SliverReorderableList))
        // Nullable in newer Flutter; required by the Flutter 3.38 constructor.
        // ignore: deprecated_member_use, unnecessary_non_null_assertion
        .onReorder!(0, 1);
    await tester.pumpAndSettle();
    expect(savedOrders, isEmpty);
  });

  testWidgets('move down menu keeps its final-index behavior', (tester) async {
    await showPlaylist(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('v1')),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.t('playlists.moveDown')));
    await tester.pumpAndSettle();
    expect(savedOrders, [
      ['v2', 'v1', 'v3'],
    ]);
  });
}
