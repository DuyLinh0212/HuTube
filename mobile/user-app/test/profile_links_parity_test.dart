import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/account/models/account_models.dart';
import 'package:user_app/account/services/account_service.dart';
import 'package:user_app/core/storage/app_preferences.dart';
import 'package:user_app/account/screens/edit_profile_screen.dart';
import 'package:user_app/channel/models/channel_models.dart';
import 'package:user_app/channel/models/channel_links.dart';
import 'package:user_app/channel/screens/channel_links_screen.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/features/account/account_settings_screen.dart';
import 'package:user_app/features/notifications/notification_center.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse;

final profileData = {
  'userId': 'viewer',
  'username': 'cong-danh',
  'displayName': 'Công Danh',
  'email': 'test@example.test',
  'bio': 'Hello',
};
final channelData = {
  'channelId': 'mine',
  'name': 'My channel',
  'handle': 'mine',
  'isOwner': true,
  'settings': jsonEncode({
    'trailerVideoId': 'trailer',
    'watermark': true,
    'links': [
      {'platform': 'other', 'title': 'Website', 'url': 'https://example.test'},
    ],
  }),
};

Future<void> openPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => page),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.invalidateReadCache();
    AppStrings.currentLang.value = 'vi';
  });
  test('public links parse legacy data and reject non-web schemes', () {
    expect(
      channelLinks(
        '[{"label":"Web","url":"https://example.test"}]',
      ).single['title'],
      'Web',
    );
    for (final bad in [
      'javascript:alert(1)',
      'file:///tmp/private',
      'https://user:password@example.test',
      'https://',
    ]) {
      expect(isPublicWebLink(bad), isFalse);
    }
    expect(channelLinks('{"links":[{"url":"javascript:alert(1)"}]}'), isEmpty);
    expect(
      channelLinks(
        '{"links":[{"url":"javascript:alert(1)"}]}',
        validOnly: false,
      ),
      hasLength(1),
    );
  });
  test(
    'playback preferences persist locally while account settings use supported API fields',
    () async {
      Map<String, dynamic>? sent;
      final client = MockClient((r) async {
        if (r.method == 'PUT') sent = jsonDecode(r.body);
        return jsonResponse({
          'language': 'en',
          'theme': 'dark',
          'keepSubscriptionsPrivate': true,
          'keepPlaylistsPrivate': true,
        });
      });
      final auth = AuthController(ApiClient(client: client), MemoryStore())
        ..user = profileData;
      final service = AccountService(auth);
      final before = await service.getPreferences();
      await service.updatePreferences(
        before.copyWith(autoplayNext: false, defaultPlaybackQuality: '720p'),
      );
      final after = await service.getPreferences();
      expect(after.autoplayNext, isFalse);
      expect(after.defaultPlaybackQuality, '720p');
      expect(sent?['language'], 'en');
      expect(sent, isNot(contains('autoplayNext')));
      expect(sent, isNot(contains('defaultPlaybackQuality')));
      expect(await const AppPreferencesStore().readAutoplayNext(), isFalse);
      auth.dispose();
      client.close();
    },
  );
  testWidgets(
    'settings Edit links opens the channel links editor rather than profile',
    (tester) async {
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/channels/me') ||
            r.url.path.endsWith('/channels/mine')) {
          return jsonResponse(channelData);
        }
        if (r.url.path.endsWith('/account/profile')) {
          return jsonResponse(profileData);
        }
        return jsonResponse({'items': []});
      });
      final auth = AuthController(ApiClient(client: client), MemoryStore())
        ..user = profileData;
      final notifications = NotificationCenter(auth);
      await openPage(
        tester,
        AccountSettingsScreen(auth: auth, notifications: notifications),
      );
      final edit = find.byKey(const ValueKey('settings-edit-links'));
      await tester.scrollUntilVisible(
        edit,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.byType(ChannelLinksScreen), findsOneWidget);
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(find.text('Website'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      notifications.dispose();
      auth.dispose();
      client.close();
    },
  );
  testWidgets(
    'profile loads saved region, saves fields, updates identity and preserves privacy settings',
    (tester) async {
      Map<String, dynamic>? patch, preferences;
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/account/settings')) {
          if (r.method == 'PUT') preferences = jsonDecode(r.body);
          return jsonResponse(
            preferences ??
                {
                  'location': 'Nhật Bản',
                  'language': 'en',
                  'theme': 'dark',
                  'keepSubscriptionsPrivate': true,
                  'keepPlaylistsPrivate': true,
                },
          );
        }
        patch = jsonDecode(r.body);
        return jsonResponse({...profileData, ...patch!});
      });
      final auth = AuthController(ApiClient(client: client), MemoryStore())
        ..user = profileData;
      await openPage(
        tester,
        EditProfileScreen(
          auth: auth,
          profile: UserProfile.fromJson(profileData),
        ),
      );
      await tester.scrollUntilVisible(
        find.byType(DropdownButtonFormField<String>),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text(AppStrings.t('editProfile.countryJapan')),
        findsOneWidget,
      );
      final save = find.byKey(const ValueKey('profile-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('profile-display-name')),
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-display-name')),
        'Tên mới',
      );
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(patch?['displayName'], 'Tên mới');
      expect(preferences?['location'], 'Nhật Bản');
      expect(preferences, {'location': 'Nhật Bản'});
      expect(auth.user?['displayName'], 'Tên mới');
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    },
  );
  testWidgets('profile validates empty name and confirms leaving dirty form', (
    tester,
  ) async {
    final client = MockClient(
      (_) async => jsonResponse({'location': 'Việt Nam'}),
    );
    final auth = AuthController(ApiClient(client: client), MemoryStore())
      ..user = profileData;
    await openPage(
      tester,
      EditProfileScreen(auth: auth, profile: UserProfile.fromJson(profileData)),
    );
    await tester.enterText(
      find.byKey(const ValueKey('profile-display-name')),
      ' ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('profile-save')));
    await tester.pumpAndSettle();
    expect(
      find.text(AppStrings.t('editProfile.displayNameRequired')),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.t('form.discardTitle')), findsOneWidget);
    await tester.tap(find.text(AppStrings.t('form.discard')));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    client.close();
  });
  testWidgets(
    'link editor saves actual URLs and preserves settings changed since opening',
    (tester) async {
      Map<String, dynamic>? patch;
      var reads = 0;
      final client = MockClient((r) async {
        if (r.method == 'PATCH') {
          patch = jsonDecode(r.body);
          return jsonResponse({...channelData, ...patch!});
        }
        reads++;
        final settings =
            jsonDecode(channelData['settings'] as String)
                as Map<String, dynamic>;
        if (reads > 1) settings['externalUpdate'] = 'keep';
        return jsonResponse({...channelData, 'settings': jsonEncode(settings)});
      });
      final auth = AuthController(ApiClient(client: client), MemoryStore())
        ..user = profileData;
      await openPage(
        tester,
        ChannelLinksScreen(
          auth: auth,
          channel: ChannelDetail.fromJson(channelData),
        ),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('link-url-0')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const ValueKey('link-url-0')),
        'javascript:alert(1)',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('links-save')));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.t('channel.linkUrlError')), findsOneWidget);
      expect(patch, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('link-url-0')),
        'https://new.example.test/profile',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('links-save')));
      await tester.pumpAndSettle();
      final saved = jsonDecode(patch!['settings']);
      expect(saved['links'][0]['url'], 'https://new.example.test/profile');
      expect(saved['trailerVideoId'], 'trailer');
      expect(saved['externalUpdate'], 'keep');
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    },
  );
}
