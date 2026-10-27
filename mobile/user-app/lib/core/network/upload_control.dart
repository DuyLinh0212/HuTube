import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;

String newUploadId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class UploadCancelled implements Exception {
  const UploadCancelled();
}

class UploadControl {
  final _abort = Completer<void>();
  Future<void> get aborted => _abort.future;
  bool get isCancelled => _abort.isCompleted;
  void cancel() {
    if (!_abort.isCompleted) _abort.complete();
  }

  void check() {
    if (isCancelled) throw const UploadCancelled();
  }
}

class ProgressMultipartRequest extends http.MultipartRequest
    with http.Abortable {
  ProgressMultipartRequest(
    super.method,
    super.url, {
    this.control,
    this.onProgress,
  });
  final UploadControl? control;
  final void Function(int sent, int total)? onProgress;
  @override
  Future<void>? get abortTrigger => control?.aborted;
  @override
  http.ByteStream finalize() {
    control?.check();
    final stream = super.finalize();
    final total = contentLength;
    var sent = 0;
    onProgress?.call(0, total);
    return http.ByteStream(
      stream.map((chunk) {
        control?.check();
        sent += chunk.length;
        onProgress?.call(sent, total);
        return chunk;
      }),
    );
  }
}
