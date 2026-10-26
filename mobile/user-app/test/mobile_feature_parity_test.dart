import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/core/network/upload_control.dart';
import 'package:user_app/core/widgets/content_filters.dart';
import 'package:user_app/features/content/content_models.dart';
import 'package:user_app/features/content/content_service.dart';
import 'package:user_app/features/creator/creator_service.dart';
import 'package:user_app/features/creator/upload_controller.dart';
import 'package:user_app/features/creator/upload_draft_store.dart';
import 'package:user_app/features/creator/video_metadata.dart';
import 'package:user_app/features/policies/policy_document.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse, session;

Future<void> flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _LiveHttpOverrides extends HttpOverrides {}

Map<String, dynamic> draftData() => {
  'title': 'Tiêu đề',
  'description': 'Mô tả',
  'tags': 'học tập',
  'languageCode': 'vi',
  'visibility': 'private',
  'chapters': [
    {'startSeconds': 0, 'title': 'Mở đầu'},
  ],
  'videoCards': <Map<String, dynamic>>[],
  'playlistIds': ['playlist-1'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AppStrings.currentLang.value = 'vi';
  });

  test(
    'metadata quality cap handles portrait, rotation dimensions and small sources',
    () {
      const landscape = VideoMetadata(
        durationSeconds: 2,
        width: 1920,
        height: 1080,
      );
      expect(landscape.selectQuality('480p'), '480p');
      expect(landscape.selectQuality('2160p'), '1080p');
      expect(
        const VideoMetadata(
          durationSeconds: 2,
          width: 1920,
          height: 1080,
        ).qualities.last,
        '1080p',
      );
      expect(
        const VideoMetadata(
          durationSeconds: 2,
          width: 1080,
          height: 1920,
        ).qualities.last,
        '1080p',
      );
      expect(
        const VideoMetadata(
          durationSeconds: 2,
          width: 426,
          height: 240,
        ).qualities,
        ['144p', '240p'],
      );
      expect(
        const VideoMetadata(
          durationSeconds: 2,
          width: 100,
          height: 100,
        ).qualities,
        isEmpty,
      );
    },
  );

  test('drafts reject corrupt, future version and invalid timestamps', () {
    expect(UploadDraftStore.decode('broken'), isNull);
    expect(
      UploadDraftStore.decode(jsonEncode({'version': 2, 'data': draftData()})),
      isNull,
    );
    final data = draftData()
      ..['chapters'] = [
        {'startSeconds': -1, 'title': 'bad'},
      ];
    expect(
      UploadDraftStore.decode(jsonEncode({'version': 1, 'data': data})),
      isNull,
    );
    expect(
      UploadDraftStore.decode(
        jsonEncode({'version': 1, 'data': draftData()}),
      )?['title'],
      'Tiêu đề',
    );
  });

  test('draft persistence is separated by user and channel', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const store = UploadDraftStore();
    await store.save('alice', 'one', draftData());
    expect(await store.read('bob', 'one'), isNull);
    expect(await store.read('alice', 'two'), isNull);
    expect((await store.read('alice', 'one'))?['title'], 'Tiêu đề');
    await store.remove('alice', 'one');
    expect(await store.read('alice', 'one'), isNull);
  });

  test('finishing upload does not delete a newer draft', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const store = UploadDraftStore();
    await store.save('alice', 'one', draftData());
    final revision = await store.revision('alice', 'one');
    await store.save(
      'alice',
      'one',
      draftData()..['title'] = 'Video tiếp theo',
    );
    await store.removeIfUnchanged('alice', 'one', revision);
    expect((await store.read('alice', 'one'))?['title'], 'Video tiếp theo');
  });

  test('policy export preserves Vietnamese, version and selected content', () {
    final text = policyDocumentText([
      {
        'name': 'Quyền riêng tư',
        'content': 'Không tiết lộ dữ liệu',
        'version': '2.1',
        'effectiveAt': '2026-10-19',
        'code': 'PRIVACY',
      },
    ], fallback: 'fallback');
    expect(text, contains('Quyền riêng tư'));
    expect(text, contains('PRIVACY · 2.1'));
    expect(text, contains('2026-10-19'));
    expect(text, contains('Không tiết lộ dữ liệu'));
    expect(
      policyDocumentText([], fallback: 'Nội dung đang hiển thị'),
      'Nội dung đang hiển thị',
    );
  });

  testWidgets(
    'search debounces and keeps its text while parent results change',
    (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContentFilters(
              options: const {
                'sort': ['newest', 'oldest'],
              },
              onChanged: (q, values) =>
                  calls.add('$q:${values['sort'] ?? 'newest'}'),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'học');
      await tester.pump(const Duration(milliseconds: 200));
      expect(calls, isEmpty);
      await tester.enterText(find.byType(TextField), 'học tập');
      await tester.pump(const Duration(milliseconds: 301));
      expect(calls, ['học tập:newest']);
      expect(normalizeContentText('ĐẶNG Học TẬP'), 'dang hoc tap');
      expect(tester.takeException(), isNull);
    },
  );

  test('history filters and recommendation tag reach the API', () async {
    final paths = <Uri>[];
    final auth = AuthController(
      ApiClient(
        client: MockClient((r) async {
          paths.add(r.url);
          return jsonResponse({
            'items': [],
            'page': 1,
            'pageSize': 20,
            'total': 0,
          });
        }),
      ),
      MemoryStore(),
    )..user = {'userId': 'one'};
    addTearDown(auth.dispose);
    await ContentService(
      auth,
    ).history(query: 'học tập', sort: 'oldest', dateRange: 'week');
    expect(paths.first.queryParameters['q'], 'học tập');
    expect(paths.first.queryParameters['dateRange'], 'week');
    expect(paths.first.queryParameters['sort'], 'oldest');
    await ContentService(auth).searchVideos(query: '', tag: 'dart');
    expect(paths.last.queryParameters['tag'], 'dart');
  });

  test(
    'multipart reports all transmitted bytes and respects cancellation',
    () async {
      final control = UploadControl();
      final samples = <int>[];
      final request = ProgressMultipartRequest(
        'POST',
        Uri.parse('https://example.test/videos'),
        control: control,
        onProgress: (sent, total) {
          samples.add(sent);
          expect(sent, lessThanOrEqualTo(total));
        },
      );
      request.files.add(
        http.MultipartFile.fromBytes(
          'Video',
          List.filled(256, 7),
          filename: 'video.mp4',
        ),
      );
      final bytes = await request.finalize().toBytes();
      expect(samples.first, 0);
      expect(samples.last, bytes.length);
      final cancelled = UploadControl()..cancel();
      expect(
        () => ProgressMultipartRequest(
          'POST',
          Uri.parse('https://example.test'),
          control: cancelled,
        ).finalize(),
        throwsA(isA<UploadCancelled>()),
      );
    },
  );

  test(
    'creator payload and progress survive a 401 refresh with the same idempotency key',
    () async {
      var uploads = 0, progressCalls = 0;
      final keys = <String>[];
      final directory = await Directory.systemTemp.createTemp(
        'hutube-upload-test',
      );
      addTearDown(() {
        expect(
          directory.absolute.path.startsWith(
            '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}',
          ),
          isTrue,
        );
        return directory.delete(recursive: true);
      });
      final file = File('${directory.path}/video.mp4');
      await file.writeAsBytes([1, 2, 3]);
      final auth = AuthController(
        ApiClient(
          client: MockClient((r) async {
            if (r.url.path.endsWith('/auth/login')) {
              return jsonResponse(session());
            }
            if (r.url.path.endsWith('/auth/refresh')) {
              return jsonResponse(session('2'));
            }
            if (r.url.path.endsWith('/upload-sessions')) {
              keys.add(jsonDecode(r.body)['uploadId'] as String);
              return jsonResponse({
                'uploadId': 'same-key',
                'chunkSize': 4,
                'nextChunk': 0,
              });
            }
            if (r.url.path.endsWith('/chunks/0')) {
              return jsonResponse({'nextChunk': 1});
            }
            expect(r.url.path, endsWith('/same-key/complete'));
            expect(r.headers['prefer'], 'respond-async');
            uploads++;
            final body = utf8.decode(r.bodyBytes);
            expect(body, contains('name="ChaptersJson"'));
            expect(body, contains('{"startSeconds":0,"title":"Introduction"}'));
            expect(body, isNot(contains('name="Chapters[')));
            expect(body, contains('name="LanguageCode"\r\n\r\nen'));
            expect(body, contains('name="AllowComments"\r\n\r\nfalse'));
            expect(body, contains('name="SourceQuality"\r\n\r\n1080p'));
            return uploads == 1
                ? jsonResponse({'code': 'UNAUTHORIZED'}, 401)
                : jsonResponse({'videoId': 'saved'});
          }),
        ),
        MemoryStore(),
      );
      addTearDown(auth.dispose);
      await auth.login('test@example.test', 'Password1!');
      final result = await CreatorService(auth).upload(
        channelId: 'channel',
        title: 'Title',
        description: '',
        categoryId: null,
        visibility: 'private',
        ageRestricted: false,
        duration: 10,
        quality: '1080p',
        tags: [],
        languageCode: 'en',
        allowComments: false,
        chapters: [
          {'startSeconds': 0, 'title': 'Introduction'},
        ],
        idempotencyKey: 'same-key',
        onProgress: (_, _) => progressCalls++,
        uploadControl: UploadControl(),
        video: MultipartFilePayload(
          field: 'Video',
          path: file.path,
          fileName: 'video.mp4',
          contentType: 'video/mp4',
        ),
      );
      expect(result.id, 'saved');
      expect(keys, ['same-key']);
      expect(uploads, 2);
      expect(progressCalls, greaterThan(2));
    },
  );

  test('cancelled API upload is not translated into a network error', () async {
    final control = UploadControl()..cancel();
    var called = false;
    final client = ApiClient(
      client: MockClient((r) async {
        called = true;
        return jsonResponse({});
      }),
    );
    await expectLater(
      client.uploadMultipart(
        '/videos',
        fields: {},
        files: [],
        uploadControl: control,
      ),
      throwsA(isA<UploadCancelled>()),
    );
    expect(called, isFalse);
  });

  test('authenticated multipart forwards the cancellation control', () async {
    var requests = 0;
    final auth = AuthController(
      ApiClient(
        client: MockClient((r) async {
          requests++;
          return jsonResponse({});
        }),
      ),
      MemoryStore(),
    )..user = {'userId': 'one'};
    addTearDown(auth.dispose);
    await expectLater(
      auth.protectedMultipart(
        '/videos',
        fields: {},
        files: [],
        uploadControl: UploadControl()..cancel(),
      ),
      throwsA(isA<UploadCancelled>()),
    );
    expect(requests, 0);
  });

  test(
    'abort cancels an IO request while waiting for the server response',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<void>();
      final release = Completer<void>();
      server.listen((request) async {
        await request.drain<void>();
        if (!received.isCompleted) received.complete();
        await release.future;
        try {
          await request.response.close();
        } catch (_) {
          /* Client aborted. */
        }
      });
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        client.client.close();
        await server.close(force: true);
      });
      final control = UploadControl();
      final future = client.uploadMultipart(
        '/videos',
        fields: {'Title': 'Test'},
        files: [],
        uploadControl: control,
      );
      final assertion = expectLater(future, throwsA(isA<UploadCancelled>()));
      await received.future.timeout(const Duration(seconds: 5));
      control.cancel();
      await assertion.timeout(const Duration(seconds: 5));
    }, _LiveHttpOverrides()),
  );

  test(
    'upload retry keeps its key, one active upload, and completion is independent of page',
    () async {
      final auth = AuthController(
        ApiClient(client: MockClient((r) async => jsonResponse({}))),
        MemoryStore(),
      )..user = {'userId': 'one'};
      final controller = UploadController(auth);
      addTearDown(() {
        controller.dispose();
        auth.dispose();
      });
      final keys = <String>[];
      var attempts = 0;
      Future<VideoDetail> task(
        UploadControl control,
        String key,
        void Function(int, int) progress,
      ) async {
        keys.add(key);
        attempts++;
        progress(4, 10);
        if (attempts == 1) throw const SocketException('offline');
        progress(10, 10);
        return VideoDetail.fromJson({'videoId': 'saved'});
      }

      expect(controller.start(name: 'test.mp4', task: task), isTrue);
      expect(controller.start(name: 'another.mp4', task: task), isFalse);
      await flush();
      expect(controller.phase, UploadPhase.failed);
      controller.retry();
      await flush();
      expect(controller.phase, UploadPhase.completed);
      expect(keys[0], keys[1]);
      expect(controller.video?.id, 'saved');
    },
  );

  test(
    'playlist retry attaches only failed playlists without uploading again',
    () async {
      var uploads = 0, attachments = 0;
      final auth = AuthController(
        ApiClient(
          client: MockClient((r) async {
            attachments++;
            return attachments == 1
                ? jsonResponse({'code': 'FAIL'}, 500)
                : jsonResponse({});
          }),
        ),
        MemoryStore(),
      )..user = {'userId': 'one'};
      final controller = UploadController(auth);
      addTearDown(() {
        controller.dispose();
        auth.dispose();
      });
      controller.start(
        name: 'test.mp4',
        playlistIds: ['p'],
        task: (_, _, _) async {
          uploads++;
          return VideoDetail.fromJson({'videoId': 'saved'});
        },
      );
      await flush();
      expect(controller.phase, UploadPhase.partial);
      controller.retry();
      await flush();
      expect(controller.phase, UploadPhase.completed);
      expect(uploads, 1);
      expect(attachments, 2);
    },
  );

  test(
    'cancel ignores late response and logout clears the active task',
    () async {
      final auth = AuthController(
        ApiClient(client: MockClient((r) async => jsonResponse({}))),
        MemoryStore(),
      )..user = {'userId': 'one'};
      final controller = UploadController(auth);
      addTearDown(() {
        controller.dispose();
        auth.dispose();
      });
      final late = Completer<VideoDetail>();
      UploadControl? active;
      controller.start(
        name: 'late.mp4',
        task: (control, _, _) {
          active = control;
          return late.future;
        },
      );
      controller.cancel();
      expect(active?.isCancelled, isTrue);
      late.complete(VideoDetail.fromJson({'videoId': 'late'}));
      await flush();
      expect(controller.phase, UploadPhase.cancelled);
      expect(controller.video, isNull);
      controller.start(
        name: 'logout.mp4',
        task: (control, _, _) {
          active = control;
          return Completer<VideoDetail>().future;
        },
      );
      await auth.clearSession();
      await flush();
      expect(active?.isCancelled, isTrue);
      expect(controller.visible, isFalse);
    },
  );
}
