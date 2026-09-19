import 'dart:async';
import 'dart:io';

import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'content_models.dart';
import 'content_service.dart';
import 'local_download_manager.dart';
import 'media_entitlements.dart';
import 'video_card.dart';

class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key, required this.auth, required this.videoId});
  final AuthController auth;
  final String videoId;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  late final ContentService _content;
  final _comment = TextEditingController();
  NativeVideoPlayerController? _player;
  BackgroundPlaybackGuard? _backgroundPlaybackGuard;
  StreamSubscription<Duration>? _positionSubscription;
  VideoDetail? _video;
  MediaEntitlements _entitlements = const MediaEntitlements.none();
  List<CommentItem> _comments = [];
  List<VideoCard> _related = [];
  bool _loading = true;
  bool _sendingComment = false;
  bool _playerReady = false;
  String? _error;
  String? _actionMessage;
  int _lastSavedSecond = 0;

  @override
  void initState() {
    super.initState();
    _content = ContentService(widget.auth);
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    _positionSubscription?.cancel();
    _backgroundPlaybackGuard?.dispose();
    unawaited(_player?.dispose());
    super.dispose();
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
        _entitlements = entitlements;
        _comments = comments.items;
        _related = related.items
            .where((item) => item.id != detail.id)
            .take(8)
            .toList();
        _loading = false;
      });
      await _startPlayer(
        playback.renditions.isNotEmpty
            ? playback.renditions.last.url
            : detail.videoUrl,
        resumeAt: playback.resumeAt > 0
            ? playback.resumeAt
            : detail.viewerState.resumeAt,
      );
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

  Future<void> _startPlayer(String url, {int resumeAt = 0}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      if (mounted) {
        setState(() => _actionMessage = AppStrings.t('watch.invalidSource'));
      }
      return;
    }
    // The native player keeps media alive in the background by default. A
    // guard is therefore always installed and only permits that behavior for
    // accounts whose current plan has `background_play` enabled.
    final next = NativeVideoPlayerController(
      id: widget.videoId.hashCode & 0x7fffffff,
      autoPlay: false,
      showNativeControls: true,
      allowsPictureInPicture: _entitlements.pictureInPicture,
      canStartPictureInPictureAutomatically: _entitlements.pictureInPicture,
    );
    final nextGuard = BackgroundPlaybackGuard(
      next,
      pauseInBackground: !_entitlements.backgroundPlayback,
    );
    final old = _player;
    final oldGuard = _backgroundPlaybackGuard;
    final oldSubscription = _positionSubscription;
    if (!mounted) {
      nextGuard.dispose();
      unawaited(next.dispose());
      return;
    }
    setState(() {
      _player = next;
      _backgroundPlaybackGuard = nextGuard;
      _positionSubscription = null;
      _playerReady = false;
    });
    oldGuard?.dispose();
    unawaited(oldSubscription?.cancel());
    unawaited(old?.dispose());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_player, next)) {
        unawaited(_initializePlayer(next, url, resumeAt: resumeAt));
      }
    });
  }

  Future<void> _initializePlayer(
    NativeVideoPlayerController player,
    String url, {
    required int resumeAt,
  }) async {
    try {
      // initialize waits until NativeVideoPlayer has created its platform view,
      // which is why it runs only after the widget is in the tree.
      await player.initialize();
      await player.loadUrl(
        url: url,
        startAt: resumeAt > 0 ? Duration(seconds: resumeAt) : null,
      );
      if (!mounted || !identical(_player, player)) return;
      _positionSubscription = player.positionStream.listen((position) {
        if (identical(_player, player)) _onPositionChanged(position);
      });
      setState(() => _playerReady = true);
    } catch (_) {
      if (!mounted || !identical(_player, player)) return;
      _backgroundPlaybackGuard?.dispose();
      _backgroundPlaybackGuard = null;
      _player = null;
      unawaited(player.dispose());
      setState(() {
        _playerReady = false;
        _actionMessage = AppStrings.t('watch.playerError');
      });
    }
  }

  void _onPositionChanged(Duration position) {
    if (!mounted) return;
    final seconds = position.inSeconds;
    if (widget.auth.authenticated && seconds - _lastSavedSecond >= 10) {
      _lastSavedSecond = seconds;
      unawaited(_content.progress(widget.videoId, seconds));
    }
  }

  Future<void> _enterPictureInPicture() async {
    final player = _player;
    if (player == null || !_playerReady) return;
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
    final player = _player;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(16),
          ),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: player != null
                ? Stack(
                    children: [
                      NativeVideoPlayer(controller: player),
                      if (!_playerReady)
                        const Positioned.fill(
                          child: ColoredBox(
                            color: Color(0xB3171927),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primaryPink,
                              ),
                            ),
                          ),
                        ),
                    ],
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
          child: _ChannelSummary(video: video),
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
              onTap: () =>
                  _player?.seekTo(Duration(seconds: chapter.startSeconds)),
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
                .map((item) => VideoCardTile(video: item))
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

class _ChannelSummary extends StatelessWidget {
  const _ChannelSummary({required this.video});
  final VideoDetail video;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      HuTubeAvatar(label: video.channelName, radius: 22),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              video.channelName,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              '@${video.channelHandle}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      OutlinedButton(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Theo dõi kênh sẽ được kết nối khi API sẵn sàng.'),
          ),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: const Text('Theo dõi'),
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
  });
  final CommentItem item;
  final ContentService content;
  final bool signedIn;
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
