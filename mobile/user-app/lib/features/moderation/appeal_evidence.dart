import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import 'moderation_service.dart';

/// Evidence is fetched through the authenticated API, never its public-looking URL.
class AppealEvidence extends StatefulWidget {
  const AppealEvidence({super.key, required this.auth, required this.appealId});
  final AuthController auth;
  final String appealId;
  @override
  State<AppealEvidence> createState() => _AppealEvidenceState();
}

class _AppealEvidenceState extends State<AppealEvidence> {
  BinaryPayload? _data;
  bool _loading = false;
  bool _failed = false;
  int _request = 0;
  int? _session;
  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_authChanged);
    _load();
  }

  void _authChanged() {
    if (_session != widget.auth.sessionGeneration) {
      _request++;
      if (mounted) {
        setState(() {
          _data = null;
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant AppealEvidence oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth) {
      oldWidget.auth.removeListener(_authChanged);
      widget.auth.addListener(_authChanged);
    }
    if (oldWidget.appealId != widget.appealId ||
        oldWidget.auth != widget.auth) {
      _load();
    }
  }

  @override
  void dispose() {
    _request++;
    widget.auth.removeListener(_authChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    final session = widget.auth.sessionGeneration;
    _session = session;
    setState(() {
      _loading = true;
      _failed = false;
      _data = null;
    });
    try {
      final data = await ModerationService(
        widget.auth,
      ).evidence(widget.appealId);
      if (!mounted ||
          request != _request ||
          session != widget.auth.sessionGeneration) {
        return;
      }
      if (data.bytes.isEmpty || data.bytes.length > 10 * 1024 * 1024) {
        throw const FormatException('Invalid evidence');
      }
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (mounted &&
          request == _request &&
          session == widget.auth.sessionGeneration) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  String get _mime =>
      _data?.contentType.split(';').first.trim().toLowerCase() ?? '';
  bool get _image =>
      const ['image/jpeg', 'image/png', 'image/webp'].contains(_mime);
  Future<void> _share() async {
    final data = _data;
    if (data == null || _session != widget.auth.sessionGeneration) return;
    final ext =
        {
          'image/png': 'png',
          'image/jpeg': 'jpg',
          'image/webp': 'webp',
          'application/pdf': 'pdf',
        }[_mime] ??
        'bin';
    try {
      await Share.shareXFiles(
        [
          XFile.fromData(
            Uint8List.fromList(data.bytes),
            mimeType: _mime,
            name: 'evidence.$ext',
          ),
        ],
        fileNameOverrides: ['evidence.$ext'],
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.t('common.error'))));
      }
    }
  }

  void _preview() {
    if (!_image || _session != widget.auth.sessionGeneration) return;
    final data = _data!;
    final viewerSession = widget.auth.sessionGeneration;
    showDialog<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(AppStrings.t('moderation.evidenceSection')),
            actions: [
              IconButton(
                onPressed: _share,
                tooltip: AppStrings.t('evidence.share'),
                icon: const Icon(Icons.ios_share_rounded),
              ),
            ],
          ),
          body: AnimatedBuilder(
            animation: widget.auth,
            builder: (context, _) =>
                viewerSession == widget.auth.sessionGeneration
                ? Center(
                    child: InteractiveViewer(
                      minScale: .5,
                      maxScale: 5,
                      child: Image.memory(
                        Uint8List.fromList(data.bytes),
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_failed)
              ListTile(
                leading: const Icon(Icons.attachment_outlined),
                title: Text(AppStrings.t('evidence.loadFailed')),
                trailing: IconButton(
                  onPressed: _load,
                  tooltip: AppStrings.t('common.retry'),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              )
            else if (_data != null) ...[
              if (_image)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  child: Semantics(
                    button: true,
                    label: AppStrings.t('evidence.zoom'),
                    child: InkWell(
                      onTap: _preview,
                      child: SizedBox(
                        height: 160,
                        child: Image.memory(
                          Uint8List.fromList(_data!.bytes),
                          fit: BoxFit.contain,
                          cacheWidth: 800,
                          errorBuilder: (_, _, _) => Center(
                            child: Text(AppStrings.t('evidence.loadFailed')),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ListTile(
                dense: true,
                leading: Icon(
                  _image
                      ? Icons.image_outlined
                      : _mime == 'application/pdf'
                      ? Icons.picture_as_pdf_outlined
                      : Icons.insert_drive_file_outlined,
                ),
                title: Text(
                  _image
                      ? AppStrings.t('evidence.image')
                      : _mime == 'application/pdf'
                      ? AppStrings.t('evidence.pdf')
                      : AppStrings.t('evidence.file'),
                ),
                subtitle: Text(
                  '${(_data!.bytes.length / 1024).toStringAsFixed(0)} KB${_image ? ' · ${AppStrings.t('evidence.zoom')}' : ''}',
                ),
                onTap: _image ? _preview : _share,
                trailing: IconButton(
                  onPressed: _share,
                  tooltip: AppStrings.t('evidence.share'),
                  icon: const Icon(Icons.ios_share_rounded, size: 20),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
