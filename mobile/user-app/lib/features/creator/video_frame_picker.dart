import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/error_banner.dart';
import '../content/content_models.dart';
import '../content/content_service.dart';

class VideoFramePicker extends StatefulWidget {
  const VideoFramePicker({super.key, required this.auth, required this.video});
  final AuthController auth;
  final VideoDetail video;
  @override
  State<VideoFramePicker> createState() => _VideoFramePickerState();
}

class _VideoFramePickerState extends State<VideoFramePicker> {
  static const _channel = MethodChannel('hutube/media_tools');
  final _frames = <int, String>{};
  late final _session = widget.auth.sessionGeneration;
  double _seconds = 0;
  String? _source, _frame, _selected, _error;
  bool _busy = false;
  bool get _current => mounted && _session == widget.auth.sessionGeneration;
  @override
  void initState() {
    super.initState();
    unawaited(_extract());
  }

  Future<void> _extract() async {
    if (_busy) return;
    final second = _seconds.round();
    if (_frames.containsKey(second)) {
      setState(() => _frame = _frames[second]);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_source == null) {
        final playback = await ContentService(
          widget.auth,
        ).playback(widget.video.id);
        if (!_current) return;
        _source =
            playback.renditions
                .where((r) => r.height > 0 && r.height <= 720)
                .firstOrNull
                ?.url ??
            playback.renditions.firstOrNull?.url ??
            widget.video.videoUrl;
      }
      if (_source == null) throw const FormatException('No source');
      final path = await _channel
          .invokeMethod<String>('extractFrame', {
            'source': _source,
            'seconds': second.toDouble(),
          })
          .timeout(const Duration(seconds: 30));
      if (path == null) throw const FormatException('No frame');
      if (!_current) {
        await File(path).delete();
        return;
      }
      _frames[second] = path;
      setState(() => _frame = path);
    } catch (_) {
      if (_current) setState(() => _error = AppStrings.t('creator.frameError'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final path
        in _frames.values.where((path) => path != _selected).toSet()) {
      unawaited(File(path).delete().catchError((Object _) => File(path)));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppStrings.t('creator.chooseFrame'))),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: FilledButton(
          onPressed: _busy || _frame == null
              ? null
              : () {
                  _selected = _frame;
                  Navigator.of(
                    context,
                  ).pop(XFile(_frame!, mimeType: 'image/jpeg'));
                },
          child: Text(AppStrings.t('creator.useFrame')),
        ),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: 16),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Colors.black,
              child: _frame == null
                  ? const Center(
                      child: Icon(
                        Icons.image_outlined,
                        color: Colors.white54,
                        size: 40,
                      ),
                    )
                  : Image.file(File(_frame!), fit: BoxFit.contain),
            ),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          AppStrings.t('creator.frameTime'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Slider(
          value: _seconds,
          max: widget.video.duration > 0
              ? (widget.video.duration - 1).clamp(1, double.infinity).toDouble()
              : 1,
          label:
              '${_seconds.round() ~/ 60}:${(_seconds.round() % 60).toString().padLeft(2, '0')}',
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  _seconds = value;
                  _frame = _frames[value.round()];
                }),
          onChangeEnd: (_) => _extract(),
        ),
        Text(
          '${_seconds.round() ~/ 60}:${(_seconds.round() % 60).toString().padLeft(2, '0')}',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy ? null : _extract,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(AppStrings.t('common.retry')),
        ),
      ],
    ),
  );
}
