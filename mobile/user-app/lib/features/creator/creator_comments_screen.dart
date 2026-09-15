import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth.dart';
import '../../channel/models/channel_models.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
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
  final Set<String> _hidden = {};

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
      final page = await _service.managedComments(widget.channel.id);
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

  Future<void> _toggleHidden(CommentItem comment) async {
    final hide = !_hidden.contains(comment.id);
    try {
      await _service.setCommentHidden(comment.id, hide);
      if (!mounted) return;
      setState(() {
        if (hide) {
          _hidden.add(comment.id);
        } else {
          _hidden.remove(comment.id);
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
            child: CircularProgressIndicator(color: AppColors.primaryPink),
          )
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _load,
                  child: Text(AppStrings.t('common.retry')),
                ),
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: _comments.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 190),
                      Center(child: Text(AppStrings.t('creator.noComments'))),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _comments.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final comment = _comments[index];
                      final hidden = _hidden.contains(comment.id);
                      return Card(
                        child: ListTile(
                          onTap: () =>
                              context.push('/watch/${comment.videoId}'),
                          leading: CircleAvatar(
                            child: Text(
                              comment.displayName.isEmpty
                                  ? 'H'
                                  : comment.displayName
                                        .substring(0, 1)
                                        .toUpperCase(),
                            ),
                          ),
                          title: Text(comment.displayName),
                          subtitle: Text(
                            comment.content,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
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
                                      ? AppStrings.t('creator.showComment')
                                      : AppStrings.t('creator.hideComment'),
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
                        ),
                      );
                    },
                  ),
          ),
  );
}
