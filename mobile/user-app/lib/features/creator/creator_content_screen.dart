import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth.dart';
import '../../channel/models/channel_models.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../content/content_models.dart';
import '../content/content_service.dart';
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
      final result = await loadAllPages(
        (page) => _service.managedVideos(
          widget.channel.id,
          page: page,
          visibility: _visibility,
        ),
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
      builder: (_) => _VideoEditor(item: item, auth: widget.auth),
    );
    if (result == null) return;
    try {
      await _service.updateVideo(
        item.id,
        title: result.title,
        description: result.description,
        visibility: result.visibility,
        categoryId: result.categoryId,
        tags: result.tags,
        chapters: result.chapters,
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

  Future<void> _publish(VideoDetail item) async {
    try {
      await _service.publish(item.id);
      await _load();
      if (mounted) _show(AppStrings.t('creator.publishSuccess'));
    } on ApiFailure catch (error) {
      if (mounted) _show(AppStrings.apiError(error, fallback: 'common.error'));
    }
  }

  Future<void> _retryProcessing(VideoDetail item) async {
    try {
      await _service.retryProcessing(item.id);
      await _load();
      if (mounted) _show(AppStrings.t('creator.reprocessSent'));
    } on ApiFailure catch (error) {
      if (mounted) _show(AppStrings.apiError(error, fallback: 'common.error'));
    }
  }

  Future<void> _cancelUpload(VideoDetail item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.t('creator.cancelUploadTitle')),
        content: Text(
          AppStrings.format('creator.cancelUploadDescription', {
            'title': item.title,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.t('creator.cancelUpload')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.cancelUpload(item.id);
      await _load();
    } on ApiFailure catch (error) {
      if (mounted) _show(AppStrings.apiError(error, fallback: 'common.error'));
    }
  }

  Future<void> _updateThumbnail(VideoDetail item) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(title: Text(AppStrings.t('creator.thumbnailVideo'))),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(AppStrings.t('creator.chooseImageLibrary')),
              onTap: () => Navigator.pop(context, 'pick'),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(AppStrings.t('creator.createThumbnail')),
              onTap: () => Navigator.pop(context, 'generate'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    try {
      if (choice == 'generate') {
        await _service.updateThumbnail(item.id, generate: true);
      } else {
        final image = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: 90,
          maxWidth: 1920,
        );
        if (image == null) return;
        await _service.updateThumbnail(item.id, image: image);
      }
      await _load();
      if (mounted) _show(AppStrings.t('creator.thumbnailUpdated'));
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
                                  if (video.moderationStatus.toLowerCase() !=
                                          'approved' &&
                                      !video.processingStatus
                                          .toLowerCase()
                                          .contains('upload'))
                                    TextButton(
                                      onPressed: () => _submit(video),
                                      child: Text(
                                        AppStrings.t('creator.submitReview'),
                                      ),
                                    ),
                                  IconButton(
                                    tooltip: AppStrings.t(
                                      'creator.thumbnailTooltip',
                                    ),
                                    onPressed: () => _updateThumbnail(video),
                                    icon: const Icon(Icons.image_outlined),
                                  ),
                                  if (video.moderationStatus.toLowerCase() ==
                                          'approved' &&
                                      video.visibility.toLowerCase() !=
                                          'public')
                                    IconButton(
                                      tooltip: AppStrings.t(
                                        'creator.publishVideo',
                                      ),
                                      onPressed: () => _publish(video),
                                      icon: const Icon(Icons.publish_rounded),
                                    ),
                                  if (video.processingStatus
                                      .toLowerCase()
                                      .contains('fail'))
                                    IconButton(
                                      tooltip: AppStrings.t(
                                        'creator.reprocessVideo',
                                      ),
                                      onPressed: () => _retryProcessing(video),
                                      icon: const Icon(Icons.refresh_rounded),
                                    ),
                                  if (video.processingStatus
                                      .toLowerCase()
                                      .contains('upload'))
                                    IconButton(
                                      tooltip: AppStrings.t(
                                        'creator.cancelUploadTooltip',
                                      ),
                                      onPressed: () => _cancelUpload(video),
                                      icon: const Icon(Icons.cancel_outlined),
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
    this.categoryId,
    this.tags = const [],
    this.chapters = const [],
  });

  final String title;
  final String description;
  final String visibility;
  final String? categoryId;
  final List<String> tags;
  final List<Map<String, dynamic>> chapters;
}

class _VideoEditor extends StatefulWidget {
  const _VideoEditor({required this.item, required this.auth});

  final VideoDetail item;
  final AuthController auth;

  @override
  State<_VideoEditor> createState() => _VideoEditorState();
}

class _VideoEditorState extends State<_VideoEditor> {
  late final _title = TextEditingController(text: widget.item.title);
  late final _description = TextEditingController(
    text: widget.item.description ?? '',
  );
  late String _visibility = widget.item.visibility;
  late String? _categoryId = widget.item.categoryId;
  late final List<String> _tags = List<String>.from(widget.item.tags);
  late final List<Map<String, dynamic>> _chapters = widget.item.chapters
      .map((c) => {'startSeconds': c.startSeconds, 'title': c.title})
      .toList();
  final _tagInput = TextEditingController();

  List<Category> _categories = const [];
  bool _loadingCategories = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await ContentService(widget.auth).categories();
      if (mounted) {
        setState(() {
          _categories = cats;
          _loadingCategories = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  void _addTag() {
    final text = _tagInput.text.trim();
    if (text.isNotEmpty && !_tags.contains(text)) {
      setState(() {
        _tags.add(text);
        _tagInput.clear();
      });
    }
  }

  void _addChapter() {
    setState(() {
      final lastSec = _chapters.isEmpty
          ? 0
          : (_chapters.last['startSeconds'] as int) + 60;
      _chapters.add({
        'startSeconds': lastSec,
        'title': 'Chương ${_chapters.length + 1}',
      });
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppStrings.t('creator.editTitle'),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _title,
                maxLength: 150,
                decoration: InputDecoration(
                  labelText: AppStrings.t('creator.titleField'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 4,
                maxLength: 5000,
                decoration: InputDecoration(
                  labelText: AppStrings.t('creator.descriptionField'),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: _categoryId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: AppStrings.t('upload.topic'),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(AppStrings.t('upload.none')),
                  ),
                  ..._categories.map(
                    (category) => DropdownMenuItem<String?>(
                      value: category.id,
                      child: Text(category.name),
                    ),
                  ),
                ],
                onChanged: _loadingCategories
                    ? null
                    : (value) => setState(() => _categoryId = value),
              ),
              const SizedBox(height: 14),

              // Tags section
              const Text(
                'Thẻ tags',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 6),
              if (_tags.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _tags
                      .map(
                        (tag) => Chip(
                          label: Text(tag, style: const TextStyle(fontSize: 12)),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: () => setState(() => _tags.remove(tag)),
                        ),
                      )
                      .toList(),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tagInput,
                      decoration: const InputDecoration(
                        hintText: 'Nhập tag và bấm thêm...',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addTag(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _addTag,
                    child: const Text('Thêm'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Chapters section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Chương video (Chapters)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  TextButton.icon(
                    onPressed: _addChapter,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Thêm chương'),
                  ),
                ],
              ),
              if (_chapters.isEmpty)
                Text(
                  'Chưa có mốc chương nào.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                )
              else
                ..._chapters.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final ch = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            initialValue: '${ch['startSeconds']}',
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Giây',
                              isDense: true,
                            ),
                            onChanged: (val) {
                              ch['startSeconds'] = int.tryParse(val) ?? 0;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: '${ch['title']}',
                            decoration: const InputDecoration(
                              labelText: 'Tiêu đề chương',
                              isDense: true,
                            ),
                            onChanged: (val) {
                              ch['title'] = val.trim();
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () =>
                              setState(() => _chapters.removeAt(idx)),
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 14),

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
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _VideoEdit(
                    title: _title.text.trim(),
                    description: _description.text.trim(),
                    visibility: _visibility,
                    categoryId: _categoryId,
                    tags: _tags,
                    chapters: _chapters,
                  ),
                ),
                child: Text(AppStrings.t('creator.save')),
              ),
            ],
          ),
        ),
      ),
    ),
  );

}
