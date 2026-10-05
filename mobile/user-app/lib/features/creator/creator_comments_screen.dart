import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth.dart';
import '../../channel/models/channel_models.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../content/content_models.dart';
import 'creator_service.dart';

class CreatorCommentsScreen extends StatefulWidget {
  const CreatorCommentsScreen({
    super.key,
    required this.auth,
    required this.channel,
  });
  final AuthController auth;
  final ChannelDetail channel;
  @override
  State<CreatorCommentsScreen> createState() => _CreatorCommentsScreenState();
}

class _CreatorCommentsScreenState extends State<CreatorCommentsScreen> {
  late final CreatorService _service = CreatorService(widget.auth);
  List<CommentItem> _comments = const [];
  bool _loading = true;
  String? _error;
  String _status = 'visible';
  String _sort = 'newest';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await loadAllPages(
        (page) => _service.managedComments(
          widget.channel.id,
          page: page,
          status: _status,
          sort: _sort,
        ),
      );
      if (mounted) {
        setState(() {
          _comments = page.items;
          _loading = false;
        });
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = AppStrings.apiError(error, fallback: 'common.error');
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppStrings.t('creator.noComments');
          _loading = false;
        });
      }
    }
  }

  void _setStatus(String status) {
    if (_status == status) return;
    setState(() => _status = status);
    _load();
  }

  void _setSort(String sort) {
    if (_sort == sort) return;
    setState(() => _sort = sort);
    _load();
  }

  Future<void> _toggleHidden(CommentItem comment) async {
    final hide = comment.status != 'hidden';
    try {
      await _service.setCommentHidden(comment.id, hide);
      if (!mounted) return;
      setState(() {
        final newStatus = hide ? 'hidden' : 'visible';
        if (newStatus != _status) {
          _comments = _comments.where((item) => item.id != comment.id).toList();
        } else {
          _comments = _comments
              .map(
                (item) => item.id == comment.id
                    ? item.copyWith(status: newStatus)
                    : item,
              )
              .toList();
        }
      });
    } on ApiFailure catch (error) {
      if (mounted) {
        _message(AppStrings.apiError(error, fallback: 'common.error'));
      }
    }
  }

  Future<void> _delete(CommentItem comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.t('creator.commentDeleteTitle')),
        content: Text(AppStrings.t('creator.commentDeleteDescription')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(AppStrings.t('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteComment(comment.id);
      if (mounted) {
        setState(
          () => _comments = _comments
              .where((item) => item.id != comment.id)
              .toList(),
        );
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        _message(AppStrings.apiError(error, fallback: 'common.error'));
      }
    }
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppStrings.t('creator.commentsTitle'))),
    body: _loading
        ? const Center(
            child: CircularProgressIndicator(color: AppColors.violet),
          )
        : _error != null
        ? HuTubeStateView(
            icon: Icons.forum_outlined,
            title: _error!,
            message: AppStrings.t('common.networkError'),
            actionLabel: AppStrings.t('common.retry'),
            onAction: _load,
            accent: AppColors.violet,
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: _comments.isEmpty
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: _buildControls(context),
                      ),
                      HuTubeStateView(
                        icon: Icons.forum_outlined,
                        title: AppStrings.t('creator.noComments'),
                        message: AppStrings.t(
                          'creator.commentsEmptyDescription',
                        ),
                        compact: true,
                        accent: AppColors.violet,
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: _comments.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      if (index == 0) return _buildControls(context);
                      final comment = _comments[index - 1];
                      final hidden = comment.status == 'hidden';
                      return Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceFor(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.borderFor(context),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 4, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  HuTubeAvatar(
                                    label: comment.displayName,
                                    radius: 19,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          comment.displayName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          _dateLabel(comment.createdAt),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (choice) {
                                      if (choice == 'visibility') {
                                        _toggleHidden(comment);
                                      }
                                      if (choice == 'delete') _delete(comment);
                                    },
                                    itemBuilder: (_) => [
                                      PopupMenuItem(
                                        value: 'visibility',
                                        child: Text(
                                          hidden
                                              ? AppStrings.t(
                                                  'creator.showComment',
                                                )
                                              : AppStrings.t(
                                                  'creator.hideComment',
                                                ),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text(
                                          AppStrings.t('creator.deleteComment'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              InkWell(
                                onTap: () =>
                                    context.push('/watch/${comment.videoId}'),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.violet.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.smart_display_outlined,
                                        size: 18,
                                        color: AppColors.violet,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          comment.videoTitle
                                                      ?.trim()
                                                      .isNotEmpty ==
                                                  true
                                              ? comment.videoTitle!
                                              : AppStrings.t(
                                                  'creator.commentVideoUnavailable',
                                                ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.violet,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.open_in_new,
                                        size: 16,
                                        color: AppColors.violet,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 9),
                              Text(
                                comment.content,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 9),
                              Row(
                                children: [
                                  const Icon(Icons.favorite_border, size: 16),
                                  const SizedBox(width: 4),
                                  Text('${comment.likes}'),
                                  const SizedBox(width: 14),
                                  const Icon(
                                    Icons.mode_comment_outlined,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text('${comment.replyCount}'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
  );

  Widget _buildControls(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surfaceFor(context),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.borderFor(context)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.t('creator.commentStatusFilter'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _statusChip('visible', 'creator.visibleComments'),
            _statusChip('hidden', 'creator.hiddenComments'),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey(_sort),
          initialValue: _sort,
          decoration: InputDecoration(
            labelText: AppStrings.t('creator.commentSortLabel'),
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
              value: 'newest',
              child: Text(AppStrings.t('creator.commentSortNewest')),
            ),
            DropdownMenuItem(
              value: 'oldest',
              child: Text(AppStrings.t('creator.commentSortOldest')),
            ),
            DropdownMenuItem(
              value: 'mostLiked',
              child: Text(AppStrings.t('creator.commentSortMostLiked')),
            ),
          ],
          onChanged: (value) {
            if (value != null) _setSort(value);
          },
        ),
      ],
    ),
  );

  Widget _statusChip(String status, String labelKey) => ChoiceChip(
    label: Text(AppStrings.t(labelKey)),
    selected: _status == status,
    onSelected: (_) => _setStatus(status),
  );

  String _dateLabel(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }
}
