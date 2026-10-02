import 'dart:async';
import 'dart:io';

import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/storage/app_preferences.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../../channel/services/channel_service.dart';
import '../playlists/playlist_service.dart';
import 'content_models.dart';
import 'content_service.dart';
import 'local_download_manager.dart';
import 'media_entitlements.dart';
import 'playback_session.dart';
import 'video_card.dart';
import 'widgets/playlist_queue_sheet.dart';
import '../moderation/report_dialog.dart';

class WatchScreen extends StatefulWidget {
  const WatchScreen({
    super.key,
    required this.auth,
    required this.playback,
    required this.videoId,
  });
  final AuthController auth;
  final PlaybackSession playback;
  final String videoId;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> with WidgetsBindingObserver {
  late final ContentService _content;
  final _comment = TextEditingController();
  final _prefs = const AppPreferencesStore();
  VideoDetail? _video;
  List<Rendition> _renditions = const [];
  MediaEntitlements _entitlements = const MediaEntitlements.none();
  List<CommentItem> _comments = [];
  List<VideoCard> _related = [];
  bool _loading = true;
  bool _sendingComment = false;
  bool _isOwner = false;
  bool _isFullScreen = false;
  bool _zoomToFill = false;
  bool _pipEnabled = false;
  String _commentSort = 'top';
  String? _pinnedCommentId;
  final Set<String> _heartedCommentIds = <String>{};
  String? _error;
  String? _actionMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _content = ContentService(widget.auth);
    widget.playback.onVideoCompleted = _handleVideoCompleted;
    _prefs.readZoomToFill().then((v) {
      if (mounted) setState(() => _zoomToFill = v);
    });
    _prefs.readPipEnabled().then((v) {
      if (mounted) setState(() => _pipEnabled = v);
    });
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isFullScreen) {
      FullscreenManager.exitFullscreen();
    }
    _comment.dispose();
    if (widget.playback.onVideoCompleted == _handleVideoCompleted) {
      widget.playback.onVideoCompleted = null;
    }
    if (widget.playback.videoId == widget.videoId && widget.playback.ready) {
      widget.playback.minimize();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if ((state == AppLifecycleState.inactive || state == AppLifecycleState.paused) &&
        _pipEnabled &&
        widget.playback.isPlaying &&
        widget.playback.ready) {
      _enterPictureInPicture();
    }
  }

  Future<void> _toggleFullScreen() async {
    if (!_isFullScreen) {
      await FullscreenManager.enterFullscreen(lockToLandscape: true);
      if (mounted) setState(() => _isFullScreen = true);
    } else {
      await FullscreenManager.exitFullscreen();
      if (mounted) setState(() => _isFullScreen = false);
    }
  }

