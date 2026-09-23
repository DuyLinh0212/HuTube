import 'dart:async';
import 'dart:io';

import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
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

class _WatchScreenState extends State<WatchScreen> {
  late final ContentService _content;
  final _comment = TextEditingController();
  VideoDetail? _video;
  List<Rendition> _renditions = const [];
  MediaEntitlements _entitlements = const MediaEntitlements.none();
  List<CommentItem> _comments = [];
  List<VideoCard> _related = [];
  bool _loading = true;
  bool _sendingComment = false;
  String? _error;
  String? _actionMessage;

  @override
  void initState() {
    super.initState();
    _content = ContentService(widget.auth);
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    if (widget.playback.videoId == widget.videoId &&
        !widget.playback.minimized) {
      unawaited(widget.playback.dismiss());
    }
    super.dispose();
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
      if (!mounted) return;
      setState(() {
        _video = detail;
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
      final resumeAt = playback.resumeAt > 0
          ? playback.resumeAt
          : detail.viewerState.resumeAt;
      final source = _renditions.isNotEmpty
          ? _renditions.last.url
          : detail.videoUrl;
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

  Future<void> _react(String type) async {
    if (!widget.auth.authenticated) {
      setState(() => _actionMessage = AppStrings.t('watch.loginInteract'));
      return;
    }
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
    if (!widget.auth.authenticated) {
      setState(() => _actionMessage = AppStrings.t('watch.loginRate'));
      return;
    }
    final score = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(title: Text(AppStrings.t('watch.ratingTitle'))),
            for (var value = 1; value <= 5; value++)
              ListTile(
                leading: Icon(Icons.star_rounded, color: Colors.amber.shade700),
                title: Text(
                  AppStrings.format('watch.ratingStars', {
                    'count': AppStrings.number(value),
                  }),
                ),
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
    if (score == null || _video == null) return;
    try {
      final result = await _content.rate(widget.videoId, score);
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
        _actionMessage = AppStrings.t('watch.ratingSaved');
      });
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() => _actionMessage = AppStrings.apiError(error));
      }
    }
  }

  Future<void> _share() async {
    final video = _video;
    if (video == null) return;
    if (widget.auth.authenticated) unawaited(_content.share(video.id));
    await Share.share(
      AppStrings.format('watch.shareText', {
        'title': video.title,
        'id': video.id,
      }),
    );
  }

  Future<void> _download() async {
    if (!widget.auth.authenticated) {
      setState(() => _actionMessage = AppStrings.t('watch.loginDownload'));
      return;
    }
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
    if (!widget.auth.authenticated) {
      setState(() => _actionMessage = 'Đăng nhập để lưu video vào playlist.');
      return;
    }
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
              const ListTile(title: Text('Lưu video')),
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: const Text('Video đã lưu'),
                onTap: () => Navigator.pop(context, '__saved__'),
              ),
              for (final playlist in playlists)
                ListTile(
                  leading: const Icon(Icons.playlist_play_rounded),
                  title: Text(playlist.name),
                  subtitle: Text('${playlist.itemCount} video'),
                  onTap: () => Navigator.pop(context, playlist.id),
                ),
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: const Text('Tạo playlist mới'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/playlists');
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
        setState(() => _actionMessage = 'Video đã được lưu vào playlist.');
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
            const ListTile(
              title: Text(
                'Chất lượng',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text('Chọn độ phân giải video'),
            ),
            if (_renditions.isEmpty)
              const ListTile(title: Text('Chất lượng gốc'))
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
            const ListTile(
              title: Text(
                'Tốc độ phát',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text('Thay đổi tốc độ phát video'),
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
                title: Text(speed == 1 ? 'Bình thường' : '$speed×'),
                trailing: (player.speed - speed).abs() < .01
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  unawaited(widget.playback.setSpeed(speed));
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
    if (!widget.auth.authenticated) {
      setState(() => _actionMessage = AppStrings.t('watch.loginCommentHint'));
      return;
    }
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
        message: 'Nguồn video có thể đã bị gỡ hoặc tạm thời chưa sẵn sàng.',
        actionLabel: AppStrings.t('common.retry'),
        onAction: _load,
      );
    }
    final video = _video!;
    return ListView(
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
                  ? _CustomVideoStage(
                      session: widget.playback,
                      onMinimize: () {
                        widget.playback.minimize();
                        Navigator.of(context).maybePop();
                      },
                      onSettings: _showPlaybackSettings,
                      onPictureInPicture: _enterPictureInPicture,
                      showPictureInPicture: _entitlements.pictureInPicture,
                    )
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
                icon: Icons.star_outline_rounded,
                label: AppStrings.t('watch.rateAction'),
                onTap: _rate,
              ),
              _ActionChip(
                icon: Icons.share_outlined,
                label: AppStrings.t('watch.shareAction'),
                onTap: _share,
              ),
              _ActionChip(
                icon: Icons.download_outlined,
                label: AppStrings.t('watch.downloadAction'),
                onTap: _download,
              ),
              _ActionChip(
                icon: Icons.playlist_add_rounded,
                label: 'Lưu playlist',
                onTap: _saveToPlaylist,
              ),
              _ActionChip(
                icon: Icons.flag_outlined,
                label: 'Báo cáo',
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
          child: HuTubeSectionHeader(
            title: AppStrings.format('watch.comments', {
              'count': AppStrings.number(video.stats.comments),
            }),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _comment,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: widget.auth.authenticated
                  ? AppStrings.t('watch.commentHint')
                  : AppStrings.t('watch.loginCommentHint'),
              suffixIcon: IconButton(
                onPressed: _sendingComment ? null : _sendComment,
                icon: const Icon(Icons.send_rounded),
              ),
            ),
            enabled: widget.auth.authenticated,
          ),
        ),
        const SizedBox(height: 8),
        ..._comments.map(
          (item) => _CommentTile(
            item: item,
            content: _content,
            signedIn: widget.auth.authenticated,
            auth: widget.auth,
          ),
        ),
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
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ActionChip(
      avatar: Icon(
        icon,
        size: 18,
        color: active ? AppColors.primaryPink : null,
      ),
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
  });

