import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/core/deep_links/content_link.dart';
import 'package:user_app/features/search/search_screen.dart';
import 'package:user_app/features/moderation/appeal_composer.dart';
import 'package:user_app/features/moderation/moderation_service.dart';
import 'package:user_app/features/policies/policies_screen.dart';
import 'package:user_app/features/policies/policy_catalog.dart';
import 'package:user_app/channel/screens/channel_members_screen.dart';
import 'package:user_app/channel/models/channel_models.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse;
import 'profile_links_parity_test.dart' show openPage, channelData, profileData;

http.Response array(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.invalidateReadCache();
    AppStrings.currentLang.value = 'vi';
  });
  test(
    'content links preserve playlist ids, searches, plans and reject invalid destinations',
    () {
      expect(
        contentLinkTarget(Uri.parse('hutube://playlists/playlist-1')),
        '/playlists/playlist-1',
      );
      expect(
        contentLinkTarget(Uri.parse('hutube://channel/my-channel')),
        '/channels/my-channel',
      );
      expect(
        contentLinkTarget(Uri.parse('hutube://search?q=hello&tag=music')),
        '/search?q=hello&tag=music',
      );
      expect(
        contentLinkTarget(Uri.parse('hutube://plans/plan-1')),
        '/plans?planId=plan-1',
      );
      expect(
        contentLinkTarget(Uri.parse('hutube://plans/member?token=abc')),
        '/plans?invitationId=member&invitationToken=abc',
      );
      for (final bad in [
        'hutube://playlists/a%2Fb',
        'hutube://user:password@watch/a',
        'https://other.test/watch/a',
      ]) {
        expect(contentLinkTarget(Uri.parse(bad)), isNull);
      }
    },
  );
  testWidgets(
    'search finds several channels without any videos and paginates channel-only results',
    (tester) async {
      var videos = 0;
      final pages = <String>[];
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/categories')) return array([]);
        if (r.url.path.endsWith('/channels/search')) {
          pages.add(r.url.queryParameters['page']!);
          final page = r.url.queryParameters['page'] == '2' ? 2 : 1;
          return jsonResponse({
            'items': [
              {
                'channelId': '$page',
                'name': 'Channel $page',
                'handle': 'channel$page',
              },
            ],
            'page': page,
            'pageSize': 20,
            'total': 21,
          });
        }
        if (r.url.path.endsWith('/videos/search')) videos++;
        return jsonResponse({'items': [], 'page': 1, 'total': 0});
      });
      final auth = AuthController(ApiClient(client: client), MemoryStore());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchScreen(auth: auth, initialQuery: 'Channel'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Channel 1'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(ChoiceChip, AppStrings.t('search.resultChannels')),
      );
      await tester.pumpAndSettle();
      final previous = videos;
      final more = find.widgetWithText(
        OutlinedButton,
        AppStrings.t('search.loadMore'),
      );
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(pages.last, '2');
      expect(videos, previous);
      expect(find.text('Channel 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    },
  );
  testWidgets('search routes preserve tag and category filters', (
    tester,
  ) async {
    Uri? query;
    final client = MockClient((r) async {
      if (r.url.path.endsWith('/categories')) {
        return array([
          {'categoryId': 'category-a', 'name': 'Music'},
        ]);
      }
      if (r.url.path.endsWith('/videos/search')) query = r.url;
      return jsonResponse({'items': [], 'page': 1, 'total': 0});
    });
    final auth = AuthController(ApiClient(client: client), MemoryStore());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchScreen(
            auth: auth,
            initialQuery: 'nhạc',
            initialTag: 'music',
            initialCategoryId: 'category-a',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(query?.queryParameters['q'], 'nhạc');
    expect(query?.queryParameters['tag'], 'music');
    expect(query?.queryParameters['categoryId'], 'category-a');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    client.close();
  });
  testWidgets('policy search filters content and follows selected group', (
    tester,
  ) async {
    final client = MockClient(
      (_) async => array([
        {
          'name': 'Community rules',
          'group': 'guidelines',
          'description': 'Respect other people.',
        },
        {
          'name': 'Privacy details',
          'group': 'privacy',
          'description': 'How account data is handled.',
        },
      ]),
    );
    final auth = AuthController(ApiClient(client: client), MemoryStore());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PoliciesScreen(auth: auth)),
      ),
    );
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('policy-search'));
    await tester.ensureVisible(search);
    await tester.enterText(search, 'account data');
    await tester.pumpAndSettle();
    expect(find.text('Community rules'), findsNothing);
    expect(find.text('Privacy details'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('policy-group-all')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.textContaining(policyLabel('policies.guidelines')).last,
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.t('search.noResults')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('policy-group-guidelines')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(policyLabel('policies.privacy')).last);
    await tester.pumpAndSettle();
    expect(find.text('Privacy details'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    client.close();
  });
  for (final failure in [false, true]) {
    testWidgets('channel members role change and rollback, failure=$failure', (
      tester,
    ) async {
      var role = 'editor';
      Map<String, dynamic>? patch;
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/roles')) {
          return array([
            {'code': 'editor', 'name': 'Editor'},
            {'code': 'manager', 'name': 'Manager'},
          ]);
        }
        if (r.method == 'PATCH') {
          patch = jsonDecode(r.body);
          if (failure) return jsonResponse({'code': 'FAIL'}, 503);
          role = patch!['roleCode'];
          return jsonResponse({});
        }
        return array([
          {
            'userId': 'collaborator',
            'displayName': 'Collaborator',
            'email': 'member@example.test',
            'roleCode': role,
          },
        ]);
      });
      final auth = AuthController(ApiClient(client: client), MemoryStore())
        ..user = profileData;
      await openPage(
        tester,
        ChannelMembersScreen(
          auth: auth,
          channel: ChannelDetail.fromJson(channelData),
        ),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.t('channel.roleManager')).last);
      await tester.pumpAndSettle();
      expect(patch?['roleCode'], 'manager');
      expect(
        tester
            .state<FormFieldState<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .value,
        failure ? 'editor' : 'manager',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    });
  }
  test('evidence validates type and size before uploading', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return jsonResponse({});
    });
    final auth = AuthController(ApiClient(client: client), MemoryStore())
      ..user = profileData;
    final service = ModerationService(auth);
    await expectLater(
      service.uploadEvidence(
        'appeal',
        XFile.fromData(Uint8List(10), name: 'bad.exe'),
      ),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      service.uploadEvidence(
        'appeal',
        XFile.fromData(
          Uint8List(10 * 1024 * 1024 + 1),
          path: 'huge.pdf',
          name: 'huge.pdf',
        ),
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(requests, 0);
    auth.dispose();
    client.close();
  });
  testWidgets(
    'failed evidence upload retries the existing appeal without creating a duplicate',
    (tester) async {
      var appeals = 0, uploads = 0;
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/evidence')) {
          uploads++;
          return uploads == 1
              ? jsonResponse({'code': 'FAIL'}, 503)
              : jsonResponse({'appealId': 'appeal-1'});
        }
        appeals++;
        return jsonResponse({'appealId': 'appeal-1'});
      });
      final auth = AuthController(ApiClient(client: client), MemoryStore())
        ..user = profileData;
      await openPage(
        tester,
        Scaffold(
          body: AppealComposer(
            auth: auth,
            targetId: 'mine',
            targetType: 'channel',
            pickEvidence: () async => XFile.fromData(
              Uint8List.fromList([37, 80, 68, 70]),
              path: 'evidence.pdf',
              name: 'evidence.pdf',
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('appeal-reason')),
        'Please review this channel decision.',
      );
      final attach = find.widgetWithText(
        OutlinedButton,
        AppStrings.t('moderation.attachEvidence'),
      );
      await tester.ensureVisible(attach);
      await tester.tap(attach);
      await tester.pumpAndSettle();
      final send = find.widgetWithText(
        FilledButton,
        AppStrings.t('moderation.sendAppeal'),
      );
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(appeals, 1);
      expect(uploads, 1);
      final retry = find.widgetWithText(
        FilledButton,
        AppStrings.t('common.retry'),
      );
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(appeals, 1);
      expect(uploads, 2);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    },
  );
}
