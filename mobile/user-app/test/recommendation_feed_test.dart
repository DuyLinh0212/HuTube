import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/features/content/content_service.dart';

import 'auth_test.dart' show MemoryStore, jsonResponse, session;

void main() {
  test(
    'direct FastAPI feed refreshes its access token through the .NET API',
    () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('/auth/login')) {
          return jsonResponse(session());
        }
        if (request.url.path.endsWith('/auth/refresh')) {
          return jsonResponse(session('2'));
        }
        expect(request.url.host, 'recommendations.test');
        expect(request.url.path, '/api/v1/feed/recommended');
        expect(request.url.queryParameters, {'page': '2', 'pageSize': '10'});
        expect(request.headers.containsKey('X-Service-Token'), isFalse);
        if (request.headers['authorization'] == 'Bearer access-1') {
          return jsonResponse({'code': 'SESSION_EXPIRED'}, 401);
        }
        expect(request.headers['authorization'], 'Bearer access-2');
        return jsonResponse({
          'items': [],
          'page': 2,
          'pageSize': 10,
          'total': 0,
        });
      });
      final auth = AuthController(
        ApiClient(client: client, baseUrl: 'https://content.test/api/v1'),
        MemoryStore(),
      );
      await auth.login('linh@example.com', 'Password123!');
      final content = ContentService(
        auth,
        recommendationApi: ApiClient(
          client: client,
          baseUrl: 'https://recommendations.test/api/v1',
        ),
      );
      final result = await content.feed(explore: false, page: 2, pageSize: 10);
      expect(result.page, 2);
      expect(requests.map((uri) => uri.host), [
        'content.test',
        'recommendations.test',
        'content.test',
        'recommendations.test',
      ]);
      expect(
        requests.any(
          (uri) =>
              uri.host == 'content.test' &&
              uri.path.endsWith('/feed/recommended'),
        ),
        isFalse,
      );
      auth.dispose();
      client.close();
    },
  );

  test('FastAPI outage uses an empty ranking without .NET inference', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/login')) {
        return jsonResponse(session());
      }
      if (request.url.host == 'recommendations.test') {
        return jsonResponse({'code': 'UNAVAILABLE'}, 503);
      }
      expect(request.url.path, '/api/v1/feed/resolve');
      expect(request.method, 'POST');
      expect(jsonDecode(request.body), {
        'videoIds': [],
        'page': 1,
        'pageSize': 20,
      });
      expect(request.headers['authorization'], 'Bearer access-1');
      return jsonResponse({'items': [], 'page': 1, 'pageSize': 20, 'total': 0});
    });
    final auth = AuthController(
      ApiClient(client: client, baseUrl: 'https://content.test/api/v1'),
      MemoryStore(),
    );
    await auth.login('linh@example.com', 'Password123!');
    final content = ContentService(
      auth,
      recommendationApi: ApiClient(
        client: client,
        baseUrl: 'https://recommendations.test/api/v1',
      ),
    );
    expect((await content.feed(explore: false)).items, isEmpty);
    auth.dispose();
    client.close();
  });

  test('anonymous home feed still uses the public content API', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'content.test');
      expect(request.url.path, '/api/v1/feed/home');
      expect(request.headers.containsKey('authorization'), isFalse);
      return jsonResponse({'items': [], 'page': 1, 'pageSize': 20, 'total': 0});
    });
    final auth = AuthController(
      ApiClient(client: client, baseUrl: 'https://content.test/api/v1'),
      MemoryStore(),
    );
    final content = ContentService(auth);
    expect((await content.feed(explore: false)).items, isEmpty);
    auth.dispose();
    client.close();
  });

  test(
    'recommendation URL follows local hosts and supports deployed overrides',
    () {
      expect(const AppConfig().apiBaseUrl, 'https://api.dalitu.app/api/v1');
      expect(
        const AppConfig(apiBaseUrl: 'http://10.0.2.2:5080/api/v1')
            .recommendationBaseUrl,
        'http://10.0.2.2:8000/api/v1',
      );
      expect(
        const AppConfig().recommendationBaseUrl,
        'https://recommendation.dalitu.app/api/v1',
      );
      expect(
        const AppConfig(apiBaseUrl: 'http://127.0.0.1:5080/api/v1')
            .recommendationBaseUrl,
        'http://127.0.0.1:8000/api/v1',
      );
      expect(
        const AppConfig(apiBaseUrl: 'https://hutube.onrender.com/api/v1')
            .recommendationBaseUrl,
        'https://hutube-recommendation-services.onrender.com/api/v1',
      );
      expect(
        const AppConfig(apiBaseUrl: 'https://api.dalitu.app/api/v1')
            .recommendationBaseUrl,
        'https://recommendation.dalitu.app/api/v1',
      );
      expect(
        const AppConfig(recommendationBaseUrl: 'https://custom.test/api/v1')
            .recommendationBaseUrl,
        'https://custom.test/api/v1',
      );
    },
  );
}