  final PlaybackSession session;
  final VoidCallback onMinimize;
  final VoidCallback onSettings;
  final VoidCallback onPictureInPicture;
  final bool showPictureInPicture;

  @override
  State<_CustomVideoStage> createState() => _CustomVideoStageState();
}

class _CustomVideoStageState extends State<_CustomVideoStage> {
  bool _controlsVisible = true;
  bool? _seekForward;
  double _tapX = 0;
  Timer? _controlsTimer;
  Timer? _pulseTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _pulseTimer?.cancel();
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

  void _seek() {
    final forward = _tapX >= MediaQuery.sizeOf(context).width / 2;
    unawaited(widget.session.seekBy(forward ? 10 : -10));
    setState(() {
      _seekForward = forward;
      _controlsVisible = true;
    });
    _scheduleHide();
    _pulseTimer?.cancel();
    _pulseTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => _seekForward = null);
    });
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
      return Stack(
        fit: StackFit.expand,
        children: [
          NativeVideoPlayer(controller: player),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleControls,
              onDoubleTapDown: (details) => _tapX = details.localPosition.dx,
              onDoubleTap: _seek,
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) > 240) widget.onMinimize();
              },
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
          if (_seekForward != null)
            Align(
              alignment: _seekForward!
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .68),
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _seekForward!
                            ? Icons.forward_10_rounded
                            : Icons.replay_10_rounded,
                        color: Colors.white,
                        size: 31,
                      ),
                      const Text(
                        '10 giây',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
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
                            tooltip: 'Thu nhỏ video',
                            onPressed: widget.onMinimize,
                            color: Colors.white,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          ),
                          IconButton(
                            tooltip: 'Chất lượng và tốc độ',
                            onPressed: widget.onSettings,
                            color: Colors.white,
                            icon: const Icon(Icons.settings_rounded, size: 20),
                          ),
                          if (widget.showPictureInPicture)
                            IconButton(
                              tooltip: 'Phát cửa sổ nổi',
                              onPressed: widget.onPictureInPicture,
                              color: Colors.white,
                              icon: const Icon(
                                Icons.picture_in_picture_alt_rounded,
                                size: 19,
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      if (!widget.session.isPlaying)
                        IconButton.filled(
                          tooltip: 'Phát video',
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
                          tooltip: 'Tạm dừng video',
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
                      const Spacer(),
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
      context.go('/auth');
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
          _busy ? '…' : (_subscribed ? 'Đang theo dõi' : 'Theo dõi'),
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
  });
  final CommentItem item;
  final ContentService content;
  final bool signedIn;
  final AuthController auth;
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
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(AppStrings.t('common.send')),
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
        title: const Text('Chỉnh sửa bình luận'),
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
        title: const Text('Xóa bình luận?'),
        content: const Text('Bạn có thể đăng bình luận mới sau khi xóa.'),
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
            content: 'Bình luận đã bị xóa.',
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
                  Text(
                    _item.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(_item.content),
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
                      if (_item.userId == widget.auth.user?['userId'])
                        PopupMenuButton<String>(
                          tooltip: 'Tùy chọn bình luận',
                          onSelected: (choice) {
                            if (choice == 'edit') _edit();
                            if (choice == 'delete') _delete();
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Chỉnh sửa'),
                            ),
                            PopupMenuItem(value: 'delete', child: Text('Xóa')),
                          ],
                        )
                      else if (widget.signedIn && _item.status != 'deleted')
                        IconButton(
                          tooltip: 'Báo cáo bình luận',
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
