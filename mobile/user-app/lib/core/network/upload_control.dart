import 'dart:async';
import 'package:http/http.dart' as http;

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
