import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';

class MemoryStore implements TokenStore {
  MemoryStore([this.token]);
  String? token;
  final writes = <String>[];
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String token) async {
    this.token = token;
    writes.add(token);
  }

  @override
  Future<void> clear() async {
    token = null;
  }
}

Map<String, dynamic> session([String suffix = '1']) => {
  'accessToken': 'access-$suffix',
  'refreshToken': 'refresh-$suffix',
  'expiresAt': '2030-01-01T00:00:00Z',
  'user': {
    'userId': 'user-1',
    'username': 'linh',
    'displayName': 'Linh',
    'email': 'linh@example.com',
    'emailVerified': true,
    'isAdmin': false,
  },
};
http.Response jsonResponse(Map<String, dynamic> data, [int status = 200]) =>
    http.Response(
      jsonEncode(data),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('restore rotates refresh token and persists no access token', () async {
    final store = MemoryStore('old');
    final auth = AuthController(
      ApiClient(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/auth/refresh');
          expect(jsonDecode(request.body), {'refreshToken': 'old'});
          return jsonResponse(session());
        }),
      ),
      store,
    );
    await auth.restore();
    expect(auth.authenticated, isTrue);
    expect(auth.restoring, isFalse);
    expect(store.writes, ['refresh-1']);
  });
  test(
    'parallel 401s share one refresh and retry with new access token',
    () async {
      var refreshes = 0;
      final gate = Completer<void>();
      final auth = AuthController(
        ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/login')) {
              return jsonResponse(session());
            }
            if (request.url.path.endsWith('/refresh')) {
              refreshes++;
              await gate.future;
              return jsonResponse(session('2'));
            }
            if (request.headers['authorization'] == 'Bearer access-2') {
              return jsonResponse({'items': []});
            }
            return jsonResponse({'code': 'TOKEN_EXPIRED'}, 401);
          }),
        ),
        MemoryStore(),
      );
      await auth.login('linh@example.com', 'GoodPassword1');
      final first = auth.protected('GET', '/auth/sessions');
      final second = auth.protected('GET', '/auth/sessions');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      gate.complete();
      await Future.wait([first, second]);
      expect(refreshes, 1);
    },
  );
  test('expired refresh clears session and secure storage', () async {
    final store = MemoryStore('expired');
    final auth = AuthController(
      ApiClient(
        client: MockClient(
          (_) async => jsonResponse({'code': 'INVALID_REFRESH_TOKEN'}, 401),
        ),
      ),
      store,
    );
    await auth.restore();
    expect(store.token, isNull);
    expect(auth.authenticated, isFalse);
    expect(auth.notice, contains('hết hạn'));
  });
  test('transient network failure retains refresh for retry', () async {
    final store = MemoryStore('still-valid');
    final auth = AuthController(
      ApiClient(
        client: MockClient((_) async => throw http.ClientException('offline')),
      ),
      store,
    );
    await auth.restore();
    expect(store.token, 'still-valid');
    expect(auth.authenticated, isFalse);
    expect(auth.notice, contains('kết nối'));
  });
  test(
    'late refresh after logout cannot resurrect session and is revoked',
    () async {
      final gate = Completer<http.Response>();
      final revoked = <String>[];
      final store = MemoryStore();
      final auth = AuthController(
        ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/login')) {
              return jsonResponse(session());
            }
            if (request.url.path.endsWith('/refresh')) return gate.future;
            if (request.url.path.endsWith('/logout')) {
              revoked.add(
                (jsonDecode(request.body) as Map)['refreshToken'] as String,
              );
            }
            return jsonResponse({});
          }),
        ),
        store,
      );
      await auth.login('linh@example.com', 'GoodPassword1');
      final refresh = auth.refresh();
      await auth.logout();
      gate.complete(jsonResponse(session('late')));
      await refresh;
      expect(auth.authenticated, isFalse);
      expect(store.token, isNull);
      expect(revoked, containsAll(['refresh-1', 'refresh-late']));
    },
  );
  test('late login after logout cannot persist tokens', () async {
    final gate = Completer<http.Response>();
    final store = MemoryStore();
    final auth = AuthController(
      ApiClient(
        client: MockClient(
          (request) async => request.url.path.endsWith('/login')
              ? gate.future
              : jsonResponse({}),
        ),
      ),
      store,
    );
    final login = auth.login('linh@example.com', 'GoodPassword1');
    await auth.logout();
    gate.complete(jsonResponse(session()));
    await login;
    expect(auth.authenticated, isFalse);
    expect(store.token, isNull);
  });
  test('suspended protected response clears authenticated state', () async {
    final store = MemoryStore();
    final auth = AuthController(
      ApiClient(
        client: MockClient(
          (request) async => request.url.path.endsWith('/login')
              ? jsonResponse(session())
              : jsonResponse({'code': 'ACCOUNT_SUSPENDED'}, 403),
        ),
      ),
      store,
    );
    await auth.login('linh@example.com', 'GoodPassword1');
    await expectLater(
      auth.protected('GET', '/auth/me'),
      throwsA(isA<ApiFailure>()),
    );
    expect(auth.authenticated, isFalse);
    expect(store.token, isNull);
  });
  test('deep links only permit explicit HuTube auth routes', () {
    expect(
      AuthLink.parse(Uri.parse('hutube://auth/account'))?.path,
      '/account',
    );
    expect(
      AuthLink.parse(
        Uri.parse('hutube://auth/reset-password?token=abc'),
      )?.token,
      'abc',
    );
    for (final url in [
      'https://evil.test/account',
      'hutube://evil/account',
      'hutube://auth/unknown',
      'hutube://user@auth/account',
      'hutube://auth:80/account',
    ]) {
      expect(AuthLink.parse(Uri.parse(url)), isNull, reason: url);
    }
  });
  test('password policy covers boundaries and character requirements', () {
    expect(validatePassword('GoodPassword1'), isNull);
    for (final password in [
      'short1A',
      'onlylowercase1',
      'ONLYUPPERCASE1',
      'WithoutDigits',
      'Aa1${'x' * 126}',
    ]) {
      expect(validatePassword(password), isNotNull);
    }
  });
  test(
    'API base URL is configurable and malformed error body is readable',
    () async {
      final api = ApiClient(
        baseUrl: 'https://example.test/api/v1/',
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://example.test/api/v1/system/info',
          );
          return http.Response('<html>Bad gateway</html>', 502);
        }),
      );
      await expectLater(
        api.request('GET', '/system/info'),
        throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 502)),
      );
    },
  );
}
