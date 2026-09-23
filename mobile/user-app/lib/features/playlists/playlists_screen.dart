import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'playlist_service.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key, required this.auth, this.playlistId});
  final AuthController auth;
  final String? playlistId;

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  late final PlaylistService _service = PlaylistService(widget.auth);
  List<PlaylistSummary> _playlists = const [];
  PlaylistDetail? _detail;
  bool _loading = true;
  String? _error;

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
      if (widget.playlistId != null) {
        final detail = await _service.get(widget.playlistId!);
        if (mounted)
          setState(() {
            _detail = detail;
            _loading = false;
          });
      } else {
        final playlists = await _service.mine();
        if (mounted)
          setState(() {
            _playlists = playlists;
            _loading = false;
          });
      }
    } on ApiFailure catch (error) {
      if (mounted)
        setState(() {
          _error = AppStrings.apiError(error, fallback: 'common.error');
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _error = AppStrings.t('common.networkError');
          _loading = false;
        });
    }
  }

  Future<void> _edit({PlaylistSummary? playlist}) async {
    final name = TextEditingController(text: playlist?.name ?? '');
    final description = TextEditingController(
      text: playlist?.description ?? '',
    );
    var visibility = playlist?.visibility ?? 'private';
    final values = await showModalBottomSheet<(String, String, String)?>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, refresh) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                playlist == null ? 'Tạo playlist' : 'Chỉnh sửa playlist',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: name,
                autofocus: true,
                maxLength: 150,
                decoration: const InputDecoration(labelText: 'Tên playlist'),
              ),
              TextField(
                controller: description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Mô tả'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: visibility,
                decoration: const InputDecoration(labelText: 'Quyền riêng tư'),
                items: const [
                  DropdownMenuItem(value: 'private', child: Text('Riêng tư')),
                  DropdownMenuItem(value: 'public', child: Text('Công khai')),
                  DropdownMenuItem(
                    value: 'unlisted',
                    child: Text('Không công khai'),
                  ),
                ],
                onChanged: (value) =>
                    refresh(() => visibility = value ?? 'private'),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext, (
                  name.text.trim(),
                  description.text.trim(),
                  visibility,
                )),
                child: Text(playlist == null ? 'Tạo playlist' : 'Lưu thay đổi'),
              ),
            ],
          ),
        ),
      ),
    );
    name.dispose();
    description.dispose();
    if (values == null || values.$1.isEmpty) return;
    try {
      if (playlist == null) {
        final created = await _service.create(
          name: values.$1,
          description: values.$2,
          visibility: values.$3,
        );
        if (mounted) context.push('/playlists/${created.id}');
      } else {
        await _service.update(
          playlist.id,
          name: values.$1,
          description: values.$2,
          visibility: values.$3,
        );
      }
      await _load();
    } on ApiFailure catch (error) {
      _message(AppStrings.apiError(error, fallback: 'common.error'));
    }
  }

  Future<void> _delete(PlaylistSummary playlist) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa playlist?'),
        content: Text('“${playlist.name}” sẽ bị xóa khỏi thư viện của bạn.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.t('common.delete')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _service.delete(playlist.id);
      await _load();
    } on ApiFailure catch (error) {
      _message(AppStrings.apiError(error, fallback: 'common.error'));
    }
  }

  Future<void> _removeVideo(PlaylistItem item) async {
    final id = widget.playlistId;
    if (id == null) return;
    try {
      await _service.removeVideo(id, item.videoId);
      await _load();
    } on ApiFailure catch (error) {
      _message(AppStrings.apiError(error, fallback: 'common.error'));
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final current = _detail;
    if (current == null) return;
    if (newIndex > oldIndex) newIndex--;
    final items = [...current.items];
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    setState(
      () => _detail = PlaylistDetail(
        id: current.id,
        name: current.name,
        visibility: current.visibility,
        description: current.description,
        items: items,
      ),
    );
    try {
      await _service.reorder(
        current.id,
        items.map((item) => item.videoId).toList(),
      );
    } on ApiFailure catch (error) {
      _message(AppStrings.apiError(error, fallback: 'common.error'));
      await _load();
    }
  }

  void _message(String message) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return HuTubeStateView(
        icon: Icons.playlist_play_rounded,
        title: _error!,
        message: AppStrings.t('common.networkError'),
        actionLabel: AppStrings.t('common.retry'),
        onAction: _load,
        accent: AppColors.primary,
      );
    }
    final detail = _detail;
    if (widget.playlistId != null && detail != null) {
      return _buildDetail(detail);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          HuTubeSectionHeader(
            title: 'Playlist của bạn',
            subtitle: 'Lưu và sắp xếp video để xem lại bất cứ lúc nào.',
            action: widget.auth.authenticated ? 'Tạo mới' : null,
            onAction: _edit,
          ),
          const SizedBox(height: 18),
          if (_playlists.isEmpty)
            HuTubeStateView(
              icon: Icons.playlist_add_rounded,
              title: 'Thư viện playlist đang trống',
              message: 'Tạo playlist đầu tiên hoặc lưu video từ màn hình xem.',
              actionLabel: 'Tạo playlist',
              onAction: _edit,
              compact: true,
              accent: AppColors.primary,
            )
          else
            for (final playlist in _playlists)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceFor(context),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: AppColors.borderFor(context)),
                  ),
                  child: ListTile(
                    onTap: () => context.push('/playlists/${playlist.id}'),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.playlist_play_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                    title: Text(
                      playlist.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${playlist.itemCount} video · ${_visibility(playlist.visibility)}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _edit(playlist: playlist);
                        if (value == 'delete') _delete(playlist);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa')),
                        PopupMenuItem(value: 'delete', child: Text('Xóa')),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildDetail(PlaylistDetail detail) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Row(
          children: [
            IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${detail.items.length} video · ${_visibility(detail.visibility)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: detail.items.isEmpty
            ? HuTubeStateView(
                icon: Icons.playlist_add_rounded,
                title: 'Playlist chưa có video',
                message:
                    'Mở một video rồi chọn “Lưu playlist” để thêm vào đây.',
                accent: AppColors.primary,
              )
            : ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: detail.items.length,
                onReorder: _reorder,
                itemBuilder: (context, index) {
                  final item = detail.items[index];
                  return ListTile(
                    key: ValueKey(item.videoId),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 76,
                        height: 48,
                        child: item.thumbnailUrl == null
                            ? const ColoredBox(
                                color: AppColors.ink,
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                ),
                              )
                            : Image.network(
                                item.thumbnailUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const ColoredBox(color: AppColors.ink),
                              ),
                      ),
                    ),
                    title: Text(
                      item.title ?? 'Video không khả dụng',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: item.available
                        ? null
                        : const Text('Video hiện không phát được'),
                    onTap: item.available
                        ? () => context.push('/watch/${item.videoId}')
                        : null,
                    trailing: PopupMenuButton<String>(
                      onSelected: (choice) {
                        if (choice == 'remove') _removeVideo(item);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'remove',
                          child: Text('Xóa khỏi playlist'),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    ],
  );

  String _visibility(String value) => switch (value.toLowerCase()) {
    'public' => 'Công khai',
    'unlisted' => 'Không công khai',
    _ => 'Riêng tư',
  };
}
