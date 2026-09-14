import 'dart:async';
import 'dart:io';

import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth.dart';
import '../../core/theme/app_theme.dart';
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
      if (mounted)
        setState(() {
          _error = error.message;
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _error = 'Không thể tải video này. Vui lòng thử lại.';
          _loading = false;
        });
    }
  }

  Future<void> _startPlayer(String url, {int resumeAt = 0}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      if (mounted)
        setState(
          () => _actionMessage =
              'Nguồn video không hợp lệ. Máy chủ cần trả về URL HTTP(S).',
        );
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
        _actionMessage = 'Không thể phát nguồn video này.';
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
      setState(
        () => _actionMessage =
            'Thiết bị hiện không hỗ trợ PiP cho nguồn video này.',
      );
    }
  }

  Future<void> _react(String type) async {
    if (!widget.auth.authenticated) {
      setState(() => _actionMessage = 'Đăng nhập để tương tác với video.');
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
      if (mounted) setState(() => _actionMessage = error.message);
    }
  }

  Future<void> _rate() async {
    if (!widget.auth.authenticated) {
      setState(() => _actionMessage = 'Đăng nhập để đánh giá video.');
      return;
    }
    final score = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(title: Text('Đánh giá video')),
            for (var value = 1; value <= 5; value++)
              ListTile(
                leading: Icon(Icons.star_rounded, color: Colors.amber.shade700),
                title: Text('$value sao'),
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
        _actionMessage = 'Đã cập nhật đánh giá của bạn.';
      });
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _actionMessage = error.message);
    }
  }

  Future<void> _share() async {
    final video = _video;
    if (video == null) return;
    if (widget.auth.authenticated) unawaited(_content.share(video.id));
    await Share.share(
      'Xem ${video.title} trên HuTube\nhutube://watch/${video.id}',
    );
  }

  Future<void> _download() async {
    if (!widget.auth.authenticated) {
      setState(() => _actionMessage = 'Đăng nhập để tải video xuống.');
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
              const ListTile(title: Text('Chọn chất lượng tải xuống')),
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
        title: '${record['title'] ?? _video?.title ?? 'video'}',
        quality: '${record['quality'] ?? chosen.quality}',
        url: '${record['fileUrl'] ?? chosen.url}',
        fileSize: asInt(record['fileSize']),
      );
      if (mounted)
        setState(
          () =>
              _actionMessage = 'Đã thêm vào danh sách tải xuống trên thiết bị.',
        );
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _actionMessage = error.message);
    }
  }

  Future<void> _sendComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty || _sendingComment) return;
    if (!widget.auth.authenticated) {
      setState(() => _actionMessage = 'Đăng nhập để bình luận.');
      return;
    }
    setState(() => _sendingComment = true);
    try {
      final comment = await _content.createComment(widget.videoId, text);
      if (mounted)
        setState(() {
          _comments = [comment, ..._comments];
          _comment.clear();
          _sendingComment = false;
        });
    } on ApiFailure catch (error) {
      if (mounted)
        setState(() {
          _actionMessage = error.message;
          _sendingComment = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryPink),
      );
    if (_error != null || _video == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ?? 'Video không khả dụng.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Thử lại')),
            ],
          ),
        ),
      );
    }
    final video = _video!;
    final player = _player;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
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
        const SizedBox(height: 14),
        Text(
          video.title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          '${video.stats.views} lượt xem · ${video.channelName}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _ActionChip(
                icon: Icons.thumb_up_outlined,
                label: '${video.stats.likes}',
                active: video.viewerState.reaction == 'like',
                onTap: () => _react('like'),
              ),
              _ActionChip(
                icon: Icons.thumb_down_outlined,
                label: '${video.stats.dislikes}',
                active: video.viewerState.reaction == 'dislike',
                onTap: () => _react('dislike'),
              ),
              _ActionChip(
                icon: Icons.star_outline_rounded,
                label: 'Đánh giá',
                onTap: _rate,
              ),
              _ActionChip(
                icon: Icons.share_outlined,
                label: 'Chia sẻ',
                onTap: _share,
              ),
              _ActionChip(
                icon: Icons.download_outlined,
                label: 'Tải xuống',
                onTap: _download,
              ),
              if (_entitlements.pictureInPicture)
                _ActionChip(
                  icon: Icons.picture_in_picture_alt_outlined,
                  label: 'PiP',
                  onTap: _enterPictureInPicture,
                ),
              if (_entitlements.backgroundPlayback)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Chip(
                    avatar: Icon(Icons.headphones_outlined, size: 18),
                    label: Text('Phát nền'),
                  ),
                ),
            ],
          ),
        ),
        if (_actionMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _actionMessage!,
              style: const TextStyle(color: AppColors.primaryPink),
            ),
          ),
        const SizedBox(height: 18),
        _ChannelSummary(video: video),
        if ((video.description ?? '').isNotEmpty || video.tags.isNotEmpty) ...[
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((video.description ?? '').isNotEmpty)
                    Text(video.description!),
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
            'Chương',
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
        const SizedBox(height: 18),
        Text(
          'Bình luận (${video.stats.comments})',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _comment,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: widget.auth.authenticated
                ? 'Viết bình luận...'
                : 'Đăng nhập để bình luận',
          ),
          enabled: widget.auth.authenticated,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _sendingComment ? null : _sendComment,
            child: Text(_sendingComment ? 'Đang gửi...' : 'Bình luận'),
          ),
        ),
        ..._comments.map(
          (item) => _CommentTile(
            item: item,
            content: _content,
            signedIn: widget.auth.authenticated,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Video liên quan',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        ..._related.map((item) => VideoCardTile(video: item)),
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
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      child: Text(
        video.channelName.isEmpty ? 'H' : video.channelName.substring(0, 1),
      ),
    ),
    title: Text(
      video.channelName,
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
    subtitle: Text('@${video.channelHandle}'),
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
        title: Text('Trả lời ${_item.displayName}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'Viết phản hồi của bạn'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Gửi'),
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
      if (mounted)
        setState(() {
          _replies = replies.items;
          _loading = false;
        });
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
                        label: Text('${_item.likes}'),
                      ),
                      TextButton(
                        onPressed: _reply,
                        child: const Text('Trả lời'),
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
              _loading ? 'Đang tải...' : '${_item.replyCount} câu trả lời',
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
