import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth.dart';
import '../../channel/models/channel_models.dart';
import '../../core/errors/app_error.dart';
import '../../core/theme/app_theme.dart';
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
      if (mounted)
        setState(() {
          _error = error.message;
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _error = 'Không thể tải nội dung kênh.';
          _loading = false;
        });
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
      if (mounted) _show(error.message);
    }
  }

  Future<void> _submit(VideoDetail item) async {
    try {
      await _service.submitModeration(item.id);
      await _load();
      if (mounted) _show('Video đã được gửi vào hàng đợi kiểm duyệt.');
    } on ApiFailure catch (error) {
      if (mounted) _show(error.message);
    }
  }

  Future<void> _delete(VideoDetail item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa video?'),
        content: Text('“${item.title}” sẽ bị xóa khỏi HuTube.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteVideo(item.id);
      await _load();
    } on ApiFailure catch (error) {
      if (mounted) _show(error.message);
    }
  }

  void _show(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Nội dung kênh'),
      actions: [
        PopupMenuButton<String?>(
          tooltip: 'Lọc quyền riêng tư',
          initialValue: _visibility,
          onSelected: (value) {
            setState(() => _visibility = value);
            _load();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: null, child: Text('Tất cả video')),
            PopupMenuItem(value: 'public', child: Text('Công khai')),
            PopupMenuItem(value: 'unlisted', child: Text('Không công khai')),
            PopupMenuItem(value: 'private', child: Text('Riêng tư')),
          ],
        ),
      ],
    ),
    body: _loading
        ? const Center(
            child: CircularProgressIndicator(color: AppColors.primaryPink),
          )
        : _error != null
        ? Center(
            child: FilledButton(onPressed: _load, child: Text(_error!)),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: _items.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 190),
                      Center(child: Text('Kênh chưa có video.')),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
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
                                        ? video.visibility
                                        : video.moderationStatus,
                                  ),
                                  const Spacer(),
                                  if (video.visibility == 'public' &&
                                      video.moderationStatus.toLowerCase() !=
                                          'approved')
                                    TextButton(
                                      onPressed: () => _submit(video),
                                      child: const Text('Gửi duyệt'),
                                    ),
                                  IconButton(
                                    tooltip: 'Sửa video',
                                    onPressed: () => _edit(video),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Xóa video',
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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.primaryPink.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppColors.primaryPink),
      ),
    ),
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
            'Chỉnh sửa video',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Tiêu đề'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Mô tả'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _visibility,
            decoration: const InputDecoration(labelText: 'Chế độ hiển thị'),
            items: const [
              DropdownMenuItem(value: 'private', child: Text('Riêng tư')),
              DropdownMenuItem(
                value: 'unlisted',
                child: Text('Không công khai'),
              ),
              DropdownMenuItem(
                value: 'public',
                child: Text('Công khai (cần kiểm duyệt)'),
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
            child: const Text('Lưu thay đổi'),
          ),
        ],
      ),
    ),
  );
}
