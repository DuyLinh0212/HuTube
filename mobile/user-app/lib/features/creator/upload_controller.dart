import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../auth.dart';
import '../../core/network/upload_control.dart';
import '../../core/localization/app_strings.dart';
import '../content/content_models.dart';
import '../playlists/playlist_service.dart';

enum UploadPhase {
  idle,
  uploading,
  processing,
  completed,
  failed,
  cancelled,
  partial,
}

typedef VideoUploadTask =
    Future<VideoDetail> Function(
      UploadControl control,
      String key,
      void Function(int, int) progress,
    );

class UploadController extends ChangeNotifier {
  UploadController(this.auth) {
    auth.addListener(_identityChanged);
  }
  final AuthController auth;
  UploadPhase phase = UploadPhase.idle;
  String fileName = '';
  String? error;
  int sent = 0, total = 0;
  VideoDetail? video;
  VideoUploadTask? _task;
  Future<void> Function()? _onSaved;
  final List<String> _pendingPlaylists = [];
  String _key = '';
  int _session = -1;
  int _run = 0;
  bool _disposed = false;
  UploadControl? _control;
  bool get busy =>
      phase == UploadPhase.uploading || phase == UploadPhase.processing;
  bool get visible => phase != UploadPhase.idle;
  double? get progress => total > 0 ? (sent / total).clamp(0, 1) : null;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool start({
    required String name,
    required VideoUploadTask task,
    List<String> playlistIds = const [],
    Future<void> Function()? onSaved,
  }) {
    if (busy || !auth.authenticated) return false;
    fileName = name;
    video = null;
    sent = 0;
    total = 0;
    error = null;
    _key =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    _session = auth.sessionGeneration;
    _task = task;
    _onSaved = onSaved;
    _pendingPlaylists
      ..clear()
      ..addAll(playlistIds.toSet());
    phase = UploadPhase.uploading;
    unawaited(_execute());
    return true;
  }

  bool _current(int run) =>
      !_disposed &&
      run == _run &&
      _session == auth.sessionGeneration &&
      auth.authenticated;
  Future<void> _execute() async {
    final run = ++_run;
    _control = UploadControl();
    error = null;
    phase = video == null ? UploadPhase.uploading : UploadPhase.processing;
    _notify();
    var previousPercent = -1;
    try {
      if (video == null) {
        final result = await _task!(_control!, _key, (loaded, length) {
          if (!_current(run)) return;
          sent = loaded;
          total = length;
          phase = loaded >= length && length > 0
              ? UploadPhase.processing
              : UploadPhase.uploading;
          final percent = length > 0 ? (loaded * 100 ~/ length) : 0;
          if (percent != previousPercent) {
            previousPercent = percent;
            _notify();
          }
        });
        if (!_current(run)) return;
        video = result;
      }
      final pending = List<String>.of(_pendingPlaylists);
      for (final id in pending) {
        if (!_current(run)) return;
        try {
          await PlaylistService(auth).addVideo(id, video!.id);
          if (!_current(run)) return;
          _pendingPlaylists.remove(id);
        } on ApiFailure catch (e) {
          if (e.code == 'PLAYLIST_VIDEO_EXISTS') _pendingPlaylists.remove(id);
        } catch (_) {
          /* Keep failed attachments for a separate retry. */
        }
      }
      if (!_current(run)) return;
      phase = _pendingPlaylists.isEmpty
          ? UploadPhase.completed
          : UploadPhase.partial;
      if (_onSaved != null) {
        try {
          await _onSaved!();
        } catch (_) {
          /* Video is already saved. */
        }
      }
    } on UploadCancelled {
      if (_current(run)) phase = UploadPhase.cancelled;
    } on ApiFailure catch (e) {
      if (_current(run)) {
        phase = UploadPhase.failed;
        error = AppStrings.apiError(e);
      }
    } catch (_) {
      if (_current(run)) {
        phase = UploadPhase.failed;
        error = AppStrings.t('parity.uploadFailed');
      }
    } finally {
      if (_current(run)) _notify();
    }
  }

  void cancel() {
    if (!busy) return;
    ++_run;
    _control?.cancel();
    phase = video == null ? UploadPhase.cancelled : UploadPhase.partial;
    _notify();
  }

  void retry() {
    if (busy || _task == null || _session != auth.sessionGeneration) return;
    unawaited(_execute());
  }

  void dismiss() {
    if (busy) return;
    ++_run;
    _task = null;
    _onSaved = null;
    video = null;
    error = null;
    _pendingPlaylists.clear();
    phase = UploadPhase.idle;
    _notify();
  }

  void _identityChanged() {
    if (_session == -1 || _session == auth.sessionGeneration) return;
    ++_run;
    _control?.cancel();
    phase = UploadPhase.idle;
    _task = null;
    _onSaved = null;
    video = null;
    _pendingPlaylists.clear();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_run;
    _control?.cancel();
    auth.removeListener(_identityChanged);
    super.dispose();
  }
}

class UploadScope extends InheritedNotifier<UploadController> {
  const UploadScope({
    super.key,
    required UploadController controller,
    required super.child,
  }) : super(notifier: controller);
  static UploadController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UploadScope>()!.notifier!;
}

class UploadTray extends StatelessWidget {
  const UploadTray({super.key, required this.controller});
  final UploadController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      if (!c.visible) return const SizedBox.shrink();
      final key = switch (c.phase) {
        UploadPhase.processing => 'processingUpload',
        UploadPhase.completed => 'uploadDone',
        UploadPhase.partial => 'playlistPartial',
        UploadPhase.cancelled => 'cancelled',
        _ => 'uploadFailed',
      };
      return Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_upload_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (c.busy)
                      IconButton(
                        tooltip: AppStrings.t('parity.cancel'),
                        onPressed: c.cancel,
                        icon: const Icon(Icons.cancel_outlined),
                      )
                    else ...[
                      if (c.phase != UploadPhase.completed)
                        TextButton(
                          onPressed: c.retry,
                          child: Text(AppStrings.t('parity.retry')),
                        ),
                      IconButton(
                        tooltip: AppStrings.t('parity.close'),
                        onPressed: c.dismiss,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ],
                ),
                if (c.phase == UploadPhase.uploading) ...[
                  LinearProgressIndicator(value: c.progress),
                  Text(
                    '${((c.progress ?? 0) * 100).round()}% · ${c.sent} / ${c.total} bytes',
                  ),
                ] else ...[
                  if (c.phase == UploadPhase.processing)
                    const LinearProgressIndicator(),
                  Text(
                    c.error ?? AppStrings.t('parity.$key'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
