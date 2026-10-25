import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:user_app/auth.dart';
import 'package:user_app/channel/channel_handle.dart';
import 'package:user_app/channel/models/channel_models.dart';
import 'package:user_app/channel/screens/channel_settings_screen.dart';
import 'package:user_app/channel/screens/create_channel_screen.dart';
import 'package:user_app/core/localization/app_strings.dart';

import 'auth_test.dart' show jsonResponse, session;
import 'channel_upload_test.dart' show channelJson, authenticatedController;

Future<void> openSettings(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler,
) async {
  final auth = await authenticatedController((request) async {
    final path = request.url.path;
    if (path.endsWith('/auth/login')) return jsonResponse(session());
    if (path.endsWith('/roles') || path.endsWith('/invitations')) {
      return http.Response(
        '[]',
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'GET' && path.endsWith('/channels/channel-1')) {
      return jsonResponse(channelJson());
    }
    return handler(request);
  });
  addTearDown(auth.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChannelSettingsScreen(
                  auth: auth,
                  channel: ChannelDetail.fromJson(channelJson()),
                ),
              ),
            ),
            child: const Text('Open settings'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open settings'));
  await tester.pumpAndSettle();
}

Future<void> enterHandle(WidgetTester tester, String value) async {
  final field = find.byKey(const ValueKey('channel-settings-handle'));
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump();
}

Future<void> save(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, AppStrings.t('common.save'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    ApiClient.invalidateReadCache();
    FlutterSecureStorage.setMockInitialValues({});
    AppStrings.currentLang.value = 'vi';
  });

  test('handle normalization and validation match the web contract', () {
    expect(normalizeChannelHandle('  @@My.Channel  '), 'my.channel');
    expect(isValidChannelHandle('@My.Channel'), isTrue);
    for (final invalid in ['', 'ab', 'space handle', 'bad/handle', 'x' * 51]) {
      expect(isValidChannelHandle(invalid), isFalse);
    }
    expect(
      AppStrings.apiError(
        ApiFailure(409, 'HANDLE_ALREADY_EXISTS', 'server message'),
      ),
      AppStrings.t('channel.handleTaken'),
    );
  });

  testWidgets(
    'channel settings skip unchanged handles, reject duplicates and ignore stale responses',
    (tester) async {
      final slow = Completer<http.Response>();
      final checks = <String>[];
      Map<String, dynamic>? saved;
      await openSettings(tester, (request) async {
        if (request.url.path.endsWith('/check-handle')) {
          final handle = request.url.queryParameters['handle']!;
          checks.add(handle);
          expect(request.url.queryParameters['currentChannelId'], 'channel-1');
          if (handle == 'slow-handle') return slow.future;
          return jsonResponse({'isAvailable': handle != 'taken-handle'});
        }
        if (request.method == 'PATCH') {
          saved = jsonDecode(request.body) as Map<String, dynamic>;
          return jsonResponse({...channelJson(), ...saved!});
        }
        return jsonResponse({});
      });
      expect(checks, isEmpty);
      await enterHandle(tester, '@HUTUBE-TEST');
      expect(checks, isEmpty);
      await enterHandle(tester, 'bad handle');
      expect(checks, isEmpty);
      expect(find.text(AppStrings.t('channel.handleInvalid')), findsOneWidget);
      await enterHandle(tester, 'slow-handle');
      await enterHandle(tester, 'taken-handle');
      slow.complete(jsonResponse({'isAvailable': true}));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.t('channel.handleTaken')), findsOneWidget);
      final button = find.widgetWithText(
        FilledButton,
        AppStrings.t('common.save'),
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await enterHandle(tester, 'new-handle');
      await tester.pumpAndSettle();
      expect(
        find.text(AppStrings.t('channel.handleAvailable')),
        findsOneWidget,
      );
      await save(tester);
      expect(saved?['handle'], 'new-handle');
      expect(checks, ['slow-handle', 'taken-handle', 'new-handle']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'editing channel name alone never checks or sends the unchanged handle',
    (tester) async {
      var checks = 0;
      Map<String, dynamic>? saved;
      await openSettings(tester, (request) async {
        if (request.url.path.endsWith('/check-handle')) checks++;
        if (request.method == 'PATCH') {
          saved = jsonDecode(request.body) as Map<String, dynamic>;
        }
        return jsonResponse({...channelJson(), ...?saved});
      });
      final name = find.byType(TextFormField).first;
      await tester.ensureVisible(name);
      await tester.enterText(name, 'New channel name');
      await save(tester);
      expect(checks, 0);
      expect(saved?['name'], 'New channel name');
      expect(saved, isNot(contains('handle')));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'new channel suggests a handle and checks only a manual replacement',
    (tester) async {
      final checks = <String>[];
      final auth = await authenticatedController((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return jsonResponse(session());
        }
        if (request.url.path.endsWith('/check-handle')) {
          checks.add(request.url.queryParameters['handle']!);
          return jsonResponse({'isAvailable': true});
        }
        return jsonResponse({});
      });
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CreateChannelScreen(auth: auth)),
      );
      await tester.pumpAndSettle();
      final handle = find.byKey(const ValueKey('channel-create-handle'));
      expect(
        tester.widget<TextFormField>(handle).controller?.text,
        matches(RegExp(r'^linh-[a-f0-9]{8}$')),
      );
      await tester.enterText(find.byType(TextFormField).first, 'Kĩ sư Jura');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(handle).controller?.text,
        matches(RegExp(r'^ki-su-jura-[a-f0-9]{8}$')),
      );
      expect(checks, isEmpty);
      await tester.ensureVisible(handle);
      await tester.enterText(handle, '@My.Handle');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(checks, ['my.handle']);
      await tester.ensureVisible(find.byType(TextFormField).first);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Changed display name',
      );
      expect(
        tester.widget<TextFormField>(handle).controller?.text,
        '@My.Handle',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
