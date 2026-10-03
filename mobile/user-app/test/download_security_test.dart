import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/features/content/local_download_manager.dart';

Future<void> waitFor(bool Function() ready) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Download did not reach the expected state');
}

void main() {
  test(
    'pause prevents late completion and resume starts an authorized transfer',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hutube_download_pause_',
      );
      final delayed = Completer<http.Response>();
      var calls = 0;
      var authorizations = 0;
      final manager = LocalDownloadManager.test(
        rootDirectory: () async => root,
        clientFactory: () => MockClient((_) async {
          calls++;
          return calls == 1 ? delayed.future : http.Response('video', 200);
        }),
      );
      try {
        await manager.bindUser(
          'owner',
          authorize: (_) async {
            authorizations++;
            return 'https://media.test/file';
          },
        );
        await manager.enqueue(
          id: 'one',
          videoId: 'a',
          title: 'A',
          quality: '720p',
          url: '',
          fileSize: 5,
        );
        await waitFor(() => calls == 1);
        await manager.pause('one');
        expect(manager.items.single.status, 'paused');
        delayed.complete(http.Response('video', 200));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(manager.items.single.completed, isFalse);
        await manager.retry('one');
        expect(manager.items.single.completed, isTrue);
        expect(authorizations, 2);
      } finally {
        await manager.bindUser(null);
        await manager.flush();
        manager.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'offline files are isolated by owner and retries revalidate access',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hutube_download_security_',
      );
      var allowed = true;
      var requests = 0;
      final manager = LocalDownloadManager.test(
        rootDirectory: () async => root,
        clientFactory: () => MockClient((_) async {
          requests++;
          return http.Response('video', 200);
        }),
      );
      try {
        await manager.bindUser(
          'owner-a',
          authorize: (_) async => allowed ? 'https://media.test/file' : null,
        );
        await manager.enqueue(
          id: 'one',
          videoId: 'video',
          title: 'Private title',
          quality: '720p',
          url: 'https://expired.test/file',
          fileSize: 5,
        );
        await waitFor(() => manager.items.single.completed);
        expect(await File(manager.items.single.filePath!).exists(), isTrue);
        await manager.flush();
        await manager.bindUser('owner-b', authorize: (_) async => null);
        expect(manager.items, isEmpty);
        await manager.bindUser(
          'owner-a',
          authorize: (_) async => allowed ? 'https://media.test/file' : null,
        );
        expect(manager.items.single.completed, isTrue);
        allowed = false;
        await manager.retry('one');
        expect(manager.items.single.status, 'failed');
        expect(requests, 1);
      } finally {
        await manager.bindUser(null);
        await manager.flush();
        manager.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'an insertion and logout cannot redirect a pending transfer to another record',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hutube_download_race_',
      );
      final first = Completer<http.Response>();
      var calls = 0;
      final manager = LocalDownloadManager.test(
        rootDirectory: () async => root,
        clientFactory: () => MockClient((_) async {
          calls++;
          return calls == 1 ? first.future : http.Response('second', 200);
        }),
      );
      try {
        await manager.bindUser(
          'owner-a',
          authorize: (_) async => 'https://media.test/file',
        );
        await manager.enqueue(
          id: 'first',
          videoId: 'a',
          title: 'First',
          quality: '720p',
          url: '',
          fileSize: 5,
        );
        await waitFor(() => calls == 1);
        await manager.enqueue(
          id: 'second',
          videoId: 'b',
          title: 'Second',
          quality: '720p',
          url: '',
          fileSize: 6,
        );
        await waitFor(() => manager.items.first.completed);
        await manager.bindUser('owner-b', authorize: (_) async => null);
        first.complete(http.Response('first', 200));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(manager.items, isEmpty);
        await manager.bindUser('owner-a', authorize: (_) async => null);
        expect(manager.items.first.id, 'second');
        expect(manager.items.first.completed, isTrue);
        expect(manager.items.last.id, 'first');
        expect(manager.items.last.completed, isFalse);
      } finally {
        await manager.bindUser(null);
        await manager.flush();
        manager.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}
