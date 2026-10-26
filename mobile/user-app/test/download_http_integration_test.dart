import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/content/local_download_manager.dart';

import 'download_security_test.dart' show waitFor;

class _LiveHttp extends HttpOverrides {}

void main() {
  for (final scenario in ['redirect', 'interrupted', 'pause', 'server-error']) {
    test(
      'real HTTP download: $scenario, saved MP4 matches source',
      () => HttpOverrides.runWithHttpOverrides(() async {
        final root = await Directory.systemTemp.createTemp(
          'dalitu-http-download-',
        );
        final bytes = await File(
          'test/fixtures/download-sample.mp4',
        ).readAsBytes();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final firstPart = Completer<void>();
        final release = Completer<void>();
        var requests = 0;
        final tasks = <Future<void>>[];
        Future<void> serve(HttpRequest request) async {
          try {
            if (request.uri.path == '/redirect') {
              request.response.redirect(Uri.parse('/video.mp4'));
              return;
            }
            requests++;
            if (requests == 1 && scenario == 'server-error') {
              request.response.statusCode = 503;
              await request.response.close();
              return;
            }
            if (requests == 1 && scenario == 'interrupted') {
              final socket = await request.response.detachSocket(
                writeHeaders: false,
              );
              socket.write(
                'HTTP/1.1 200 OK\r\nContent-Type: video/mp4\r\nContent-Length: ${bytes.length}\r\nConnection: close\r\n\r\n',
              );
              socket.add(bytes.sublist(0, bytes.length ~/ 2));
              await socket.flush();
              socket.destroy();
              return;
            }
            request.response.headers.contentType = ContentType('video', 'mp4');
            request.response.contentLength = bytes.length;
            if (requests == 1 && scenario == 'pause') {
              request.response.add(bytes.sublist(0, bytes.length ~/ 2));
              await request.response.flush();
              firstPart.complete();
              await release.future;
              request.response.add(bytes.sublist(bytes.length ~/ 2));
            } else {
              request.response.add(bytes);
            }
            await request.response.close();
          } catch (_) {
            // A client pause deliberately closes the in-flight connection.
          }
        }

        final listener = server.listen((r) => tasks.add(serve(r)));
        final manager = LocalDownloadManager.test(
          rootDirectory: () async => root,
        );
        final url =
            'http://127.0.0.1:${server.port}/${scenario == 'redirect' ? 'redirect' : 'video.mp4'}';
        try {
          await manager.bindUser('viewer', authorize: (_) async => url);
          await manager.enqueue(
            id: 'sample',
            videoId: 'sample',
            title: 'Sample',
            quality: '90p',
            url: '',
            fileSize: bytes.length,
          );
          if (scenario == 'pause') {
            await firstPart.future.timeout(const Duration(seconds: 3));
            await manager.pause('sample');
            expect(manager.items.single.status, 'paused');
            release.complete();
            await manager.retry('sample');
          } else if (scenario != 'redirect') {
            await waitFor(() => manager.items.single.status == 'failed');
            expect(manager.items.single.filePath, isNull);
            await manager.retry('sample');
          }
          await waitFor(() => manager.items.single.completed);
          final saved = File(manager.items.single.filePath!);
          expect(await saved.readAsBytes(), orderedEquals(bytes));
          expect(manager.items.single.progress, 1);
          expect(requests, scenario == 'redirect' ? 1 : 2);
          await manager.flush();
          // Also export one real downloaded video for independent decode checks.
          if (scenario == 'redirect' &&
              const bool.fromEnvironment('EXPORT_DOWNLOAD_FIXTURE')) {
            final output = Directory('../../outputs/mobile-fixes')
              ..createSync(recursive: true);
            await saved.copy('${output.path}/downloaded-check.mp4');
          }
          await manager.remove('sample');
          expect(await saved.exists(), isFalse);
          expect(manager.items, isEmpty);
        } finally {
          if (!release.isCompleted) release.complete();
          await manager.bindUser(null);
          await manager.flush();
          manager.dispose();
          await server.close(force: true);
          await listener.cancel();
          await Future.wait(tasks);
          expect(
            root.absolute.path.startsWith(
              '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}',
            ),
            isTrue,
          );
          await root.delete(recursive: true);
        }
      }, _LiveHttp()),
    );
  }
}
