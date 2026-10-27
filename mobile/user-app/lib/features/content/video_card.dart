import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../playlists/save_playlist_sheet.dart';
import 'content_models.dart';

class VideoCardTile extends StatelessWidget {
  const VideoCardTile({
    super.key,
    required this.video,
    this.progress,
    this.replaceRoute = false,
    this.trailing,
    this.auth,
    this.compact = false,
  });

  final VideoCard video;
  final double? progress;
  final bool replaceRoute;
  final Widget? trailing;
  final AuthController? auth;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final history = video is LibraryVideo ? video as LibraryVideo : null;
    final metadata = history == null
        ? '${video.channelName} · ${AppStrings.format('feed.views', {'count': AppStrings.number(video.views)})}${_dateSuffix(video.publishedAt)}'
        : '${video.channelName}${history.watchedSeconds > 0 ? ' · ${AppStrings.format('library.watchedFor', {'time': _duration(history.watchedSeconds)})}' : ''}${_dateSuffix(history.activityAt)}';

    if (compact) return _compactCard(context, metadata);
    return Semantics(
      button: true,
      label: AppStrings.format('feed.openVideo', {'title': video.title}),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => replaceRoute
            ? context.go('/watch/${video.id}')
            : context.push('/watch/${video.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: video.thumbnailUrl?.startsWith('http') == true
                            ? Image.network(
                                video.thumbnailUrl!,
                                fit: BoxFit.cover,
                                cacheWidth: 720,
                                errorBuilder: (_, _, _) =>
                                    const _VideoFallback(),
                              )
                            : const _VideoFallback(),
                      ),
                      if (video.isPromoted)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: HuTubePill(
                            label: AppStrings.t('feed.promoted'),
                            icon: Icons.campaign_outlined,
                            color: AppColors.primaryPink,
                            textColor: Colors.white,
                          ),
                        ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: HuTubePill(
                          label: _duration(video.duration),
                          icon: Icons.schedule_rounded,
                          color: Colors.black.withValues(alpha: .78),
                          textColor: Colors.white,
                        ),
                      ),
                      if (progress != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: progress!.clamp(0, 1),
                            minHeight: 3,
                            color: AppColors.primaryPink,
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 11, 0, 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HuTubeAvatar(radius: 17, label: video.channelName),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            metadata,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppColors.textMutedFor(context),
                                  fontSize: 12,
                                  height: 1.45,
                                ),
                          ),
                        ],
                      ),
                    ),
                    trailing ?? _actions(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context) => PopupMenuButton<String>(
    tooltip: AppStrings.t('common.moreOptions'),
    padding: EdgeInsets.zero,
    style: IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      tapTargetSize: MaterialTapTargetSize.padded,
    ),
    icon: const Icon(Icons.more_vert_rounded, size: 18),
    onSelected: (action) {
      if (action == 'share') {
        Share.share(
          'Xem "${video.title}" trên Dalitu:\nhttps://hutube.app/watch/${video.id}',
        );
      } else if (action == 'playlist' && auth != null) {
        showAddVideoToPlaylistSheet(context, auth: auth!, videoId: video.id);
      }
    },
    itemBuilder: (_) => [
      if (auth != null)
        PopupMenuItem(
          value: 'playlist',
          child: Row(
            children: [
              AppIcons.asset(AppIcons.playlist, size: 18),
              const SizedBox(width: 10),
              Text(AppStrings.t('watch.savePlaylist')),
            ],
          ),
        ),
      PopupMenuItem(
        value: 'share',
        child: Row(
          children: [
            const Icon(Icons.share_outlined, size: 18),
            const SizedBox(width: 10),
            Text(AppStrings.t('common.share')),
          ],
        ),
      ),
    ],
  );

  Widget _compactCard(BuildContext context, String metadata) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () => replaceRoute
        ? context.go('/watch/${video.id}')
        : context.push('/watch/${video.id}'),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, bounds) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: (bounds.maxWidth * .39).clamp(96.0, 200.0),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (video.thumbnailUrl?.startsWith('http') == true)
                        Image.network(
                          video.thumbnailUrl!,
                          fit: BoxFit.cover,
                          cacheWidth: 480,
                          errorBuilder: (_, _, _) => const _VideoFallback(),
                        )
                      else
                        const _VideoFallback(),
                      Positioned(
                        right: 4,
                        bottom: progress != null ? 7 : 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .76),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Text(
                              _duration(video.duration),
                              textScaler: TextScaler.noScaling,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
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
                            value: progress!.clamp(0, 1),
                            minHeight: 3,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    metadata,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textMutedFor(context),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 40, child: trailing ?? _actions(context)),
          ],
        ),
      ),
    ),
  );

  static String _duration(int seconds) {
    final duration = Duration(seconds: seconds < 0 ? 0 : seconds);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final remainder = duration.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return duration.inHours > 0
        ? '${duration.inHours}:$minutes:$remainder'
        : '${duration.inMinutes}:$remainder';
  }

  static String _dateSuffix(DateTime? date) {
    if (date == null) return '';
    return ' · ${AppStrings.relativeDate(date)}';
  }
}

Future<void> showAddVideoToPlaylistSheet(
  BuildContext context, {
  required AuthController auth,
  required String videoId,
}) async {
  if (!auth.authenticated) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.t('watch.loginPlaylist'))),
    );
    return;
  }

  final saved = await showSavePlaylistSheet(
    context,
    auth: auth,
    videoId: videoId,
  );
  if (saved && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.t('watch.savedToPlaylist'))),
    );
  }
}

class _VideoFallback extends StatelessWidget {
  const _VideoFallback();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF371426), Color(0xFF171927)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: const Center(
      child: Icon(
        Icons.play_circle_fill_rounded,
        color: Colors.white70,
        size: 52,
      ),
    ),
  );
}
