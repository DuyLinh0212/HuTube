import 'dart:async';
import 'package:flutter/material.dart';
import '../../../auth.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hutube_widgets.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../content_models.dart';
import '../content_service.dart';

/// Edits stay close to the keyboard instead of opening a centered dialog.
class CommentEditorSheet extends StatefulWidget {
  const CommentEditorSheet({
    super.key,
    required this.initialValue,
    required this.onSubmit,
  });
  final String initialValue;
  final Future<void> Function(String text) onSubmit;
  @override
  State<CommentEditorSheet> createState() => _CommentEditorSheetState();
}

class _CommentEditorSheetState extends State<CommentEditorSheet> {
  late final _text = TextEditingController(text: widget.initialValue);
  bool _busy = false, _saved = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (_busy || text.isEmpty || text == widget.initialValue.trim()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _saved = true;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is ApiFailure
              ? AppStrings.apiError(error)
              : AppStrings.t('common.networkError');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
    dirty: !_saved && _text.text != widget.initialValue,
    busy: _busy,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStrings.t('watch.editComment'),
                        style:
                            (MediaQuery.sizeOf(context).height -
                                            MediaQuery.viewInsetsOf(
                                              context,
                                            ).bottom <
                                        300
                                    ? Theme.of(context).textTheme.titleSmall
                                    : Theme.of(context).textTheme.titleMedium)
                                ?.copyWith(fontWeight: FontWeight.w700),
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.t('watch.editHint'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMutedFor(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('text-entry-input'),
                        controller: _text,
                        autofocus: true,
                        enabled: !_busy,
                        minLines: 3,
                        maxLines: 7,
                        maxLength: 2000,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      if (_error != null)
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: FilledButton(
                  onPressed:
                      _busy ||
                          _text.text.trim().isEmpty ||
                          _text.text.trim() == widget.initialValue.trim()
                      ? null
                      : _save,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(AppStrings.t('common.save')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

typedef ThreadCommentBuilder =
    Widget Function(
      CommentItem item,
      ValueChanged<CommentItem> onUpdated,
      VoidCallback? onReply,
    );

class CommentThreadSheet extends StatefulWidget {
  const CommentThreadSheet({
    super.key,
    required this.auth,
    required this.content,
    required this.parent,
    required this.tileBuilder,
    required this.onParentChanged,
    this.focusComposer = false,
    this.initialDraft = '',
    this.onDraftChanged,
  });
  final AuthController auth;
  final ContentService content;
  final CommentItem parent;
  final ThreadCommentBuilder tileBuilder;
  final ValueChanged<CommentItem> onParentChanged;
  final bool focusComposer;
  final String initialDraft;
  final ValueChanged<String>? onDraftChanged;
  @override
  State<CommentThreadSheet> createState() => _CommentThreadSheetState();
}

class _CommentThreadSheetState extends State<CommentThreadSheet> {
  late CommentItem _parent = widget.parent;
  late final _input = TextEditingController(text: widget.initialDraft);
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late final _session = widget.auth.sessionGeneration;
  List<CommentItem> _replies = [];
  bool _loading = false, _sending = false;
  int _page = 0, _total = 0;
  String? _loadError, _sendError;
  bool get _current => mounted && _session == widget.auth.sessionGeneration;
  @override
  void initState() {
    super.initState();
    _total = _parent.replyCount;
    if (_total > 0) _load();
    if (widget.focusComposer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || !_current) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final page = await widget.content.replies(
        _parent.id,
        page: reset ? 1 : _page + 1,
        pageSize: 3,
      );
      if (!_current) return;
      setState(() {
        _replies = {
          if (!reset)
            for (final item in _replies) item.id: item,
          for (final item in page.items) item.id: item,
        }.values.toList();
        _page = page.page;
        _total = page.total > _replies.length ? page.total : _replies.length;
      });
    } catch (_) {
      if (_current) {
        setState(() => _loadError = AppStrings.t('watch.replyLoadError'));
      }
    } finally {
      if (_current) setState(() => _loading = false);
    }
  }

  void _updateParent(CommentItem item) {
    if (!_current) return;
    widget.onParentChanged(item);
    if (item.status == 'deleted') {
      Navigator.pop(context);
      return;
    }
    setState(() => _parent = item);
  }

  void _updateReply(CommentItem item) {
    if (!_current) return;
    setState(() {
      if (item.status == 'deleted') {
        _replies.removeWhere((value) => value.id == item.id);
        _total = (_total - 1).clamp(0, 1 << 31);
        _parent = _parent.copyWith(
          replyCount: (_parent.replyCount - 1).clamp(0, 1 << 31),
        );
      } else {
        _replies = _replies
            .map((value) => value.id == item.id ? item : value)
            .toList();
      }
    });
    widget.onParentChanged(_parent);
    if (item.status == 'deleted') unawaited(_load(reset: true));
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_sending || text.isEmpty || !_current || !widget.auth.authenticated) {
      return;
    }
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final reply = await widget.content.createComment(
        _parent.videoId,
        text,
        parentCommentId: _parent.id,
      );
      if (!_current) return;
      setState(() {
        if (!_replies.any((item) => item.id == reply.id)) _replies.add(reply);
        _total++;
        _parent = _parent.copyWith(replyCount: _parent.replyCount + 1);
        _input.clear();
      });
      widget.onDraftChanged?.call('');
      widget.onParentChanged(_parent);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (error) {
      if (_current) {
        setState(
          () => _sendError = error is ApiFailure
              ? AppStrings.apiError(error)
              : AppStrings.t('common.networkError'),
        );
      }
    } finally {
      if (_current) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final top = MediaQuery.paddingOf(context).top;
    final playerHeight = (viewport.width * 9 / 16).clamp(
      0.0,
      viewport.height * .4,
    );
    final height = keyboard > 0 || viewport.height < 500
        ? viewport.height - top
        : viewport.height - top - playerHeight;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: AppStrings.t('common.back'),
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Text(
                        AppStrings.t('watch.replyThreadTitle'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: AppStrings.t('common.close'),
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  key: ValueKey('comment-thread-${_parent.id}'),
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    ColoredBox(
                      color: colors.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                        child: widget.tileBuilder(
                          _parent,
                          _updateParent,
                          () => _focus.requestFocus(),
                        ),
                      ),
                    ),
                    for (final reply in _replies)
                      Container(
                        margin: const EdgeInsets.only(left: 28, right: 8),
                        padding: const EdgeInsets.only(left: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: colors.outlineVariant),
                          ),
                        ),
                        child: widget.tileBuilder(reply, _updateReply, null),
                      ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    if (_loadError != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: HuTubeNotice(
                          message: _loadError!,
                          actionLabel: AppStrings.t('common.retry'),
                          onAction: _load,
                        ),
                      ),
                    if (!_loading &&
                        _loadError == null &&
                        _replies.length < _total)
                      TextButton(
                        key: ValueKey('comment-more-${_parent.id}'),
                        onPressed: _load,
                        child: Text(
                          AppStrings.format('watch.moreReplies', {
                            'count': AppStrings.number(
                              _total - _replies.length,
                            ),
                          }),
                        ),
                      ),
                  ],
                ),
              ),
              if (_sendError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    _sendError!,
                    style: TextStyle(color: colors.error),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: colors.outlineVariant)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: widget.auth.authenticated
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: 7,
                                right: 10,
                              ),
                              child: HuTubeAvatar(
                                url: widget.auth.user?['avatarUrl'] as String?,
                                label:
                                    '${widget.auth.user?['displayName'] ?? ''}',
                                radius: 15,
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                key: const ValueKey('thread-reply-input'),
                                controller: _input,
                                focusNode: _focus,
                                minLines: 1,
                                maxLines: viewport.height - keyboard < 400
                                    ? 1
                                    : 3,
                                maxLength: 2000,
                                enabled: !_sending,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                onChanged: (value) {
                                  setState(() {});
                                  widget.onDraftChanged?.call(value);
                                },
                                decoration: InputDecoration(
                                  hintText: AppStrings.t('watch.replyHint'),
                                  counterText: '',
                                  filled: true,
                                  isDense: true,
                                  fillColor: colors.surfaceContainerHigh,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton.filled(
                              tooltip: AppStrings.t('common.send'),
                              onPressed: _sending || _input.text.trim().isEmpty
                                  ? null
                                  : _send,
                              icon: _sending
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.arrow_upward_rounded),
                            ),
                          ],
                        )
                      : Text(
                          AppStrings.t('watch.loginCommentHint'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
