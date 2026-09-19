import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../channel/models/channel_models.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../content/content_models.dart';
import '../content/video_card.dart';
import 'creator_service.dart';

class CreatorContentScreen extends StatefulWidget {
  const CreatorContentScreen({
    super.key,
    required this.auth,
    required this.channel,
  });
  final AuthController auth;
  final ChannelDetail channel;

  @override
  State<CreatorContentScreen> createState() => _CreatorContentScreenState();
}

class _CreatorContentScreenState extends State<CreatorContentScreen> {
  late final CreatorService _service = CreatorService(widget.auth);
  List<VideoDetail> _items = const [];
  bool _loading = true;
  String? _error;
  String? _visibility;

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
      final result = await _service.managedVideos(
        widget.channel.id,
        visibility: _visibility,
      );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _loading = false;
      });
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = AppStrings.apiError(error, fallback: 'creator.loadError');
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppStrings.t('creator.loadError');
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit(VideoDetail item) async {
    final result = await showModalBottomSheet<_VideoEdit>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VideoEditor(item: item),
    );
    if (result == null) return;
    try {
      await _service.updateVideo(
        item.id,
        title: result.title,
        description: result.description,
        visibility: result.visibility,
      );
      await _load();
    } on ApiFailure catch (error) {
      if (mounted) _show(AppStrings.apiError(error, fallback: 'common.error'));
    }
  }

  Future<void> _submit(VideoDetail item) async {
    try {
      await _service.submitModeration(item.id);
      await _load();
      if (mounted) _show(AppStrings.t('creator.submitted'));
    } on ApiFailure catch (error) {
      if (mounted) _show(AppStrings.apiError(error, fallback: 'common.error'));
    }
  }

  Future<void> _delete(VideoDetail item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.t('creator.deleteVideoTitle')),
        content: Text(
          AppStrings.format('creator.deleteVideoDescription', {
            'title': item.title,
          }),
        ),
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
      await _service.deleteVideo(item.id);
      await _load();
    } on ApiFailure catch (error) {
      if (mounted) _show(AppStrings.apiError(error, fallback: 'common.error'));
    }
  }

  String _statusLabel(String status) {
    return switch (status.toLowerCase()) {
      'approved' => AppStrings.t('creator.approved'),
      'pending' || 'pending_review' => AppStrings.t('creator.pendingReview'),
      'reviewing' || 'in_review' => AppStrings.t('creator.reviewing'),
      'rejected' => AppStrings.t('creator.rejected'),
      'not_submitted' || '' => AppStrings.t('creator.notSubmitted'),
      'public' => AppStrings.t('creator.public'),
      'unlisted' => AppStrings.t('creator.unlisted'),
      'private' => AppStrings.t('creator.private'),
      _ => status,
    };
  }

  void _show(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(AppStrings.t('creator.content')),
      actions: [
        PopupMenuButton<String?>(
          tooltip: AppStrings.t('creator.filterPrivacy'),
          initialValue: _visibility,
          onSelected: (value) {
            setState(() => _visibility = value);
            _load();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: null,
              child: Text(AppStrings.t('creator.allVideos')),
            ),
            PopupMenuItem(
              value: 'public',
              child: Text(AppStrings.t('creator.public')),
            ),
            PopupMenuItem(
              value: 'unlisted',
              child: Text(AppStrings.t('creator.unlisted')),
            ),
            PopupMenuItem(
              value: 'private',
              child: Text(AppStrings.t('creator.private')),
            ),
          ],
        ),
      ],
    ),
    body: _loading
        ? const Center(
            child: CircularProgressIndicator(color: AppColors.violet),
          )
        : _error != null
        ? HuTubeStateView(
            icon: Icons.video_library_outlined,
            title: _error!,
            message: AppStrings.t('common.networkError'),
            actionLabel: AppStrings.t('common.retry'),
            onAction: _load,
            accent: AppColors.violet,
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: _items.isEmpty
                ? ListView(
                    children: [
                      HuTubeStateView(
                        icon: Icons.video_library_outlined,
                        title: AppStrings.t('creator.noManagedVideos'),
                        message: AppStrings.t('creator.uploadDescription'),
                        compact: true,
                        accent: AppColors.violet,
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, index) {
                      final video = _items[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            VideoCardTile(video: video),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
                              child: Row(
                                children: [
                                  _StatusPill(
                                    label: video.moderationStatus.isEmpty
                                        ? _statusLabel(video.visibility)
                                        : _statusLabel(video.moderationStatus),
                                  ),
                                  const Spacer(),
                                  if (video.visibility == 'public' &&
                                      video.moderationStatus.toLowerCase() !=
                                          'approved')
                                    TextButton(
                                      onPressed: () => _submit(video),
                                      child: Text(
                                        AppStrings.t('creator.submitReview'),
                                      ),
                                    ),
                                  IconButton(
                                    tooltip: AppStrings.t('creator.editVideo'),
                                    onPressed: () => _edit(video),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: AppStrings.t(
                                      'creator.deleteVideo',
                                    ),
                                    onPressed: () => _delete(video),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => HuTubePill(
    label: label,
    color: AppColors.violetContainerFor(context),
    textColor: AppColors.violet,
  );
}

class _VideoEdit {
  const _VideoEdit({
    required this.title,
    required this.description,
    required this.visibility,
  });
  final String title;
  final String description;
  final String visibility;
}

class _VideoEditor extends StatefulWidget {
  const _VideoEditor({required this.item});
  final VideoDetail item;
  @override
  State<_VideoEditor> createState() => _VideoEditorState();
}

class _VideoEditorState extends State<_VideoEditor> {
  late final _title = TextEditingController(text: widget.item.title);
  late final _description = TextEditingController(
    text: widget.item.description ?? '',
  );
  late String _visibility = widget.item.visibility;
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.t('creator.editTitle'),
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: InputDecoration(
              labelText: AppStrings.t('creator.titleField'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: AppStrings.t('creator.descriptionField'),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _visibility,
            decoration: InputDecoration(
              labelText: AppStrings.t('creator.visibilityField'),
            ),
            items: [
              DropdownMenuItem(
                value: 'private',
                child: Text(AppStrings.t('creator.private')),
              ),
              DropdownMenuItem(
                value: 'unlisted',
                child: Text(AppStrings.t('creator.unlisted')),
              ),
              DropdownMenuItem(
                value: 'public',
                child: Text(AppStrings.t('creator.publicModeration')),
              ),
            ],
            onChanged: (value) => setState(() => _visibility = value!),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _VideoEdit(
                title: _title.text,
                description: _description.text,
                visibility: _visibility,
              ),
            ),
            child: Text(AppStrings.t('creator.save')),
          ),
        ],
      ),
    ),
  );
}
