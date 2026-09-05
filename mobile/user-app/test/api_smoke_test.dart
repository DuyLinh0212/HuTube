import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/auth.dart';

import 'auth_test.dart' show MemoryStore;

// Opt-in: requires the real local API and its Development email pickup folder.
// This verifies the production HTTP/controller code, not native secure storage.
void main() {
  const baseUrl = String.fromEnvironment('LIVE_API_BASE_URL');
  const pickup = String.fromEnvironment('EMAIL_PICKUP_DIRECTORY');
  test(
    'live mobile register verify login refresh restore reset and revoke',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final email = 'mobile-smoke-$suffix@example.com';
      final api = ApiClient(baseUrl: baseUrl);
      final store = MemoryStore();
      final auth = AuthController(api, store);
      final info = await api.request('GET', '/system/info');
      expect(info, isNotEmpty);
      await api.request(
        'POST',
        '/auth/register',
        body: {
          'username': 'mobile_$suffix',
          'displayName': 'Mobile Smoke',
          'email': email,
          'password': 'MobileSmoke123!',
        },
      );
      await expectLater(
        auth.login(email, 'MobileSmoke123!'),
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'EMAIL_NOT_VERIFIED'),
        ),
      );
      await api.request(
        'POST',
        '/auth/verify-email',
        body: {'token': await emailToken(pickup, email, 'verify-email')},
      );
      await auth.login(email, 'MobileSmoke123!');
      expect(auth.authenticated, isTrue);
      final me = await auth.protected('GET', '/auth/me');
      expect(me['email'], email);
      final firstToken = store.token;
      await auth.refresh();
      expect(store.token, isNot(firstToken));
      final restored = AuthController(ApiClient(baseUrl: baseUrl), store);
      await restored.restore();
      expect(restored.authenticated, isTrue);
      await restored.protected('POST', '/auth/logout-others');
      final sessions = await restored.protected('GET', '/auth/sessions');
      expect(sessions['items'], hasLength(1));
      await api.request(
        'POST',
        '/auth/forgot-password',
        body: {'email': email},
      );
      await api.request(
        'POST',
        '/auth/reset-password',
        body: {
          'token': await emailToken(pickup, email, 'reset-password'),
          'password': 'ChangedSmoke123!',
        },
      );
      await expectLater(
        restored.protected('GET', '/auth/me'),
        throwsA(isA<ApiFailure>()),
      );
      expect(restored.authenticated, isFalse);
      await restored.login(email, 'ChangedSmoke123!');
      await restored.logout();
      expect(restored.authenticated, isFalse);
      expect(store.token, isNull);
      auth.dispose();
      restored.dispose();
    },
    skip: baseUrl.isEmpty || pickup.isEmpty
        ? 'Set LIVE_API_BASE_URL and EMAIL_PICKUP_DIRECTORY to run against local API.'
        : false,
  );
}

Future<String> emailToken(String pickup, String email, String route) async {
  for (final file in Directory(pickup).listSync().whereType<File>()) {
    final raw = await file.readAsString();
    if (!raw.contains(email)) continue;
    final sections = raw.split(RegExp(r'\r?\n\r?\n'));
    var body = sections.skip(1).join('\n\n');
    if (raw.contains('Content-Transfer-Encoding: base64')) {
      body = utf8.decode(base64.decode(body.replaceAll(RegExp(r'\s'), '')));
    } else {
      body = body.replaceAll(RegExp(r'=\r?\n'), '').replaceAll('=3D', '=');
    }
    final match = RegExp('$route\\?token=([A-Za-z0-9_%+-]+)').firstMatch(body);
    if (match != null) return Uri.decodeComponent(match.group(1)!);
  }
  throw StateError(
    'Development email was not found for the smoke-test account.',
  );
}
