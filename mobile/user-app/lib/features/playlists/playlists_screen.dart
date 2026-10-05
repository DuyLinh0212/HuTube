import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../../core/widgets/scrollable_sheet.dart';
import '../content/content_models.dart';
import '../content/content_service.dart';
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
  late final ContentService _content = ContentService(widget.auth);
  List<PlaylistSummary> _playlists = const [];
  Map<String, PlaylistDetail> _previews = const {};
  PlaylistDetail? _detail;
  List<VideoCard> _videoOptions = const [];
  String _videoSearch = '';
  bool _videoLoading = false;
  bool _loading = true;
  bool _busy = false;
  bool _canManage = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _isOwner(String userId) =>
      userId.isNotEmpty && userId == '${widget.auth.user?['userId'] ?? ''}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.playlistId != null) {
        final detail = await _service.get(widget.playlistId!);
        if (mounted) {
          setState(() {
            _detail = detail;
            _canManage = _isOwner(detail.userId);
            _loading = false;
          });
        }
      } else {
        final playlists = await _service.mine();
        final previews = <String, PlaylistDetail>{};
        final results = await Future.wait(
          playlists
              .take(12)
              .map(
                (playlist) => _service
                    .get(playlist.id)
                    .catchError(
                      (_) => PlaylistDetail(
                        id: playlist.id,
                        name: playlist.name,
                        visibility: playlist.visibility,
                        items: const [],
                        coverUrl: playlist.coverUrl,
                      ),
                    ),
              ),
        );
        for (final detail in results) {
          previews[detail.id] = detail;
        }
        if (mounted) {
          setState(() {
            _playlists = playlists;
            _previews = previews;
            _loading = false;
          });
        }
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
          _error = AppStrings.t('common.networkError');
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit({
    PlaylistSummary? playlist,
    PlaylistDetail? detail,
  }) async {
    final name = TextEditingController(
      text: playlist?.name ?? detail?.name ?? '',
    );
    final description = TextEditingController(
      text: playlist?.description ?? detail?.description ?? '',
    );
    var visibility = playlist?.visibility ?? detail?.visibility ?? 'private';
    final values = await showModalBottomSheet<(String, String, String)?>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, refresh) => ScrollableSheet(
          child: Padding(
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
                  AppStrings.t(
                    playlist == null && detail == null
                        ? 'playlists.create'
                        : 'playlists.edit',
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: name,
                  autofocus: true,
                  maxLength: 150,
                  decoration: InputDecoration(
                    labelText: AppStrings.t('playlists.name'),
                  ),
                ),
                TextField(
                  controller: description,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: AppStrings.t('playlists.descriptionField'),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: visibility,
                  decoration: InputDecoration(
                    labelText: AppStrings.t('playlists.privacy'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'private',
                      child: Text(AppStrings.t('playlists.private')),
                    ),
                    DropdownMenuItem(
                      value: 'public',
                      child: Text(AppStrings.t('playlists.public')),
                    ),
                    DropdownMenuItem(
                      value: 'unlisted',
                      child: Text(AppStrings.t('playlists.unlisted')),
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
                  child: Text(
                    AppStrings.t(
                      playlist == null && detail == null
                          ? 'playlists.create'
                          : 'playlists.save',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    name.dispose();
    description.dispose();
    if (values == null || values.$1.isEmpty) return;
    try {
      if (playlist == null && detail == null) {
        final created = await _service.create(
          name: values.$1,
          description: values.$2,
          visibility: values.$3,
        );
        if (mounted) context.push('/playlists/${created.id}');
      } else {
        final id = playlist?.id ?? detail!.id;
        final updated = await _service.update(
          id,
          name: values.$1,
          description: values.$2,
          visibility: values.$3,
        );
        if (mounted && widget.playlistId != null) {
          setState(() {
            _detail = updated;
            _canManage = _isOwner(updated.userId);
          });
        }
      }
      if (mounted && widget.playlistId == null) await _load();
    } on ApiFailure catch (error) {
      _message(AppStrings.apiError(error, fallback: 'common.error'));
    }
  }

  Future<void> _delete(PlaylistSummary playlist) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.t('playlists.deleteTitle')),
        content: Text(
          AppStrings.format('playlists.deleteDescription', {
            'name': playlist.name,
          }),
        ),
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
      _message(AppStrings.apiError(error, fallback: 'playlists.deleteError'));
    }
  }

  Future<void> _deleteDetail(PlaylistDetail detail) async {
    await _delete(
      PlaylistSummary(
        id: detail.id,
        name: detail.name,
        visibility: detail.visibility,
        itemCount: detail.items.length,
        description: detail.description,
        coverUrl: detail.coverUrl,
      ),
    );
    if (mounted && widget.playlistId != null) context.pop();
  }

  Future<void> _pickCover(PlaylistDetail detail) async {
    if (!_canManage || _busy) return;
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1800,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _busy = true);
    try {
      final updated = await _service.uploadCover(
        detail.id,
        UploadPayload(
          bytes: bytes,
          fileName: file.name,
          contentType: file.mimeType ?? 'image/jpeg',
        ),
      );
      if (mounted) {
        setState(() {
          _detail = updated;
          _canManage = _isOwner(updated.userId);
          _busy = false;
        });
        _message(AppStrings.t('playlists.coverUpdated'));
      }
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _busy = false);
      _message(AppStrings.apiError(error, fallback: 'playlists.coverError'));
    }
  }

  Future<void> _removeVideo(PlaylistItem item) async {
    final id = widget.playlistId;
    if (id == null || !_canManage || _busy) return;
    setState(() => _busy = true);
    try {
      await _service.removeVideo(id, item.videoId);
      await _load();
    } on ApiFailure catch (error) {
      _message(AppStrings.apiError(error, fallback: 'common.error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final current = _detail;
    if (current == null || !_canManage || oldIndex == newIndex) return;
    final items = [...current.items];
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    setState(
      () => _detail = PlaylistDetail(
        id: current.id,
        userId: current.userId,
        name: current.name,
        visibility: current.visibility,
        description: current.description,
        coverUrl: current.coverUrl,
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

  Future<void> _searchVideos(String query) async {
    setState(() {
      _videoSearch = query;
      _videoLoading = true;
    });
    try {
      final result = await _content.searchVideos(
        query: query,
        page: 1,
        pageSize: 30,
        sort: 'newest',
      );
      final existing = _detail?.items.map((item) => item.videoId).toSet() ?? {};
      if (mounted) {
        setState(() {
          _videoOptions = result.items
              .where((video) => !existing.contains(video.id))
              .toList();
          _videoLoading = false;
        });
      }
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _videoLoading = false);
      _message(AppStrings.apiError(error, fallback: 'playlists.searchError'));
    }
  }

  Future<void> _addVideo(VideoCard video) async {
    final id = widget.playlistId;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    try {
      final updated = await _service.addVideo(id, video.id);
      if (mounted) {
        setState(() {
          _detail = updated;
          _busy = false;
        });
        _message(AppStrings.t('common.saved'));
      }
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _busy = false);
      _message(AppStrings.apiError(error, fallback: 'playlists.addVideoError'));
    }
  }

  Future<void> _openAddVideo() async {
    _videoOptions = const [];
    _videoSearch = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, refresh) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .82,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppStrings.t('playlists.addVideoToPlaylist'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(AppStrings.t('playlists.addVideoDescription')),
                const SizedBox(height: 14),
                TextField(
                  autofocus: true,
                  onChanged: (value) {
                    refresh(() {});
                    _searchVideos(value);
                  },
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: AppStrings.t('playlists.searchVideoPlaceholder'),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _videoLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _videoOptions.isEmpty
                      ? Center(
                          child: Text(
                            _videoSearch.isEmpty
                                ? AppStrings.t(
                                    'playlists.searchVideoPlaceholder',
                                  )
                                : AppStrings.t('playlists.noMatchingVideos'),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _videoOptions.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final video = _videoOptions[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: _thumbnail(
                                video.thumbnailUrl,
                                width: 82,
                                height: 50,
                              ),
                              title: Text(
                                video.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(video.channelName),
                              trailing: IconButton(
                                tooltip: AppStrings.t('playlists.addVideo'),
                                onPressed: () async {
                                  await _addVideo(video);
                                  if (context.mounted) {
                                    Navigator.pop(sheetContext);
                                  }
                                },
                                icon: const Icon(
                                  Icons.add_circle_outline_rounded,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _play(PlaylistDetail detail, {bool shuffle = false}) {
    final playable = detail.items
        .asMap()
        .entries
        .where((entry) => entry.value.available)
        .toList();
    if (playable.isEmpty) {
      _message(AppStrings.t('playlists.noPlayableVideo'));
      return;
    }
    final entry = shuffle
        ? playable[Random().nextInt(playable.length)]
        : playable.first;
    final index = detail.items.indexOf(entry.value);
    context.push(
      '/watch/${entry.value.videoId}?playlist=${Uri.encodeComponent(detail.id)}&index=$index&shuffle=$shuffle',
    );
  }

  Future<void> _share(PlaylistDetail detail) async {
    await Share.share(
      '${detail.name}\nhutube://playlists/${detail.id}',
      subject: detail.name,
    );
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
      child: _playlists.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                HuTubeSectionHeader(
                  title: AppStrings.t('playlists.title'),
                  subtitle: AppStrings.t('playlists.subtitle'),
                  action: widget.auth.authenticated
                      ? AppStrings.t('playlists.createAction')
                      : null,
                  onAction: _edit,
                ),
                const SizedBox(height: 18),
                HuTubeStateView(
                  icon: Icons.playlist_add_rounded,
                  title: AppStrings.t('playlists.emptyTitle'),
                  message: AppStrings.t('playlists.createFirst'),
                  actionLabel: AppStrings.t('playlists.create'),
                  onAction: _edit,
                  compact: true,
                  accent: AppColors.primary,
                ),
              ],
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: .82,
              ),
              itemCount: _playlists.length,
              itemBuilder: (_, index) => _playlistCard(_playlists[index]),
            ),
    );
  }

  Widget _playlistCard(PlaylistSummary playlist) {
    final preview = _previews[playlist.id];
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push('/playlists/${playlist.id}'),
      child: Ink(
        decoration: BoxDecoration(
          color: AppColors.surfaceFor(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderFor(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _playlistCover(
                playlist.coverUrl ?? preview?.coverUrl,
                preview?.items ?? const [],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 10, 10, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${playlist.itemCount} video · ${_visibility(playlist.visibility)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'edit') _edit(playlist: playlist);
                      if (value == 'delete') _delete(playlist);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(AppStrings.t('common.edit')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(AppStrings.t('common.delete')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playlistCover(String? coverUrl, List<PlaylistItem> items) {
    if (coverUrl != null && coverUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        child: Image.network(
          coverUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _emptyCover(items),
        ),
      );
    }
    return _emptyCover(items);
  }

  Widget _emptyCover(List<PlaylistItem> items) {
    final images = items
        .where((item) => item.thumbnailUrl != null)
        .take(3)
        .toList();
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (images.isNotEmpty)
            Row(
              children: images
                  .map(
                    (item) => Expanded(
                      child: Image.network(
                        item.thumbnailUrl!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                  .toList(),
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: .9),
                    AppColors.primary.withValues(alpha: .45),
                  ],
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.playlist_play_rounded,
                  color: Colors.white,
                  size: 42,
                ),
              ),
            ),
          Positioned(
            right: 9,
            bottom: 9,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Text(
                  '${items.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
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
      Expanded(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _detailHeader(detail)),
            if (detail.items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: HuTubeStateView(
                  icon: Icons.playlist_add_rounded,
                  title: AppStrings.t('playlists.noVideosTitle'),
                  message: AppStrings.t('playlists.noVideosDescription'),
                  actionLabel: _canManage
                      ? AppStrings.t('playlists.addVideo')
                      : null,
                  onAction: _canManage ? _openAddVideo : null,
                  accent: AppColors.primary,
                ),
              )
            else
              SliverReorderableList(
                itemCount: detail.items.length,
                onReorderItem: _reorder,
                itemBuilder: (context, index) =>
                    _videoRow(detail, detail.items[index], index),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    ],
  );

  Widget _detailHeader(PlaylistDetail detail) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Expanded(
              child: Text(
                detail.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            if (_canManage)
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') _edit(detail: detail);
                  if (value == 'cover') _pickCover(detail);
                  if (value == 'delete') _deleteDetail(detail);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(AppStrings.t('common.edit')),
                  ),
                  PopupMenuItem(
                    value: 'cover',
                    child: Text(AppStrings.t('playlists.changeCover')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(AppStrings.t('common.delete')),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 190,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _playlistCover(detail.coverUrl, detail.items),
              if (_canManage)
                Positioned(
                  right: 10,
                  top: 10,
                  child: IconButton.filledTonal(
                    tooltip: AppStrings.t('playlists.changeCover'),
                    onPressed: _busy ? null : () => _pickCover(detail),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera_outlined),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          detail.description?.trim().isNotEmpty == true
              ? detail.description!
              : AppStrings.t('playlists.descriptionFallback'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        Text(
          '${detail.items.length} video · ${_visibility(detail.visibility)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: detail.items.isEmpty ? null : () => _play(detail),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(AppStrings.t('playlists.playAll')),
            ),
            OutlinedButton.icon(
              onPressed: detail.items.isEmpty
                  ? null
                  : () => _play(detail, shuffle: true),
              icon: const Icon(Icons.shuffle_rounded),
              label: Text(AppStrings.t('playlists.shuffle')),
            ),
            OutlinedButton.icon(
              onPressed: () => _share(detail),
              icon: const Icon(Icons.share_outlined),
              label: Text(AppStrings.t('playlists.share')),
            ),
            if (_canManage)
              OutlinedButton.icon(
                onPressed: _busy ? null : _openAddVideo,
                icon: const Icon(Icons.add_rounded),
                label: Text(AppStrings.t('playlists.addVideo')),
              ),
          ],
        ),
        const Divider(height: 28),
      ],
    ),
  );

  Widget _videoRow(
    PlaylistDetail detail,
    PlaylistItem item,
    int index,
  ) => ListTile(
    key: ValueKey(item.videoId),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
    leading: _thumbnail(item.thumbnailUrl, width: 88, height: 55),
    title: Text(
      item.title ?? AppStrings.t('playlists.videoUnavailable'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: item.available
        ? null
        : Text(AppStrings.t('playlists.videoCannotPlay')),
    onTap: item.available
        ? () => context.push(
            '/watch/${item.videoId}?playlist=${Uri.encodeComponent(detail.id)}&index=$index',
          )
        : null,
    trailing: _canManage
        ? PopupMenuButton<String>(
            onSelected: (choice) {
              if (choice == 'remove') _removeVideo(item);
              if (choice == 'up' && index > 0) _reorder(index, index - 1);
              if (choice == 'down' && index < detail.items.length - 1) {
                _reorder(index, index + 1);
              }
            },
            itemBuilder: (_) => [
              if (index > 0)
                PopupMenuItem(
                  value: 'up',
                  child: Text(AppStrings.t('playlists.moveUp')),
                ),
              if (index < detail.items.length - 1)
                PopupMenuItem(
                  value: 'down',
                  child: Text(AppStrings.t('playlists.moveDown')),
                ),
              PopupMenuItem(
                value: 'remove',
                child: Text(AppStrings.t('playlists.removeVideo')),
              ),
            ],
          )
        : null,
  );

  Widget _thumbnail(
    String? url, {
    required double width,
    required double height,
  }) => ClipRRect(
    borderRadius: BorderRadius.circular(9),
    child: SizedBox(
      width: width,
      height: height,
      child: url == null
          ? const ColoredBox(
              color: AppColors.ink,
              child: Icon(Icons.play_arrow_rounded, color: Colors.white),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.ink),
            ),
    ),
  );

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _visibility(String value) => switch (value.toLowerCase()) {
    'public' => AppStrings.t('playlists.visibility.public'),
    'unlisted' => AppStrings.t('playlists.visibility.unlisted'),
    _ => AppStrings.t('playlists.visibility.private'),
  };
}
