import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/features/content/content_models.dart';
import 'package:user_app/features/content/content_service.dart';

import 'auth_test.dart' show MemoryStore, jsonResponse;

void main() {
  setUp(ApiClient.invalidateReadCache);
  final video = VideoDetail.fromJson({
    'videoId': 'current',
    'categoryId': 'music',
    'tags': ['-xh', 'china', 'music'],
  });
  Map<String, dynamic> result(List<String> ids) => {
    'items': ids.map((id) => {'videoId': id}).toList(),
    'page': 1,
    'pageSize': 20,
    'total': ids.length,
  };
  ContentService service(Future<Map<String, dynamic>> Function(Uri) respond) {
    final client = MockClient((r) async => jsonResponse(await respond(r.url)));
    final auth = AuthController(ApiClient(client: client), MemoryStore());
    addTearDown(auth.dispose);
    addTearDown(client.close);
    return ContentService(auth);
  }

  test(
    'rare first tag matching only the current video fills from its category',
    () async {
      final calls = <Uri>[];
      final content = service((url) async {
        calls.add(url);
        return result(
          url.queryParameters.containsKey('tag')
              ? ['current']
              : ['current', 'related'],
        );
      });
      expect((await content.relatedVideos(video)).map((v) => v.id), [
        'related',
      ]);
      expect(calls.length, 2);
      expect(calls.first.queryParameters['tag'], '-xh');
      expect(calls.last.queryParameters.containsKey('tag'), isFalse);
      expect(
        calls.every((url) => url.queryParameters['categoryId'] == 'music'),
        isTrue,
      );
    },
  );

  test('keeps tag matches first, removes duplicates and caps at ten', () async {
    final content = service(
      (url) async => result(
        url.queryParameters.containsKey('tag')
            ? ['current', 'tagged', 'tagged']
            : ['current', 'tagged', ...List.generate(12, (n) => 'category-$n')],
      ),
    );
    expect((await content.relatedVideos(video)).map((v) => v.id), [
      'tagged',
      ...List.generate(9, (n) => 'category-$n'),
    ]);
  });

  test('does not broaden a full tag result', () async {
    var calls = 0;
    final content = service((url) async {
      calls++;
      return result(List.generate(10, (n) => 'tagged-$n'));
    });
    expect((await content.relatedVideos(video)).length, 10);
    expect(calls, 1);
  });

  test('without tags searches the category once', () async {
    var calls = 0;
    final content = service((url) async {
      calls++;
      expect(url.queryParameters['categoryId'], 'music');
      expect(url.queryParameters.containsKey('tag'), isFalse);
      return result(['related']);
    });
    final noTags = VideoDetail.fromJson({
      'videoId': 'current',
      'categoryId': 'music',
    });
    expect((await content.relatedVideos(noTags)).map((v) => v.id), ['related']);
    expect(calls, 1);
  });

  test('without metadata uses the normal feed', () async {
    final content = service((url) async {
      expect(url.path.endsWith('/feed/home'), isTrue);
      return result(['current', 'feed']);
    });
    expect(
      (await content.relatedVideos(
        VideoDetail.fromJson({'videoId': 'current'}),
      )).map((v) => v.id),
      ['feed'],
    );
  });

  test('keeps valid tag matches when category fill fails', () async {
    final content = service((url) async {
      if (!url.queryParameters.containsKey('tag')) throw StateError('offline');
      return result(['tagged']);
    });
    expect((await content.relatedVideos(video)).map((v) => v.id), ['tagged']);
  });

  test('surfaces failure when there are no tag matches to preserve', () async {
    final content = service((url) async {
      if (!url.queryParameters.containsKey('tag')) throw StateError('offline');
      return result(['current']);
    });
    await expectLater(content.relatedVideos(video), throwsA(anything));
  });

  test(
    'allows a genuinely empty related category without unrelated feed fallback',
    () async {
      final content = service((url) async {
        expect(url.path.endsWith('/videos/search'), isTrue);
        return result(['current']);
      });
      expect(await content.relatedVideos(video), isEmpty);
    },
  );
}
