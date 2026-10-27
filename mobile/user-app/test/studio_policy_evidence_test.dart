import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/features/moderation/appeal_evidence.dart';
import 'package:user_app/features/policies/policy_catalog.dart';
import 'package:user_app/features/policies/policy_document.dart';
import 'package:user_app/features/policies/policy_reference.dart';
import 'package:user_app/features/policies/policies_screen.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse, session;

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.invalidateReadCache();
    AppStrings.currentLang.value = 'vi';
  });
  test(
    'policy reference codes stay synchronized with user-web and translations cover both languages',
    () {
      final source = File(
        '../../frontend/user-web/src/app/features/policy/public-policy-page.ts',
      ).readAsStringSync();
      final webCodes = RegExp(
        "code: '([A-Z_]+)'",
      ).allMatches(source).map((m) => m[1]).toSet();
      final references = [
        for (final group in policyGroups) ...policyReference[group] as List,
      ];
      expect(references.length, 30);
      expect(references.map((p) => p['code']).toSet(), webCodes);
      for (final lang in ['vi', 'en']) {
        AppStrings.currentLang.value = lang;
        final catalog = policyCatalog([]);
        for (final p in catalog) {
          expect('${p['name']}', isNot(startsWith('policy.')));
          expect('${p['content']}', isNot(startsWith('policy.')));
          expect(p['rules'], isNotEmpty);
        }
        expect(
          policyLabel('policies.enforcement'),
          isNot(startsWith('policies.')),
        );
      }
    },
  );
  test(
    'published policies override matching reference codes; legacy groups and retired codes match web',
    () {
      final catalog = policyCatalog([
        {
          'code': 'CHILD_SAFETY',
          'name': 'Latest title',
          'content': 'Latest rules',
          'group': 'content',
          'version': 'v9',
        },
        {
          'code': 'DOXXING_PRIVACY',
          'name': 'Privacy update',
          'content': 'Private data',
          'group': 'all',
        },
        {
          'code': 'CUSTOM_LEGAL',
          'name': 'Extra terms',
          'content': 'Service terms',
          'group': 'legal',
        },
        {'code': 'REVENUE_PAYOUTS', 'group': 'terms'},
        {'code': 'OTHER_MONEY', 'group': 'monetization'},
      ]);
      expect(catalog.length, 31);
      expect(catalog.where((p) => p['code'] == 'CHILD_SAFETY').length, 1);
      expect(catalog.first['content'], 'Latest rules');
      expect(catalog.first['published'], true);
      expect(
        catalog.singleWhere((p) => p['code'] == 'DOXXING_PRIVACY')['group'],
        'privacy',
      );
      expect(
        catalog.singleWhere((p) => p['code'] == 'CUSTOM_LEGAL')['group'],
        'terms',
      );
      expect(catalog.any((p) => p['code'] == 'REVENUE_PAYOUTS'), false);
      final rules = catalog.singleWhere((p) => p['code'] == 'APPEALS_PROCESS');
      expect(policySearchText(rules), contains('30 ngay'));
      final export = policyDocumentText(catalog, fallback: '');
      expect(export, contains('Latest rules'));
      expect(export, contains('48 giờ'));
      expect(export, contains(policyLabel('policies.exceptionsEdsa')));
    },
  );
  testWidgets(
    'failed policy API keeps reference guidance, shows retry and prevents PDF export',
    (tester) async {
      var failed = true;
      final client = MockClient(
        (_) async => failed
            ? jsonResponse({'code': 'SERVER_ERROR'}, 500)
            : http.Response('[]', 200),
      );
      final auth = AuthController(ApiClient(client: client), MemoryStore());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PoliciesScreen(auth: auth)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(policyLabel('policies.loadError')), findsOneWidget);
      expect(
        tester
            .widget<PopupMenuButton<bool>>(find.byType(PopupMenuButton<bool>))
            .enabled,
        false,
      );
      failed = false;
      await tester.tap(
        find.widgetWithText(TextButton, AppStrings.t('common.retry')),
      );
      await tester.pumpAndSettle();
      expect(find.text(policyLabel('policies.loadError')), findsNothing);
      expect(
        tester
            .widget<PopupMenuButton<bool>>(find.byType(PopupMenuButton<bool>))
            .enabled,
        true,
      );
      await tester.enterText(
        find.byKey(const ValueKey('policy-search')),
        'khieu nai',
      );
      await tester.pumpAndSettle();
      expect(find.text('Quy trình khiếu nại minh bạch'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    },
  );
  testWidgets(
    'evidence loads through authenticated endpoint, displays image and opens zoom without sharing',
    (tester) async {
      final image = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=',
      );
      var requested = 0;
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/auth/refresh')) {
          return jsonResponse(session());
        }
        if (r.url.path.endsWith('/auth/logout')) return jsonResponse({});
        expect(r.url.path, endsWith('/appeals/a/evidence'));
        expect(r.headers['Authorization'], 'Bearer access-1');
        requested++;
        return http.Response.bytes(
          image,
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      final auth = AuthController(
        ApiClient(client: client),
        MemoryStore('refresh'),
      );
      await auth.restore();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppealEvidence(auth: auth, appealId: 'a'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requested, 1);
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await auth.logout();
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    },
  );
  testWidgets(
    'stale evidence response cannot replace a different appeal; PDF has file card and retry',
    (tester) async {
      final first = Completer<http.Response>();
      var second = 0;
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/auth/refresh')) {
          return jsonResponse(session());
        }
        if (r.url.path.contains('/appeals/first/')) return first.future;
        second++;
        return second == 1
            ? jsonResponse({'code': 'FAIL'}, 500)
            : http.Response.bytes(
                utf8.encode('%PDF-1.4 test'),
                200,
                headers: {'content-type': 'application/pdf'},
              );
      });
      final auth = AuthController(
        ApiClient(client: client),
        MemoryStore('refresh'),
      );
      await auth.restore();
      Widget page(String id) => MaterialApp(
        home: Scaffold(
          body: AppealEvidence(auth: auth, appealId: id),
        ),
      );
      await tester.pumpWidget(page('first'));
      await tester.pump();
      await tester.pumpWidget(page('second'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.t('evidence.loadFailed')), findsOneWidget);
      await tester.tap(find.byTooltip(AppStrings.t('common.retry')));
      await tester.pumpAndSettle();
      first.complete(
        http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.t('evidence.pdf')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'policies and evidence fit narrow width with large text dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = MockClient(
          (r) async => r.url.path.endsWith('/auth/refresh')
              ? jsonResponse(session())
              : r.url.path.endsWith('/evidence')
              ? http.Response.bytes(
                  Uint8List.fromList([1]),
                  200,
                  headers: {'content-type': 'application/pdf'},
                )
              : http.Response('[]', 200),
        );
        final auth = AuthController(
          ApiClient(client: client),
          MemoryStore('refresh'),
        );
        await auth.restore();
        for (final child in [
          PoliciesScreen(auth: auth),
          AppealEvidence(auth: auth, appealId: 'pdf'),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(body: child),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        auth.dispose();
        client.close();
      },
    );
  }
}
