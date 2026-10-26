import '../../core/widgets/confirmation_dialog.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'local_download_manager.dart';
import 'offline_player_screen.dart';
import 'content_service.dart';
import 'download_actions.dart';
import 'content_models.dart';
import 'download_coordinator.dart';
import '../../core/widgets/scrollable_sheet.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, required this.auth, this.coordinator});
  final AuthController auth;
  final DownloadCoordinator? coordinator;
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  late final _downloads = _coordinator.manager;
  final Map<String, VideoCard> _metadata = {};
  late final ContentService _content = ContentService(widget.auth);
  late final _coordinator =
      widget.coordinator ?? DownloadCoordinator(widget.auth);
  List<Map<String, dynamic>> _remote = const [];
  bool _remoteLoading = true;
  int _requestGeneration = 0;
  late int _sessionGeneration;
  late bool _authenticated;
  late bool _offlineSession;
  @override
  void initState() {
    super.initState();
    _sessionGeneration = widget.auth.sessionGeneration;
    _authenticated = widget.auth.authenticated;
    _offlineSession = widget.auth.offlineSession;
    widget.auth.addListener(_identityChanged);
    _downloads.ensureLoaded();
    unawaited(
      _coordinator.initialize().then((_) {
        if (mounted) {
          unawaited(_loadRemote());
          return _coordinator.loadSuggestions();
        }
      }),
    );
  }

  void _identityChanged() {
    if (_sessionGeneration == widget.auth.sessionGeneration &&
        _authenticated == widget.auth.authenticated &&
        _offlineSession == widget.auth.offlineSession) {
      return;
    }
    _sessionGeneration = widget.auth.sessionGeneration;
    _authenticated = widget.auth.authenticated;
    _offlineSession = widget.auth.offlineSession;
    ++_requestGeneration;
    if (mounted) {
      setState(() {
        _remote = [];
        _metadata.clear();
        _remoteLoading = widget.auth.authenticated;
      });
    }
    if (widget.auth.authenticated) _loadRemote();
  }

  @override
  void dispose() {
    widget.auth.removeListener(_identityChanged);
    if (widget.coordinator == null) _coordinator.dispose();
    super.dispose();
  }

  Future<void> _downloadSuggested(VideoCard video) async {
    try {
      await _coordinator.download(
        video,
        choose: (options) => showModalBottomSheet<Rendition>(
          context: context,
          builder: (context) => ScrollableSheet(
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(title: Text(AppStrings.t('watch.downloadQuality'))),
                  for (final option in options)
                    ListTile(
                      title: Text(option.quality),
                      subtitle: Text('${option.width}×${option.height}'),
                      onTap: () => Navigator.pop(context, option),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      if (mounted) await _loadRemote();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiFailure
                  ? AppStrings.apiError(error)
                  : AppStrings.t('downloads.error'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadRemote() async {
    if (!mounted) return;
    if (!widget.auth.authenticated ||
        widget.auth.offlineSession ||
        !_coordinator.conditions.connected) {
      setState(() => _remoteLoading = false);
      return;
    }
    final request = ++_requestGeneration;
    final generation = widget.auth.sessionGeneration;
    bool current() =>
        mounted &&
        request == _requestGeneration &&
        generation == widget.auth.sessionGeneration;
    try {
      final items = await _content.downloads();
      if (current()) {
        setState(() {
          _remote = items;
          _remoteLoading = false;
        });
        unawaited(_hydrateMetadata(request, generation));
      }
    } on ApiFailure catch (error) {
      if (current()) {
        setState(() {
          _remoteLoading = false;
          if (error.status != 404) _remote = const [];
        });
      }
    } catch (_) {
      if (current()) {
        setState(() => _remoteLoading = false);
      }
    }
  }

  Future<void> _hydrateMetadata(int request, int generation) async {
    final ids = {
      ..._remote.map((item) => '${item['videoId'] ?? ''}'),
      ..._downloads.items
          .where(
            (item) => item.thumbnailUrl == null || item.channelName.isEmpty,
          )
          .map((item) => item.videoId),
    }.where((id) => id.isNotEmpty && !_metadata.containsKey(id)).toList();
    for (var offset = 0; offset < ids.length; offset += 3) {
      if (!mounted ||
          request != _requestGeneration ||
          generation != widget.auth.sessionGeneration) {
        return;
      }
      await Future.wait(
        ids.skip(offset).take(3).map((id) async {
          try {
            final video = await _content.detail(id);
            if (!mounted ||
                request != _requestGeneration ||
                generation != widget.auth.sessionGeneration) {
              return;
            }
            setState(() => _metadata[id] = video);
            for (final item in _downloads.items.where(
              (item) => item.videoId == id,
            )) {
              unawaited(
                _downloads.updateMetadata(
                  item.id,
                  thumbnailUrl: video.thumbnailUrl,
                  channelName: video.channelName,
                  duration: video.duration,
                ),
              );
            }
          } catch (_) {
            // Unavailable videos still keep their saved file and cover art.
          }
        }),
      );
    }
  }

  Future<void> _operate(Map<String, dynamic> item, String operation) async {
    final generation = widget.auth.sessionGeneration;
    final id = '${item['videoDownloadId'] ?? ''}';
    if (id.isEmpty) return;
    try {
      final updated = operation == 'download'
          ? item
          : await _content.updateDownload(id, operation);
      if (!mounted || generation != widget.auth.sessionGeneration) return;
      if (operation == 'pause') await _downloads.pause(id);
      if (operation == 'cancel') await _downloads.remove(id);
      if (operation == 'resume' ||
          operation == 'retry' ||
          operation == 'download') {
        await _downloads.enqueue(
          id: id,
          videoId: '${updated['videoId'] ?? ''}',
          title: '${updated['title'] ?? ''}',
          quality: '${updated['quality'] ?? ''}',
          url: '${updated['fileUrl'] ?? ''}',
          fileSize: asInt(updated['fileSize']),
          thumbnailUrl: _metadata['${updated['videoId']}']?.thumbnailUrl,
          channelName: _metadata['${updated['videoId']}']?.channelName ?? '',
          duration: _metadata['${updated['videoId']}']?.duration ?? 0,
        );
      }
      if (generation == widget.auth.sessionGeneration) await _loadRemote();
    } on ApiFailure catch (error) {
      if (mounted && generation == widget.auth.sessionGeneration) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
      }
    }
  }

  Future<void> _removeRemote(Map<String, dynamic> item) async {
    final generation = widget.auth.sessionGeneration;
    final id = '${item['videoDownloadId'] ?? ''}';
    if (id.isEmpty) return;
    try {
      await _content.deleteDownload(id);
      if (generation != widget.auth.sessionGeneration) return;
      await _downloads.remove(id);
      await _loadRemote();
    } on ApiFailure catch (error) {
      if (mounted && generation == widget.auth.sessionGeneration) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
      }
    }
  }

  Future<void> _deleteAllRemote() async {
    final generation = widget.auth.sessionGeneration;
    final remoteIds = _remote
        .map((item) => '${item['videoDownloadId'] ?? ''}')
        .where((id) => id.isNotEmpty)
        .toList();
    final ids = {...remoteIds, ..._downloads.items.map((item) => item.id)};
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: AppStrings.t('downloads.removeAllTitle'),
        message: AppStrings.t('downloads.removeAllDescription'),
        confirmLabel: AppStrings.t('common.delete'),
        destructive: true,
        icon: Icons.delete_outline_rounded,
      ),
    );
    if (confirmed != true || generation != widget.auth.sessionGeneration) {
      return;
    }
    try {
      if (remoteIds.isNotEmpty) await _content.deleteDownloads(remoteIds);
      for (final id in ids) {
        if (generation != widget.auth.sessionGeneration) return;
        await _downloads.remove(id);
      }
      await _loadRemote();
    } on ApiFailure catch (error) {
      if (mounted && generation == widget.auth.sessionGeneration) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_downloads, _coordinator]),
    builder: (_, _) {
      final local = _downloads.items;
      final localIds = local.map((item) => item.id).toSet();
      final remoteOnly = _remote
          .where((item) => !localIds.contains('${item['videoDownloadId']}'))
          .toList();
      final hasItems = local.isNotEmpty || remoteOnly.isNotEmpty;
      return RefreshIndicator(
        onRefresh: () async {
          await _loadRemote();
          await _coordinator.loadSuggestions();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppStrings.t('downloads.title'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (hasItems)
                  PopupMenuButton<String>(
                    tooltip: AppStrings.t('downloads.clearAll'),
                    onSelected: (_) => _deleteAllRemote(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'clear',
                        child: Text(AppStrings.t('downloads.clearAll')),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.t('downloads.subtitle'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textMutedFor(context),
              ),
            ),
            const SizedBox(height: 20),
            if (_coordinator.settingsFailed) ...[
              HuTubeNotice(
                message: AppStrings.t('prefs.loadError'),
                actionLabel: AppStrings.t('common.retry'),
                onAction: _coordinator.refreshSettings,
              ),
              const SizedBox(height: 12),
            ],
            if (_coordinator.preferences.wifiOnly) ...[
              _DownloadInfo(
                icon: Icons.wifi_rounded,
                message: AppStrings.t('downloads.wifiPolicy'),
              ),
              const SizedBox(height: 16),
            ],
            if (_remoteLoading)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (!hasItems && !_remoteLoading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: HuTubeStateView(
                  icon: Icons.offline_pin_outlined,
                  title: AppStrings.t('downloads.empty'),
                  message: AppStrings.t('downloads.description'),
                  accent: AppColors.primaryPink,
                ),
              ),
            for (final item in local) _localRow(item),
            for (final item in remoteOnly) _remoteRow(item),
            if (_coordinator.preferences.recommendations) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppStrings.t('downloads.suggestedTitle'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: AppStrings.t('common.retry'),
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _coordinator.loading
                        ? null
                        : _coordinator.loadSuggestions,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_coordinator.loading)
                const LinearProgressIndicator(minHeight: 2),
              if (_coordinator.suggestionsFailed)
                HuTubeNotice(
                  message: AppStrings.t('common.networkError'),
                  actionLabel: AppStrings.t('common.retry'),
                  onAction: _coordinator.loadSuggestions,
                ),
              if (!_coordinator.loading &&
                  !_coordinator.suggestionsFailed &&
                  _coordinator.suggestions.isEmpty)
                Text(
                  AppStrings.t('downloads.noSuggestions'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              for (final video in _coordinator.suggestions.where(
                (video) =>
                    !remoteOnly.any((item) => item['videoId'] == video.id),
              ))
                _DownloadVideoRow(
                  title: video.title,
                  thumbnailUrl: video.thumbnailUrl,
                  duration: video.duration,
                  channelName: video.channelName,
                  onTap: () => context.push('/watch/${video.id}'),
                  trailing: _coordinator.requesting.contains(video.id)
                      ? const SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : IconButton(
                          tooltip: AppStrings.t('common.download'),
                          icon: const Icon(Icons.download_rounded),
                          onPressed: () => _downloadSuggested(video),
                        ),
                ),
            ],
          ],
        ),
      );
    },
  );

  Widget _localRow(LocalDownload item) {
    final video = _metadata[item.videoId];
    return _DownloadVideoRow(
      key: ValueKey('download-${item.id}'),
      title: item.title,
      thumbnailUrl: item.thumbnailUrl ?? video?.thumbnailUrl,
      thumbnailPath: item.thumbnailPath,
      duration: item.duration > 0 ? item.duration : video?.duration ?? 0,
      channelName: item.channelName.isNotEmpty
          ? item.channelName
          : video?.channelName ?? '',
      status: [
        item.quality,
        _label(item),
      ].where((value) => value.isNotEmpty).join(' · '),
      statusColor: item.status == 'failed'
          ? Theme.of(context).colorScheme.error
          : item.completed
          ? AppColors.textMutedFor(context)
          : Theme.of(context).colorScheme.primary,
      error: item.error == null ? null : _downloadError(item.error),
      progress: item.active ? item.progress : null,
      completed: item.completed,
      onTap: item.completed
          ? () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => OfflinePlayerScreen(
                  auth: widget.auth,
                  download: item,
                  manager: _downloads,
                ),
              ),
            )
          : null,
      trailing: PopupMenuButton<String>(
        tooltip: AppStrings.t('common.moreOptions'),
        onSelected: (value) {
          if (value == 'pause') _downloads.pause(item.id);
          if (value == 'retry') _downloads.retry(item.id);
          if (value == 'delete') {
            final records = _remote.where(
              (record) => record['videoDownloadId'] == item.id,
            );
            if (records.isNotEmpty) {
              _removeRemote(records.first);
            } else {
              _downloads.remove(item.id);
            }
          }
        },
        itemBuilder: (_) => [
          if (item.active ||
              item.status == 'queued' ||
              item.status.startsWith('waiting_'))
            PopupMenuItem(
              value: 'pause',
              child: Text(AppStrings.t('downloads.pause')),
            ),
          if (!item.active && !item.completed)
            PopupMenuItem(
              value: 'retry',
              child: Text(AppStrings.t('common.retry')),
            ),
          PopupMenuItem(
            value: 'delete',
            child: Text(AppStrings.t('downloads.remove')),
          ),
        ],
      ),
    );
  }

  Widget _remoteRow(Map<String, dynamic> item) {
    final video = _metadata['${item['videoId']}'];
    return _DownloadVideoRow(
      key: ValueKey('download-${item['videoDownloadId']}'),
      title: '${item['title'] ?? AppStrings.t('downloads.videoFallback')}',
      thumbnailUrl: video?.thumbnailUrl,
      channelName: video?.channelName ?? '',
      duration: video?.duration ?? 0,
      status:
          '${item['quality'] ?? ''} · ${_remoteStatus('${item['status'] ?? ''}')}',
      statusColor: Theme.of(context).colorScheme.primary,
      trailing: PopupMenuButton<String>(
        tooltip: AppStrings.t('common.moreOptions'),
        onSelected: (choice) =>
            choice == 'delete' ? _removeRemote(item) : _operate(item, choice),
        itemBuilder: (_) => [
          for (final action in remoteDownloadActions('${item['status'] ?? ''}'))
            PopupMenuItem(
              value: action,
              child: Text(
                AppStrings.t(
                  action == 'download'
                      ? 'common.download'
                      : action == 'delete'
                      ? 'downloads.remove'
                      : 'downloads.$action',
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _label(LocalDownload item) => switch (item.status) {
    'queued' => AppStrings.t('downloads.queued'),
    'downloading' => AppStrings.format('downloads.downloading', {
      'percent': AppStrings.number((item.progress * 100).round()),
    }),
    'completed' => AppStrings.t('downloads.savedOffline'),
    'paused' => AppStrings.t('downloads.paused'),
    'waiting_wifi' => AppStrings.t('downloads.waitingWifi'),
    'waiting_network' => AppStrings.t('downloads.waitingNetwork'),
    _ => AppStrings.t('downloads.failed'),
  };

  String _downloadError(String? error) {
    if (error == null || error.isEmpty) return AppStrings.t('downloads.error');
    const serverPrefix = 'downloads.serverError:';
    if (error.startsWith(serverPrefix)) {
      return AppStrings.format('downloads.serverError', {
        'status': error.substring(serverPrefix.length),
      });
    }
    final translated = AppStrings.t(error);
    return translated == error ? AppStrings.t('downloads.error') : translated;
  }

  String _remoteStatus(String status) => switch (status.toLowerCase()) {
    'queued' || 'pending' => AppStrings.t('downloads.status.waiting'),
    'downloading' ||
    'in_progress' ||
    'processing' => AppStrings.t('downloads.status.loading'),
    'ready' => AppStrings.t('downloads.status.ready'),
    'revoked' => AppStrings.t('downloads.status.revoked'),
    'paused' => AppStrings.t('downloads.status.paused'),
    'completed' || 'complete' => AppStrings.t('downloads.status.complete'),
    'failed' || 'error' => AppStrings.t('downloads.status.failed'),
    'cancelled' ||
    'canceled' ||
    'canceled_by_user' => AppStrings.t('downloads.status.cancelled'),
    _ => status.isEmpty ? AppStrings.t('downloads.status.processing') : status,
  };
}

class _DownloadInfo extends StatelessWidget {
  const _DownloadInfo({required this.icon, required this.message});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => HuTubeSurface(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ),
      ],
    ),
  );
}

class _DownloadVideoRow extends StatelessWidget {
  const _DownloadVideoRow({
    super.key,
    required this.title,
    required this.trailing,
    this.thumbnailUrl,
    this.thumbnailPath,
    this.channelName = '',
    this.duration = 0,
    this.status,
    this.statusColor,
    this.error,
    this.progress,
    this.completed = false,
    this.onTap,
  });
  final String title, channelName;
  final String? thumbnailUrl, thumbnailPath, status, error;
  final int duration;
  final double? progress;
  final Color? statusColor;
  final bool completed;
  final Widget trailing;
  final VoidCallback? onTap;

  String get _duration {
    final hours = duration ~/ 3600;
    final minutes = (duration ~/ 60 % 60).toString().padLeft(
      hours > 0 ? 2 : 1,
      '0',
    );
    final seconds = (duration % 60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.textMutedFor(context);
    Widget fallback() => ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.play_circle_outline_rounded, size: 30, color: muted),
      ),
    );
    Widget cover() {
      if (thumbnailPath != null && File(thumbnailPath!).existsSync()) {
        return Image.file(
          File(thumbnailPath!),
          fit: BoxFit.cover,
          cacheWidth: 480,
          errorBuilder: (_, _, _) => fallback(),
        );
      }
      if (thumbnailUrl?.isNotEmpty == true) {
        return Image.network(
          thumbnailUrl!,
          fit: BoxFit.cover,
          cacheWidth: 480,
          errorBuilder: (_, _, _) => fallback(),
        );
      }
      return fallback();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: LayoutBuilder(
        builder: (context, bounds) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: title,
              button: onTap != null,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: (bounds.maxWidth * .39).clamp(96.0, 200.0),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          cover(),
                          if (duration > 0)
                            Positioned(
                              right: 5,
                              bottom: progress == null ? 5 : 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .78),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    _duration,
                                    textScaler: TextScaler.noScaling,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (progress != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 3,
                                color: AppColors.primaryPink,
                                backgroundColor: Colors.black38,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    if (channelName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        channelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                    if (status != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (completed) ...[
                            Icon(
                              Icons.offline_pin_rounded,
                              size: 14,
                              color: muted,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              status!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: statusColor, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        error!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(width: 48, height: 48, child: trailing),
          ],
        ),
      ),
    );
  }
}