  @override
  void didUpdateWidget(covariant WatchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _content.detail(widget.videoId);
      final playback = await _content.playback(widget.videoId);
      final entitlements = await MediaEntitlements.load(widget.auth);
      final comments = await _content.comments(widget.videoId);
      final related = await _content.feed(
        explore: false,
        pageSize: 12,
        sort: 'popular',
      );
      bool isOwner = false;
      if (widget.auth.authenticated) {
        try {
          final myChannel = await ChannelService(widget.auth).getMyChannel();
          if (myChannel != null &&
              (myChannel.id == detail.channelId ||
                  myChannel.handle == detail.channelHandle ||
                  widget.auth.user?['userId'] == detail.channelId)) {
            isOwner = true;
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _video = detail;
        _isOwner = isOwner;
        _renditions = [...playback.renditions]
          ..sort((a, b) => a.height.compareTo(b.height));
        _entitlements = entitlements;
        _comments = comments.items;
        _related = related.items
            .where((item) => item.id != detail.id)
            .take(8)
            .toList();
        _loading = false;
      });

      if (widget.playback.queue.isEmpty) {
        final currentCard = VideoCard(
          id: detail.id,
          channelId: detail.channelId,
          channelName: detail.channelName,
          channelHandle: detail.channelHandle,
          title: detail.title,
          thumbnailUrl: detail.thumbnailUrl,
          duration: detail.duration,
          visibility: detail.visibility,
          publishedAt: detail.publishedAt,
          views: detail.views,
        );
        widget.playback.setQueue([currentCard, ..._related], initialIndex: 0);
      }
      final resumeAt = playback.resumeAt > 0
          ? playback.resumeAt
          : detail.viewerState.resumeAt;
      final source = _renditions.isNotEmpty
          ? _renditions.last.url
          : detail.videoUrl;
      if (widget.playback.videoId == widget.videoId && widget.playback.ready) {
        widget.playback.restore();
      } else {
        await widget.playback.start(
          auth: widget.auth,
          video: detail,
          videoRenditions: _renditions,
          mediaEntitlements: entitlements,
          sourceUrl: source,
          resumeAt: resumeAt,
        );
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(
            widget.playback.initialize(source, resumeAt: resumeAt).catchError((
              _,
            ) {
              if (mounted) {
                setState(
                  () => _actionMessage = AppStrings.t('watch.playerError'),
                );
              }
            }),
          );
        });
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = AppStrings.apiError(error, fallback: 'watch.loadError');
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppStrings.t('watch.loadError');
          _loading = false;
        });
      }
    }
  }

  void _handleVideoCompleted() {
    if (!mounted) return;
    final next = widget.playback.nextVideoCard;
    if (next != null && next.id != widget.videoId) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.format('watch.autoPlayingNext', {'seconds': '2'}),
          ),
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: AppStrings.t('common.cancel'),
            onPressed: () {
              widget.playback.toggleAutoplay();
            },
          ),
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && widget.playback.autoplayNext) {
          context.pushReplacement('/watch/${next.id}');
        }
      });
    }
  }

  void _openQueueSheet() {
    HapticFeedback.lightImpact();
    PlaylistQueueSheet.show(
      context,
      playback: widget.playback,
      onSelectVideo: (video) {
        if (video.id != widget.videoId) {
          context.pushReplacement('/watch/${video.id}');
        }
      },
    );
  }

  Future<void> _enterPictureInPicture() async {
    final player = widget.playback.player;
    if (player == null || !widget.playback.ready) return;
    // Android only permits PiP from fullscreen. The native player tracks that
    // state before opening the system fullscreen surface, so this can remain a
    // single user action on both platforms.
    if (Platform.isAndroid && !player.isFullScreen) {
      await player.enterFullScreen();
    }
    final started = await player.enterPictureInPicture();
    if (!mounted) return;
    if (!started) {
      setState(() => _actionMessage = AppStrings.t('watch.pipUnsupported'));
    }
  }

  Future<bool> _requireAuth({required String action}) async {
    if (widget.auth.authenticated) return true;
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Icon(
                Icons.account_circle_outlined,
                size: 52,
                color: AppColors.primaryPink,
              ),
              const SizedBox(height: 14),
              Text(
                'Bạn muốn $action?',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Đăng nhập để tương tác với video, đăng ký kênh và lưu nội dung yêu thích của bạn.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Để sau'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primaryPink),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Đăng nhập'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (proceed == true && mounted) {
      context.push('/auth');
    }
    return false;
  }

  Future<void> _react(String type) async {
    HapticFeedback.lightImpact();
    if (!await _requireAuth(action: 'bày tỏ cảm xúc')) return;
    final video = _video;
    if (video == null) return;
    try {
      final result = await _content.react(
        video.id,
        video.viewerState.reaction == type ? null : type,
      );
      if (!mounted) return;
      setState(() {
        _video = VideoDetail(
          id: video.id,
          channelId: video.channelId,
          channelName: video.channelName,
          channelHandle: video.channelHandle,
          title: video.title,
          thumbnailUrl: video.thumbnailUrl,
          duration: video.duration,
          visibility: video.visibility,
          publishedAt: video.publishedAt,
          views: video.views,
          description: video.description,
          videoUrl: video.videoUrl,
          tags: video.tags,
          chapters: video.chapters,
          stats: VideoStats(
            views: video.stats.views,
            likes: asInt(result['likes']),
            dislikes: asInt(result['dislikes']),
            comments: video.stats.comments,
            averageRating: video.stats.averageRating,
            ratingCount: video.stats.ratingCount,
          ),
          viewerState: ViewerState(
            reaction: result['myReaction'] as String?,
            rating: video.viewerState.rating,
            resumeAt: video.viewerState.resumeAt,
          ),
          moderationStatus: video.moderationStatus,
          processingStatus: video.processingStatus,
        );
      });
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() => _actionMessage = AppStrings.apiError(error));
      }
    }
  }

  Future<void> _rate() async {
    HapticFeedback.lightImpact();
    if (!await _requireAuth(action: 'đánh giá video này')) return;
    if (!mounted) return;
    final currentRating = _video?.viewerState.rating;
    final score = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        int selected = currentRating ?? 0;
        return StatefulBuilder(
          builder: (ctx, setSheetState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    AppStrings.t('watch.ratingTitle'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    selected > 0 ? '$selected / 5 sao' : 'Chạm vào sao để đánh giá',
                    style: TextStyle(
                      fontSize: 14,
                      color: selected > 0 ? Colors.amber.shade700 : AppColors.textMuted,
                      fontWeight: selected > 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 1; i <= 5; i++)
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setSheetState(() => selected = i);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(
                              i <= selected ? Icons.star_rounded : Icons.star_outline_rounded,
                              size: 42,
                              color: i <= selected ? Colors.amber.shade600 : Colors.grey.shade400,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (currentRating != null) ...[
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, 0),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                          child: const Text('Xóa đánh giá'),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryPink),
                          onPressed: selected > 0 ? () => Navigator.pop(ctx, selected) : null,
                          child: const Text('Gửi đánh giá'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (score == null || _video == null) return;
    try {
      final result = await _content.rate(widget.videoId, score == 0 ? null : score);
      final old = _video!;
      if (!mounted) return;
      setState(() {
        _video = VideoDetail(
          id: old.id,
          channelId: old.channelId,
          channelName: old.channelName,
          channelHandle: old.channelHandle,
          title: old.title,
          thumbnailUrl: old.thumbnailUrl,
          duration: old.duration,
          visibility: old.visibility,
          publishedAt: old.publishedAt,
          views: old.views,
          description: old.description,
          videoUrl: old.videoUrl,
          tags: old.tags,
          chapters: old.chapters,
          stats: VideoStats(
            views: old.stats.views,
            likes: old.stats.likes,
            dislikes: old.stats.dislikes,
            comments: old.stats.comments,
            averageRating: (result['average'] as num?)?.toDouble(),
            ratingCount: asInt(result['count']),
          ),
          viewerState: ViewerState(
            reaction: old.viewerState.reaction,
            rating: result['myRating'] as int?,
            resumeAt: old.viewerState.resumeAt,
          ),
          moderationStatus: old.moderationStatus,
          processingStatus: old.processingStatus,
        );
        _actionMessage = score == 0
            ? 'Đã xóa đánh giá của bạn'
            : AppStrings.t('watch.ratingSaved');
      });
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() => _actionMessage = AppStrings.apiError(error));
      }
    }
  }

  String _formatDuration(Duration value) {
    final seconds = value.inSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final rest = seconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
    }
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  Future<void> _share() async {
    HapticFeedback.lightImpact();
    final video = _video;
    if (video == null) return;
    if (widget.auth.authenticated) unawaited(_content.share(video.id));
    final currentPos = widget.playback.position.inSeconds;
    if (currentPos > 5) {
      final withTimestamp = await showModalBottomSheet<bool>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Chia sẻ: ${video.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.timer_outlined, color: AppColors.primaryPink),
                  title: Text('Bắt đầu tại ${_formatDuration(widget.playback.position)}'),
                  subtitle: const Text('Người xem sẽ mở video ngay tại mốc thời gian này'),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  onTap: () => Navigator.pop(ctx, true),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.play_circle_outline_rounded),
                  title: const Text('Bắt đầu từ đầu video'),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  onTap: () => Navigator.pop(ctx, false),
                ),
              ],
            ),
          ),
        ),
      );
      if (withTimestamp == null) return;
      final url = withTimestamp
          ? 'https://hutube.app/watch/${video.id}?t=$currentPos'
          : 'https://hutube.app/watch/${video.id}';
      await Share.share(
        'Xem "${video.title}" trên HuTube:\n$url',
      );
    } else {
      await Share.share(
        AppStrings.format('watch.shareText', {
          'title': video.title,
          'id': video.id,
        }),
      );
    }
  }

  Future<void> _download() async {
    if (!await _requireAuth(action: 'tải xuống video này')) return;
    try {
      final options = await _content.downloadOptions(widget.videoId);
      if (!mounted) return;
      final chosen = await showModalBottomSheet<Rendition>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text(AppStrings.t('watch.downloadQuality'))),
              for (final item in options)
                ListTile(
                  title: Text(item.quality),
                  subtitle: Text('${item.width}×${item.height}'),
                  onTap: () => Navigator.pop(context, item),
                ),
            ],
          ),
        ),
      );
      if (chosen == null) return;
      final record = await _content.createDownload(
        widget.videoId,
        chosen.quality,
      );
      await LocalDownloadManager.instance.enqueue(
        id: '${record['videoDownloadId'] ?? ''}',
        videoId: widget.videoId,
        title:
            '${record['title'] ?? _video?.title ?? AppStrings.t('common.download')}',
        quality: '${record['quality'] ?? chosen.quality}',
        url: '${record['fileUrl'] ?? chosen.url}',
        fileSize: asInt(record['fileSize']),
      );
      if (mounted) {
        setState(() => _actionMessage = AppStrings.t('watch.downloadAdded'));
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() => _actionMessage = AppStrings.apiError(error));
      }
    }
  }

  Future<void> _saveToPlaylist() async {
    HapticFeedback.lightImpact();
    if (!await _requireAuth(action: 'lưu video vào danh sách phát')) return;
    try {
      final service = PlaylistService(widget.auth);
      final playlists = await service.mine();
      if (!mounted) return;
      final selected = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(
                  AppStrings.t('watch.saveVideo'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              ListTile(
                leading: AppIcons.asset(AppIcons.bookmark, size: 22),
                title: Text(AppStrings.t('watch.savedVideo')),
                onTap: () => Navigator.pop(context, '__saved__'),
              ),
              for (final playlist in playlists)
                ListTile(
                  leading: AppIcons.asset(AppIcons.playlist, size: 22),
                  title: Text(playlist.name),
                  subtitle: Text(
                    AppStrings.format('channel.videoCount', {
                      'count': AppStrings.number(playlist.itemCount),
                    }),
                  ),
                  onTap: () => Navigator.pop(context, playlist.id),
                ),
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: Text(AppStrings.t('watch.createPlaylist')),
                onTap: () async {
                  Navigator.pop(context);
                  final nameController = TextEditingController();
                  final created = await showDialog<String>(
                    context: context,
                    builder: (dialogCtx) => AlertDialog(
                      title: Text(AppStrings.t('watch.createPlaylist')),
                      content: TextField(
                        controller: nameController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: AppStrings.t('playlists.namePlaceholder'),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          child: Text(AppStrings.t('common.cancel')),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(
                            dialogCtx,
                            nameController.text.trim(),
                          ),
                          child: Text(AppStrings.t('common.create')),
                        ),
                      ],
                    ),
                  );
                  nameController.dispose();
                  if (created != null && created.isNotEmpty) {
                    try {
                      final newPlaylist = await service.create(name: created);
                      await service.addVideo(newPlaylist.id, widget.videoId);
                      if (mounted) {
                        setState(() => _actionMessage = AppStrings.t('watch.savedToPlaylist'));
                      }
                    } on ApiFailure catch (e) {
                      if (mounted) {
                        setState(() => _actionMessage = AppStrings.apiError(e));
                      }
                    }
                  }
                },
              ),
            ],
          ),
        ),
      );
      if (selected == null) return;
      if (selected == '__saved__') {
        await service.saveVideo(widget.videoId);
      } else {
        await service.addVideo(selected, widget.videoId);
      }
      if (mounted) {
        setState(() => _actionMessage = AppStrings.t('watch.savedToPlaylist'));
      }
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _actionMessage = AppStrings.apiError(error));
    }
  }

  Future<void> _showPlaybackSettings() async {
    final player = widget.playback.player;
    if (player == null || !widget.playback.ready) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                AppStrings.t('watch.quality'),
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(AppStrings.t('watch.chooseResolution')),
            ),
            if (_renditions.isEmpty)
              ListTile(title: Text(AppStrings.t('watch.originalQuality')))
            else
              for (final rendition in _renditions)
                ListTile(
                  title: Text(rendition.quality),
                  subtitle: Text('${rendition.width} × ${rendition.height}'),
                  trailing:
                      widget.playback.selectedRendition?.url == rendition.url
                      ? const Icon(
                          Icons.check_rounded,
                          color: AppColors.primary,
                        )
                      : null,
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      await widget.playback.changeQuality(rendition);
                    } on Object catch (_) {
                      if (mounted) {
                        setState(
                          () => _actionMessage = AppStrings.t(
                            'watch.playerError',
                          ),
                        );
                      }
                    }
                  },
                ),
            const Divider(),
            ListTile(
              title: Text(
                AppStrings.t('watch.playbackSpeed'),
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(AppStrings.t('watch.changePlaybackSpeed')),
            ),
            for (final speed in const [
              0.25,
              0.5,
              0.75,
              1.0,
              1.25,
              1.5,
              1.75,
              2.0,
            ])
              ListTile(
                title: Text(speed == 1 ? AppStrings.t('watch.normalSpeed') : '$speed×'),
                trailing: (player.speed - speed).abs() < .01
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  unawaited(widget.playback.setSpeed(speed));
                },
              ),
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.aspect_ratio_rounded),
              title: const Text('Thu phóng vừa màn hình', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Phóng to để che hết màn hình trong chế độ toàn màn hình'),
              value: _zoomToFill,
              onChanged: (val) {
                setState(() => _zoomToFill = val);
                _prefs.writeZoomToFill(val);
                Navigator.pop(context);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.picture_in_picture_alt_rounded),
              title: const Text('Hình trong hình (PiP)', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Tự động thu nhỏ khi thoát ra màn hình chính'),
              value: _pipEnabled,
              onChanged: (val) {
                setState(() => _pipEnabled = val);
                _prefs.writePipEnabled(val);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty || _sendingComment) return;
    if (!await _requireAuth(action: 'bình luận về video này')) return;
    HapticFeedback.lightImpact();
    setState(() => _sendingComment = true);
    try {
      final comment = await _content.createComment(widget.videoId, text);
      if (mounted) {
        setState(() {
          _comments = [comment, ..._comments];
          _comment.clear();
          _sendingComment = false;
        });
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() {
          _actionMessage = AppStrings.apiError(error);
          _sendingComment = false;
        });
      }
    }
  }

  void _togglePinComment(CommentItem item) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_pinnedCommentId == item.id || item.isPinned) {
        _pinnedCommentId = null;
        _comments = _comments
            .map((c) => c.id == item.id ? c.copyWith(isPinned: false) : c)
            .toList();
      } else {
        _pinnedCommentId = item.id;
        _comments = _comments
            .map((c) => c.copyWith(isPinned: c.id == item.id))
            .toList();
      }
    });
  }

  void _toggleHeartComment(CommentItem item) {
    HapticFeedback.lightImpact();
    setState(() {
      final isHearted =
          _heartedCommentIds.contains(item.id) || item.hasCreatorHeart;
      if (isHearted) {
        _heartedCommentIds.remove(item.id);
        _comments = _comments
            .map((c) => c.id == item.id ? c.copyWith(hasCreatorHeart: false) : c)
            .toList();
      } else {
        _heartedCommentIds.add(item.id);
        _comments = _comments
            .map((c) => c.id == item.id ? c.copyWith(hasCreatorHeart: true) : c)
            .toList();
      }
    });
  }

  Future<void> _toggleHideComment(CommentItem item) async {
    HapticFeedback.lightImpact();
    final isHidden = item.status == 'hidden';
    try {
      final updated = await _content.setCommentVisibility(item.id, !isHidden);
      if (mounted) {
        setState(() {
          _comments = _comments
              .map((c) => c.id == item.id ? updated : c)
              .toList();
        });
      }
    } on ApiFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.apiError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
        children: const [
          _WatchSkeletonPlayer(),
          Padding(padding: EdgeInsets.all(20), child: _WatchSkeletonCopy()),
        ],
      );
    }
    if (_error != null || _video == null) {
      return HuTubeStateView(
        icon: Icons.play_disabled_rounded,
        title: _error ?? AppStrings.t('watch.videoUnavailable'),
        message: AppStrings.t('watch.sourceUnavailable'),
        actionLabel: AppStrings.t('common.retry'),
        onAction: _load,
      );
    }
    final video = _video!;
    final videoStageWidget = _CustomVideoStage(
      session: widget.playback,
      isFullScreen: _isFullScreen,
      zoomToFill: _zoomToFill,
      onToggleFullScreen: _toggleFullScreen,
      onToggleZoom: () {
        final newVal = !_zoomToFill;
        setState(() => _zoomToFill = newVal);
        _prefs.writeZoomToFill(newVal);
      },
      onMinimize: () {
        if (_isFullScreen) {
          _toggleFullScreen();
          return;
        }
        widget.playback.minimize();
        Navigator.of(context).maybePop();
      },
      onSettings: _showPlaybackSettings,
      onPictureInPicture: _enterPictureInPicture,
      showPictureInPicture: _entitlements.pictureInPicture,
    );

    if (_isFullScreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _toggleFullScreen();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.expand(
            child: AnimatedBuilder(
              animation: widget.playback,
              builder: (context, _) => widget.playback.player != null
                  ? videoStageWidget
                  : const Center(
                      child: CircularProgressIndicator(color: AppColors.primaryPink),
                    ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (widget.playback.videoId == widget.videoId && widget.playback.ready) {
          widget.playback.minimize();
        }
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(16),
          ),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: AnimatedBuilder(
              animation: widget.playback,
              builder: (context, _) => widget.playback.player != null
                  ? videoStageWidget
                  : const DecoratedBox(
                      decoration: BoxDecoration(color: Color(0xff171927)),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primaryPink,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Text(
            video.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -.45,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 7, 20, 0),
          child: Text(
            AppStrings.format('watch.viewsAndChannel', {
              'views': AppStrings.number(video.stats.views),
              'channel': video.channelName,
            }),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              _ActionChip(
                icon: Icons.thumb_up_outlined,
                label: AppStrings.number(video.stats.likes),
                active: video.viewerState.reaction == 'like',
                onTap: () => _react('like'),
              ),
              _ActionChip(
                icon: Icons.thumb_down_outlined,
                label: AppStrings.number(video.stats.dislikes),
                active: video.viewerState.reaction == 'dislike',
                onTap: () => _react('dislike'),
              ),
              _ActionChip(
                customIcon: AppIcons.asset(AppIcons.star, size: 18),
                label: video.viewerState.rating != null
                    ? '${video.viewerState.rating} ★'
                    : AppStrings.t('watch.rateAction'),
                active: video.viewerState.rating != null,
                onTap: _rate,
              ),
              _ActionChip(
                customIcon: AppIcons.asset(AppIcons.share, size: 18),
                label: AppStrings.t('watch.shareAction'),
                onTap: _share,
              ),
              _ActionChip(
                customIcon: AppIcons.asset(AppIcons.download, size: 18),
                label: AppStrings.t('watch.downloadAction'),
                onTap: _download,
              ),
              _ActionChip(
                customIcon: AppIcons.asset(AppIcons.playlist, size: 18),
                label: AppStrings.t('watch.savePlaylist'),
                onTap: _saveToPlaylist,
              ),
              _ActionChip(
                customIcon: AppIcons.asset(AppIcons.queue, size: 18),
                label: AppStrings.t('watch.queue'),
                active: widget.playback.queue.isNotEmpty,
                onTap: _openQueueSheet,
              ),
              _ActionChip(
                customIcon: AppIcons.asset(AppIcons.report, size: 18),
                label: AppStrings.t('watch.report'),
                onTap: () => showContentReportDialog(
                  context,
                  auth: widget.auth,
                  targetType: 'video',
                  targetId: video.id,
                ),
              ),
              if (_entitlements.pictureInPicture)
                _ActionChip(
                  icon: Icons.picture_in_picture_alt_outlined,
                  label: AppStrings.t('watch.pipAction'),
                  onTap: _enterPictureInPicture,
                ),
              if (_entitlements.backgroundPlayback)
                Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Chip(
                    avatar: Icon(Icons.headphones_outlined, size: 18),
                    label: Text(AppStrings.t('watch.background')),
                  ),
                ),
            ],
          ),
        ),
        if (_actionMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              _actionMessage!,
              style: const TextStyle(color: AppColors.primaryPink),
            ),
          ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _ChannelSummary(video: video, auth: widget.auth),
        ),
        if ((video.description ?? '').isNotEmpty || video.tags.isNotEmpty) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: HuTubeSurface(
              color: AppColors.surfaceAltFor(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((video.description ?? '').isNotEmpty)
                    Text(
                      video.description!,
                      style: const TextStyle(height: 1.5),
                    ),
                  if (video.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Wrap(
                        spacing: 6,
                        children: video.tags
                            .map((tag) => Chip(label: Text('#$tag')))
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (video.chapters.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            AppStrings.t('watch.chapters'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          ...video.chapters.map(
            (chapter) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.play_circle_outline_rounded),
              title: Text(chapter.title),
              subtitle: Text(
                '${chapter.startSeconds ~/ 60}:${(chapter.startSeconds % 60).toString().padLeft(2, '0')}',
              ),
              onTap: () => widget.playback.seekTo(
                Duration(seconds: chapter.startSeconds),
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: HuTubeSectionHeader(
                  title: AppStrings.format('watch.comments', {
                    'count': AppStrings.number(video.stats.comments),
                  }),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Sắp xếp bình luận',
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort_rounded, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        _commentSort == 'top' ? 'Hàng đầu' : 'Mới nhất',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                onSelected: (val) {
                  setState(() => _commentSort = val);
                },
                itemBuilder: (ctx) => const [
                  PopupMenuItem(
                    value: 'top',
                    child: Text('Bình luận hàng đầu'),
                  ),
                  PopupMenuItem(
                    value: 'newest',
                    child: Text('Mới nhất trước'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: InkWell(
            onTap: widget.auth.authenticated
                ? null
                : () => _requireAuth(action: 'bình luận về video này'),
            borderRadius: BorderRadius.circular(12),
            child: IgnorePointer(
              ignoring: !widget.auth.authenticated,
              child: TextField(
                controller: _comment,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: widget.auth.authenticated
                      ? AppStrings.t('watch.commentHint')
                      : 'Đăng nhập để thêm bình luận...',
                  suffixIcon: IconButton(
                    onPressed: _sendingComment ? null : _sendComment,
                    icon: AppIcons.asset(
                      AppIcons.send,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...() {
          final pinned = _comments
              .where((c) => c.id == _pinnedCommentId || c.isPinned)
              .firstOrNull;
          final others = _comments.where((c) => c.id != pinned?.id).toList();
          if (_commentSort == 'top') {
            others.sort((a, b) => (b.likes - b.dislikes).compareTo(a.likes - a.dislikes));
          } else {
            others.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
          }
          final list = [?pinned, ...others];
          return list.map(
            (item) => _CommentTile(
              item: item,
              content: _content,
              signedIn: widget.auth.authenticated,
              auth: widget.auth,
              channelName: video.channelName,
              isOwner: _isOwner,
              isPinned: item.id == _pinnedCommentId || item.isPinned,
              isHearted: _heartedCommentIds.contains(item.id) ||
                  item.hasCreatorHeart,
              onTogglePin: () => _togglePinComment(item),
              onToggleHeart: () => _toggleHeartComment(item),
              onToggleHide: () => _toggleHideComment(item),
            ),
          );
        }(),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: HuTubeSectionHeader(title: AppStrings.t('watch.related')),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: _related
                .map((item) => VideoCardTile(video: item, replaceRoute: true))
                .toList(),
          ),
        ),
      ],
    ),
  );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    this.icon,
    this.customIcon,
    required this.label,
    required this.onTap,
    this.active = false,
  });
  final IconData? icon;
  final Widget? customIcon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ActionChip(
      avatar: customIcon ??
          (icon != null
              ? Icon(
                  icon,
                  size: 18,
                  color: active ? AppColors.primaryPink : null,
                )
              : null),
      label: Text(label),
      onPressed: onTap,
    ),
  );
}

class _CustomVideoStage extends StatefulWidget {
  const _CustomVideoStage({
    required this.session,
    required this.onMinimize,
    required this.onSettings,
    required this.onPictureInPicture,
    required this.showPictureInPicture,
    this.isFullScreen = false,
    this.zoomToFill = false,
    this.onToggleFullScreen,
    this.onToggleZoom,
  });

  final PlaybackSession session;
  final VoidCallback onMinimize;
  final VoidCallback onSettings;
  final VoidCallback onPictureInPicture;
  final bool showPictureInPicture;
  final bool isFullScreen;
  final bool zoomToFill;
  final VoidCallback? onToggleFullScreen;
  final VoidCallback? onToggleZoom;

  @override
  State<_CustomVideoStage> createState() => _CustomVideoStageState();
}

class _CustomVideoStageState extends State<_CustomVideoStage> {
  bool _controlsVisible = true;
  bool? _seekForward;
  int _seekStep = 10;
  int _accumulatedSeekSeconds = 0;
  Timer? _controlsTimer;
  Timer? _pulseTimer;
  Timer? _singleTapTimer;
  DateTime? _lastTapTime;
  bool? _lastTapForward;

  @override
  void initState() {
    super.initState();
    _loadSeekStep();
    _scheduleHide();
  }

  Future<void> _loadSeekStep() async {
    try {
      final step = await const AppPreferencesStore().readDoubleTapSeek();
      if (mounted) setState(() => _seekStep = step);
    } catch (_) {}
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _pulseTimer?.cancel();
    _singleTapTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _controlsTimer?.cancel();
    if (!widget.session.isPlaying) return;
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _handleSideTap(bool forward) {
    final now = DateTime.now();
    final isSameSide = _lastTapForward == forward;
    final isQuickConsecutiveTap = isSameSide &&
        _lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds <
            (_seekForward != null ? 650 : 280);

    _lastTapTime = now;
    _lastTapForward = forward;

    if (isQuickConsecutiveTap || _seekForward == forward) {
      _singleTapTimer?.cancel();
      _singleTapTimer = null;

      _accumulatedSeekSeconds += _seekStep;
      unawaited(widget.session.seekBy(forward ? _seekStep : -_seekStep));

      setState(() {
        _seekForward = forward;
        _controlsVisible = false;
      });

      _pulseTimer?.cancel();
      _pulseTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() {
            _seekForward = null;
            _accumulatedSeekSeconds = 0;
            _lastTapTime = null;
            _lastTapForward = null;
          });
        }
      });
    } else {
      _singleTapTimer?.cancel();
      _singleTapTimer = Timer(const Duration(milliseconds: 280), () {
        if (mounted && _seekForward == null) {
          _lastTapTime = null;
          _lastTapForward = null;
          _toggleControls();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.session,
    builder: (context, _) {
      final player = widget.session.player;
      if (player == null) return const ColoredBox(color: AppColors.ink);
      final total = widget.session.duration.inMilliseconds;
      final current = widget.session.position.inMilliseconds
          .clamp(0, total > 0 ? total : 1)
          .toDouble();
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: (widget.isFullScreen && widget.zoomToFill)
                    ? BoxFit.cover
                    : BoxFit.contain,
                child: SizedBox(
                  width: 16,
                  height: 9,
                  child: NativeVideoPlayer(controller: player),
                ),
              ),
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _handleSideTap(false),
                        onVerticalDragEnd: (details) {
                          if ((details.primaryVelocity ?? 0) > 240) {
                            widget.onMinimize();
                          }
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _handleSideTap(true),
                        onVerticalDragEnd: (details) {
                          if ((details.primaryVelocity ?? 0) > 240) {
                            widget.onMinimize();
                          }
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
              if (!widget.session.ready)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x9917111F),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryPink,
                      ),
                    ),
                  ),
                ),
              if (_seekForward == true)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: width * 0.42,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.elliptical(90, 200),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.fast_forward_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '+$_accumulatedSeekSeconds giây',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(blurRadius: 4, color: Colors.black87),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_seekForward == false)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: width * 0.42,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.elliptical(90, 200),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.fast_rewind_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '-$_accumulatedSeekSeconds giây',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(blurRadius: 4, color: Colors.black87),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xB8000000),
                            Colors.transparent,
                            Color(0xD9000000),
                          ],
                          stops: [0, .48, 1],
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.session.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: widget.isFullScreen
                                    ? AppStrings.t('watch.exitFullscreen')
                                    : AppStrings.t('watch.minimize'),
                                onPressed: widget.onMinimize,
                                color: Colors.white,
                                icon: Icon(
                                  widget.isFullScreen
                                      ? Icons.arrow_back_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                ),
                              ),
                              IconButton(
                                tooltip: AppStrings.t('watch.qualityAndSpeed'),
                                onPressed: widget.onSettings,
                                color: Colors.white,
                                icon: const Icon(Icons.settings_rounded, size: 20),
                              ),
                              if (widget.isFullScreen && widget.onToggleZoom != null)
                                IconButton(
                                  tooltip: widget.zoomToFill
                                      ? 'Thu nhỏ vừa màn hình'
                                      : 'Thu phóng vừa với màn hình',
                                  onPressed: widget.onToggleZoom,
                                  color: widget.zoomToFill
                                      ? AppColors.primaryPink
                                      : Colors.white,
                                  icon: Icon(
                                    widget.zoomToFill
                                        ? Icons.fit_screen_rounded
                                        : Icons.crop_free_rounded,
                                    size: 20,
                                  ),
                                ),
                              if (widget.showPictureInPicture)
                                IconButton(
                                  tooltip: AppStrings.t('watch.pictureInPicture'),
                                  onPressed: widget.onPictureInPicture,
                                  color: Colors.white,
                                  icon: const Icon(
                                    Icons.picture_in_picture_alt_rounded,
                                    size: 19,
                                  ),
                                ),
                            ],
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _handleSideTap(false),
                                    onVerticalDragEnd: (details) {
                                      if ((details.primaryVelocity ?? 0) > 240) {
                                        widget.onMinimize();
                                      }
                                    },
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                                if (!widget.session.isPlaying)
                                  IconButton.filled(
                                    tooltip: AppStrings.t('watch.playVideo'),
                                    onPressed: () {
                                      unawaited(widget.session.togglePlayback());
                                      _scheduleHide();
                                    },
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black.withValues(
                                        alpha: .58,
                                      ),
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(58, 58),
                                    ),
                                    icon: const Icon(Icons.play_arrow_rounded, size: 36),
                                  )
                                else
                                  IconButton.filled(
                                    tooltip: AppStrings.t('watch.pauseVideo'),
                                    onPressed: () =>
                                        unawaited(widget.session.togglePlayback()),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black.withValues(
                                        alpha: .58,
                                      ),
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(52, 52),
                                    ),
                                    icon: const Icon(Icons.pause_rounded, size: 30),
                                  ),
                                Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _handleSideTap(true),
                                    onVerticalDragEnd: (details) {
                                      if ((details.primaryVelocity ?? 0) > 240) {
                                        widget.onMinimize();
                                      }
                                    },
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 5),
                            child: Row(
                              children: [
                                Text(
                                  _time(widget.session.position),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 2.5,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 5,
                                      ),
                                      overlayShape: const RoundSliderOverlayShape(
                                        overlayRadius: 13,
                                      ),
                                    ),
                                    child: Slider(
                                      min: 0,
                                      max: total > 0 ? total.toDouble() : 1,
                                      value: current,
                                      activeColor: AppColors.primaryPink,
                                      inactiveColor: Colors.white38,
                                      onChanged: total <= 0
                                          ? null
                                          : (value) => unawaited(
                                              widget.session.seekTo(
                                                Duration(
                                                  milliseconds: value.round(),
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                                Text(
                                  _time(widget.session.duration),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (widget.onToggleFullScreen != null) ...[
                                  const SizedBox(width: 4),
                                  IconButton(
                                    tooltip: widget.isFullScreen
                                        ? AppStrings.t('watch.exitFullscreen')
                                        : AppStrings.t('watch.fullscreen'),
                                    onPressed: widget.onToggleFullScreen,
                                    iconSize: 22,
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(),
                                    color: Colors.white,
                                    icon: Icon(
                                      widget.isFullScreen
                                          ? Icons.fullscreen_exit_rounded
                                          : Icons.fullscreen_rounded,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );

  String _time(Duration value) {
    final seconds = value.inSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final rest = seconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
    }
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }
}

class _ChannelSummary extends StatefulWidget {
  const _ChannelSummary({required this.video, required this.auth});
  final VideoDetail video;
  final AuthController auth;

  @override
  State<_ChannelSummary> createState() => _ChannelSummaryState();
}

class _ChannelSummaryState extends State<_ChannelSummary> {
  late final ChannelService _channels = ChannelService(widget.auth);
  bool _subscribed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSubscription();
  }

  Future<void> _loadSubscription() async {
    if (!widget.auth.authenticated) return;
    try {
      final status = await _channels.getSubscriptionStatus(
        widget.video.channelId,
      );
      if (mounted) setState(() => _subscribed = status?['status'] == 'active');
    } catch (_) {}
  }

  Future<void> _toggleSubscription() async {
    if (!widget.auth.authenticated) {
      final proceed = await showModalBottomSheet<bool>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Icon(
                  Icons.subscriptions_outlined,
                  size: 52,
                  color: AppColors.primaryPink,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Bạn muốn đăng ký kênh này?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Đăng nhập để đăng ký kênh và nhận thông báo về video mới nhất.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Để sau'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.primaryPink),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Đăng nhập'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      if (proceed == true && mounted) {
        context.push('/auth');
      }
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_subscribed) {
        await _channels.unsubscribe(widget.video.channelId);
      } else {
        await _channels.subscribe(widget.video.channelId);
      }
      if (mounted) setState(() => _subscribed = !_subscribed);
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      HuTubeAvatar(label: widget.video.channelName, radius: 22),
      const SizedBox(width: 11),
      Expanded(
        child: InkWell(
          onTap: () => context.push('/channels/${widget.video.channelHandle}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.video.channelName,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                '@${widget.video.channelHandle}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      OutlinedButton(
        onPressed: _busy ? null : _toggleSubscription,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          backgroundColor: _subscribed
              ? AppColors.surfaceAltFor(context)
              : null,
        ),
        child: Text(
          _busy ? '…' : (_subscribed ? AppStrings.t('watch.following') : AppStrings.t('watch.follow')),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );
}

class _WatchSkeletonPlayer extends StatelessWidget {
  const _WatchSkeletonPlayer();

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 9,
    child: DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.ink),
      child: Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          backgroundColor: Colors.white12,
        ),
      ),
    ),
  );
}

class _WatchSkeletonCopy extends StatelessWidget {
  const _WatchSkeletonCopy();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(width: 250, height: 22, color: AppColors.borderSubtle),
      const SizedBox(height: 10),
      Container(width: 180, height: 13, color: AppColors.borderSubtle),
      const SizedBox(height: 22),
      Container(height: 66, color: AppColors.borderSubtle),
    ],
  );
}

class _CommentTile extends StatefulWidget {
  const _CommentTile({
    required this.item,
    required this.content,
    required this.signedIn,
    required this.auth,
    required this.channelName,
    required this.isOwner,
    required this.isPinned,
    required this.isHearted,
    required this.onTogglePin,
    required this.onToggleHeart,
    required this.onToggleHide,
  });
  final CommentItem item;
  final ContentService content;
  final bool signedIn;
  final AuthController auth;
  final String channelName;
  final bool isOwner;
  final bool isPinned;
  final bool isHearted;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleHeart;
  final VoidCallback onToggleHide;

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  late CommentItem _item;
  List<CommentItem>? _replies;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
  }

  @override
  void didUpdateWidget(covariant _CommentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item) {
      _item = widget.item;
    }
  }

  Future<void> _react() async {
    if (!widget.signedIn) return;
    try {
      final response = await widget.content.reactComment(
        _item.id,
        _item.myReaction == 'like' ? null : 'like',
      );
      if (!mounted) return;
      setState(() {
        _item = CommentItem(
          id: _item.id,
          videoId: _item.videoId,
          displayName: _item.displayName,
          content: _item.content,
          createdAt: _item.createdAt,
          likes: asInt(response['likes']),
          dislikes: asInt(response['dislikes']),
          myReaction: response['myReaction'] as String?,
          replyCount: _item.replyCount,
          userId: _item.userId,
          status: _item.status,
        );
      });
    } on ApiFailure {
      // The parent page already keeps the read path usable if an interaction
      // fails; a failed reaction should not alter the rendered count.
    }
  }

  Future<void> _reply() async {
    HapticFeedback.lightImpact();
    if (!widget.signedIn) return;
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          AppStrings.format('watch.replyTitle', {'name': _item.displayName}),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: AppStrings.t('watch.replyHint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppStrings.t('common.cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            icon: AppIcons.asset(AppIcons.send, size: 16, color: Colors.white),
            label: Text(AppStrings.t('common.send')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;
    try {
      final reply = await widget.content.createComment(
        _item.videoId,
        text.trim(),
        parentCommentId: _item.id,
      );
      if (mounted) setState(() => _replies = [...?_replies, reply]);
    } on ApiFailure {
      // Leave the dialog closed; the API is the source of truth for replies.
    }
  }

  Future<void> _loadReplies() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final replies = await widget.content.replies(_item.id);
      if (mounted) {
        setState(() {
          _replies = replies.items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    final controller = TextEditingController(text: _item.content);
    final updatedText = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.t('watch.editComment')),
        content: TextField(controller: controller, minLines: 2, maxLines: 5),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppStrings.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(AppStrings.t('common.save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updatedText == null || updatedText.trim().isEmpty) return;
    try {
      final updated = await widget.content.updateComment(_item.id, updatedText);
      if (mounted) setState(() => _item = updated);
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.t('watch.deleteCommentTitle')),
        content: Text(AppStrings.t('watch.deleteCommentDescription')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppStrings.t('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.content.deleteComment(_item.id);
      if (mounted) {
        setState(
          () => _item = CommentItem(
            id: _item.id,
            videoId: _item.videoId,
            displayName: _item.displayName,
            content: AppStrings.t('watch.commentDeleted'),
            createdAt: _item.createdAt,
            likes: _item.likes,
            dislikes: _item.dislikes,
            myReaction: null,
            replyCount: 0,
            userId: _item.userId,
            status: 'deleted',
          ),
        );
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isPinned || _item.isPinned)
          Padding(
            padding: const EdgeInsets.only(left: 43, bottom: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.push_pin_rounded,
                  size: 14,
                  color: AppColors.primaryPink,
                ),
                const SizedBox(width: 4),
                Text(
                  AppStrings.format('watch.pinnedBy', {
                    'channel': widget.channelName.isEmpty
                        ? AppStrings.t('channel.owner')
                        : widget.channelName,
                  }),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryPink,
                  ),
                ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 17,
              child: Text(
                _item.displayName.isEmpty
                    ? 'H'
                    : _item.displayName.substring(0, 1),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _item.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (_item.status == 'hidden') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            AppStrings.t('watch.hideComment'),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.amber,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _item.content,
                    style: TextStyle(
                      color: _item.status == 'hidden'
                          ? Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5)
                          : null,
                    ),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _react,
                        icon: const Icon(Icons.thumb_up_outlined, size: 16),
                        label: Text(AppStrings.number(_item.likes)),
                      ),
                      TextButton(
                        onPressed: _reply,
                        child: Text(AppStrings.t('common.reply')),
                      ),
                      if (widget.isHearted || _item.hasCreatorHeart)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.favorite_rounded,
                                size: 13,
                                color: Colors.redAccent,
                              ),
                              const SizedBox(width: 4),
                              CircleAvatar(
                                radius: 8,
                                backgroundColor: AppColors.primaryPink,
                                child: Text(
                                  widget.channelName.isNotEmpty
                                      ? widget.channelName[0].toUpperCase()
                                      : 'H',
                                  style: const TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Spacer(),
                      if (_item.userId == widget.auth.user?['userId'] ||
                          widget.isOwner)
                        PopupMenuButton<String>(
                          tooltip: AppStrings.t('watch.commentOptions'),
                          onSelected: (choice) {
                            if (choice == 'pin') widget.onTogglePin();
                            if (choice == 'heart') widget.onToggleHeart();
                            if (choice == 'hide') widget.onToggleHide();
                            if (choice == 'edit') _edit();
                            if (choice == 'delete') _delete();
                          },
                          itemBuilder: (_) => [
                            if (widget.isOwner) ...[
                              PopupMenuItem(
                                value: 'pin',
                                child: Row(
                                  children: [
                                    Icon(
                                      widget.isPinned
                                          ? Icons.push_pin_rounded
                                          : Icons.push_pin_outlined,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      widget.isPinned
                                          ? AppStrings.t('watch.unpinComment')
                                          : AppStrings.t('watch.pinComment'),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'heart',
                                child: Row(
                                  children: [
                                    Icon(
                                      widget.isHearted
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      size: 18,
                                      color: Colors.redAccent,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      widget.isHearted
                                          ? AppStrings.t('watch.unheartComment')
                                          : AppStrings.t('watch.heartComment'),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'hide',
                                child: Row(
                                  children: [
                                    Icon(
                                      _item.status == 'hidden'
                                          ? Icons.visibility_rounded
                                          : Icons.visibility_off_outlined,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _item.status == 'hidden'
                                          ? AppStrings.t('watch.unhideComment')
                                          : AppStrings.t('watch.hideComment'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (_item.userId == widget.auth.user?['userId']) ...[
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    const Icon(Icons.edit_outlined, size: 18),
                                    const SizedBox(width: 8),
                                    Text(AppStrings.t('common.edit')),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: Colors.redAccent,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(AppStrings.t('common.delete')),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        )
                      else if (widget.signedIn && _item.status != 'deleted')
                        IconButton(
                          tooltip: AppStrings.t('watch.reportComment'),
                          onPressed: () => showContentReportDialog(
                            context,
                            auth: widget.auth,
                            targetType: 'comment',
                            targetId: _item.id,
                          ),
                          icon: const Icon(Icons.flag_outlined, size: 18),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_item.replyCount > 0)
          TextButton(
            onPressed: _loadReplies,
            child: Text(
              _loading
                  ? AppStrings.t('watch.repliesLoading')
                  : AppStrings.format('watch.replies', {
                      'count': AppStrings.number(_item.replyCount),
                    }),
            ),
          ),
        if (_replies != null)
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: Column(
              children: _replies!
                  .map(
                    (reply) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        reply.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(reply.content),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    ),
  );
}
