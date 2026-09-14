import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import 'content_models.dart';

class VideoCardTile extends StatelessWidget {
  const VideoCardTile({super.key, required this.video, this.progress});

  final VideoCard video;
  final double? progress;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Mở video ${video.title}',
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/watch/${video.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: video.thumbnailUrl?.startsWith('http') == true
                        ? Image.network(
                            video.thumbnailUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const _VideoFallback(),
                          )
                        : const _VideoFallback(),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .78),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: Text(
                          _duration(video.duration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
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
                        color: AppColors.primaryPink,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: AppColors.primaryPink.withValues(
                      alpha: .12,
                    ),
                    child: Text(
                      video.channelName.isEmpty
                          ? 'H'
                          : video.channelName.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.primaryPink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
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
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${video.channelName} · ${video.views} lượt xem${_dateSuffix(video.publishedAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
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
    final days = DateTime.now().difference(date.toLocal()).inDays;
    if (days <= 0) return ' · Hôm nay';
    if (days < 30) return ' · $days ngày trước';
    return ' · ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
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
