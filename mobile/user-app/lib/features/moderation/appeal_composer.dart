import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../../core/widgets/unsaved_changes_guard.dart';
import 'moderation_service.dart';

class AppealComposer extends StatefulWidget {
  const AppealComposer({
    super.key,
    required this.auth,
    this.targetId = '',
    this.targetType = 'video',
    this.targetLabel = '',
    this.pickEvidence,
  });
  final AuthController auth;
  final String targetId, targetType;
  final String targetLabel;
  final Future<XFile?> Function()? pickEvidence;
  @override
  State<AppealComposer> createState() => _AppealComposerState();
}

class _AppealComposerState extends State<AppealComposer> {
  final _form = GlobalKey<FormState>();
  late final _target = TextEditingController(text: widget.targetId);
  final _reason = TextEditingController();
  final _note = TextEditingController();
  late String _type = widget.targetType;
  late final _session = widget.auth.sessionGeneration;
  String? _appealId, _error;
  XFile? _evidence;
  Uint8List? _evidencePreview;
  bool _busy = false, _saved = false;
  bool get _current => mounted && _session == widget.auth.sessionGeneration;
  @override
  void dispose() {
    _target.dispose();
    _reason.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final file =
          await (widget.pickEvidence?.call() ??
              openFile(
                acceptedTypeGroups: [
                  XTypeGroup(
                    label: AppStrings.t('moderation.evidenceSection'),
                    extensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
                    mimeTypes: [
                      'image/jpeg',
                      'image/png',
                      'image/webp',
                      'application/pdf',
                    ],
                    uniformTypeIdentifiers: [
                      'public.jpeg',
                      'public.png',
                      'org.webmproject.webp',
                      'com.adobe.pdf',
                    ],
                  ),
                ],
              ));
      if (file == null || !_current) return;
      await ModerationService(widget.auth).validateEvidence(file);
      final preview =
          ModerationService(widget.auth).evidenceMime(file).startsWith('image/')
          ? await file.readAsBytes()
          : null;
      if (_current) {
        setState(() {
          _evidencePreview = preview;
          _evidence = file;
          _error = null;
        });
      }
    } catch (_) {
      if (_current) {
        setState(() => _error = AppStrings.t('moderation.evidenceInvalid'));
      }
    }
  }

  Future<void> _submit() async {
    if (_busy || !_current || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = ModerationService(widget.auth);
      if (_evidence != null) await service.validateEvidence(_evidence!);
      if (!_current) return;
      if (_appealId == null) {
        final appeal = await service.createAppeal(
          targetType: _type,
          targetId: _target.text.trim(),
          reason: _reason.text.trim(),
          evidenceNote: _note.text.trim(),
        );
        if (!_current) return;
        _appealId = appeal['appealId'] as String?;
        if (_appealId == null) throw const FormatException('Missing appeal id');
      }
      if (_evidence != null) {
        await service.uploadEvidence(_appealId!, _evidence!);
      }
      if (!_current) return;
      setState(() {
        _saved = true;
        _busy = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (e) {
      if (_current) {
        setState(
          () => _error = e.code == 'EVIDENCE_INVALID'
              ? AppStrings.t('moderation.evidenceInvalid')
              : AppStrings.apiError(e),
        );
      }
    } catch (_) {
      if (_current) setState(() => _error = AppStrings.t('common.error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
    dirty:
        !_saved &&
        (_reason.text.isNotEmpty || _note.text.isNotEmpty || _evidence != null),
    busy: _busy,
    child: SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height *
              (MediaQuery.viewInsetsOf(context).bottom > 0 ? 1 : .92),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppStrings.t('moderation.sendAppeal'),
                              style:
                                  (MediaQuery.sizeOf(context).height -
                                                  MediaQuery.viewInsetsOf(
                                                    context,
                                                  ).bottom <
                                              300
                                          ? Theme.of(
                                              context,
                                            ).textTheme.titleMedium
                                          : Theme.of(
                                              context,
                                            ).textTheme.titleLarge)
                                      ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: AppStrings.t('common.close'),
                        onPressed: _busy
                            ? null
                            : () => Navigator.maybePop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          AppStrings.t('moderation.formHint'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.textMutedFor(context),
                                height: 1.5,
                              ),
                        ),
                        const SizedBox(height: 16),
                        if (_error != null) ...[
                          ErrorBanner(message: _error!),
                          const SizedBox(height: 16),
                        ],
                        _section('moderation.contentSection'),
                        const SizedBox(height: 10),
                        if (widget.targetId.isNotEmpty)
                          HuTubeSurface(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLow,
                            border: BorderSide.none,
                            child: Row(
                              children: [
                                Icon(
                                  _type == 'channel'
                                      ? Icons.live_tv_rounded
                                      : Icons.article_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.targetLabel.isNotEmpty
                                            ? widget.targetLabel
                                            : AppStrings.t(
                                                'moderation.target.$_type',
                                              ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (widget.targetLabel.isNotEmpty)
                                        Text(
                                          AppStrings.t(
                                            'moderation.target.$_type',
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: AppColors.textMutedFor(
                                                  context,
                                                ),
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _type,
                            decoration: InputDecoration(
                              labelText: AppStrings.t('moderation.targetType'),
                              prefixIcon: const Icon(Icons.category_outlined),
                            ),
                            items: ['video', 'channel', 'comment', 'strike']
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(
                                      AppStrings.t('moderation.target.$value'),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _busy || _appealId != null
                                ? null
                                : (value) => setState(() => _type = value!),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _target,
                            key: const ValueKey('appeal-target'),
                            enabled: !_busy && _appealId == null,
                            decoration: InputDecoration(
                              labelText: AppStrings.t('moderation.targetId'),
                              hintText: AppStrings.t('moderation.targetIdHint'),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? AppStrings.t('common.required')
                                : null,
                          ),
                        ],
                        const SizedBox(height: 24),
                        _section('moderation.detailsSection'),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _reason,
                          key: const ValueKey('appeal-reason'),
                          enabled: !_busy && _appealId == null,
                          minLines: 4,
                          maxLines: 7,
                          maxLength: 2000,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: AppStrings.t('moderation.appealReason'),
                            alignLabelWithHint: true,
                            filled: true,
                            fillColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLow,
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? AppStrings.t('common.required')
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _section('moderation.evidenceSection'),
                        const SizedBox(height: 6),
                        Text(
                          AppStrings.t('moderation.evidenceHint'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.textMutedFor(context),
                                height: 1.5,
                              ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _pick,
                          icon: const Icon(Icons.attach_file_rounded),
                          label: Text(
                            _evidence?.name ??
                                AppStrings.t('moderation.attachEvidence'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          AppStrings.t('moderation.evidenceLimit'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.textMutedFor(context),
                              ),
                        ),
                        if (_evidencePreview != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              _evidencePreview!,
                              height: 140,
                              cacheWidth: 800,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        if (_evidence != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      _evidence = null;
                                      _evidencePreview = null;
                                    }),
                              icon: const Icon(Icons.close_rounded, size: 16),
                              label: Text(AppStrings.t('common.delete')),
                            ),
                          ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _note,
                          enabled: !_busy && _appealId == null,
                          minLines: 1,
                          maxLines: 3,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: AppStrings.t('moderation.evidenceNote'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      AppStrings.t(
                        _appealId == null
                            ? 'moderation.sendAppeal'
                            : 'common.retry',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _section(String key) => Text(
    AppStrings.t(key),
    style: Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
  );
}
