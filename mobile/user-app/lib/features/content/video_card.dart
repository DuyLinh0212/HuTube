import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'content_models.dart';

class VideoCardTile extends StatelessWidget {
  const VideoCardTile({
    super.key,
    required this.video,
    this.progress,
    this.replaceRoute = false,
  });

  final VideoCard video;
  final double? progress;
  final bool replaceRoute;

  @override
  Widget build(BuildContext context) => Semantics(
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
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: video.thumbnailUrl?.startsWith('http') == true
                        ? Image.network(
                            video.thumbnailUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const _VideoFallback(),
                          )
                        : const _VideoFallback(),
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
                            fontSize: 14,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${video.channelName} · ${AppStrings.format('feed.views', {'count': AppStrings.number(video.views)})}${_dateSuffix(video.publishedAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.textMutedFor(context),
                                fontSize: 11,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.more_vert_rounded, size: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  static String _duration(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  static String _dateSuffix(DateTime? date) {
    if (date == null) return '';
    return ' · ${AppStrings.relativeDate(date)}';
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
