import 'package:flutter/material.dart';
import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/modal_header.dart';
import '../../core/widgets/text_entry_dialog.dart';
import 'playlist_service.dart';

Future<bool> showSavePlaylistSheet(
  BuildContext context, {
  required AuthController auth,
  required String videoId,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SavePlaylistSheet(auth: auth, videoId: videoId),
    ) ??
    false;

/// Shared by watch and video cards, with a create action even for long lists.
class SavePlaylistSheet extends StatefulWidget {
  const SavePlaylistSheet({
    super.key,
    required this.auth,
    required this.videoId,
  });
  final AuthController auth;
  final String videoId;
  @override
  State<SavePlaylistSheet> createState() => _SavePlaylistSheetState();
}

class _SavePlaylistSheetState extends State<SavePlaylistSheet> {
  late final _service = PlaylistService(widget.auth);
  late final _session = widget.auth.sessionGeneration;
  List<PlaylistSummary> _items = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool get _current =>
      mounted &&
      widget.auth.authenticated &&
      _session == widget.auth.sessionGeneration;

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
      final items = await _service.mine();
      if (_current) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (error) {
      if (_current) {
        setState(() {
          _loading = false;
          _error = error is ApiFailure
              ? AppStrings.apiError(error)
              : AppStrings.t('common.networkError');
        });
      }
    }
  }

  Future<void> _save(String? id, {bool create = false}) async {
    if (_saving || !_current) return;
    String? name;
    if (create) {
      name = await showDialog<String>(
        context: context,
        builder: (_) => TextEntryDialog(
          title: AppStrings.t('watch.createPlaylist'),
          submitLabel: AppStrings.t('common.create'),
          hint: AppStrings.t('playlists.namePlaceholder'),
          maxLength: 150,
        ),
      );
      if (!_current || name == null) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (create) {
        final playlist = await _service.create(name: name!);
        if (!_current) return;
        // Keep the new playlist selectable if adding the video fails.
        _items = [
          PlaylistSummary(
            id: playlist.id,
            name: playlist.name,
            visibility: playlist.visibility,
            itemCount: playlist.items.length,
          ),
          ..._items,
        ];
        id = playlist.id;
      }
      if (!_current) return;
      if (id == null) {
        await _service.saveVideo(widget.videoId);
      } else {
        await _service.addVideo(id, widget.videoId);
      }
      if (mounted && _current) Navigator.pop(context, true);
    } on ApiFailure catch (error) {
      if (!mounted || !_current) return;
      if (error.code == 'PLAYLIST_VIDEO_EXISTS') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.t('playlists.videoAlreadySaved'))),
        );
        Navigator.pop(context, false);
      } else {
        setState(() => _error = AppStrings.apiError(error));
      }
    } catch (_) {
      if (_current) {
        setState(() => _error = AppStrings.t('common.networkError'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            ModalHeader(
              title: AppStrings.t('watch.savePlaylist'),
              subtitle:
                  MediaQuery.sizeOf(context).height < 600 ||
                      MediaQuery.textScalerOf(context).scale(14) > 20
                  ? null
                  : AppStrings.t('playlists.chooseHint'),
              icon: Icons.playlist_add_rounded,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('save-playlist-create'),
                  onPressed: _saving ? null : () => _save(null, create: true),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(AppStrings.t('watch.createPlaylist')),
                ),
              ),
            ),
            if (_saving) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                      children: [
                        ListTile(
                          enabled: !_saving,
                          leading: const Icon(Icons.bookmark_outline_rounded),
                          title: Text(AppStrings.t('watch.savedVideo')),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _save(null),
                        ),
                        const Divider(),
                        for (final item in _items)
                          ListTile(
                            key: ValueKey('save-playlist-${item.id}'),
                            enabled: !_saving,
                            leading: Icon(
                              item.visibility == 'private'
                                  ? Icons.lock_outline_rounded
                                  : Icons.playlist_play_rounded,
                            ),
                            title: Text(
                              item.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              AppStrings.format('channel.videoCount', {
                                'count': AppStrings.number(item.itemCount),
                              }),
                            ),
                            trailing: const Icon(Icons.add_rounded),
                            onTap: () => _save(item.id),
                          ),
                        if (_items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              AppStrings.t('playlists.emptyTitle'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        if (_error != null)
                          TextButton.icon(
                            onPressed: _saving ? null : _load,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(AppStrings.t('common.retry')),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
