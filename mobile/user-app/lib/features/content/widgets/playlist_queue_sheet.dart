import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../content_models.dart';
import '../playback_session.dart';

class PlaylistQueueSheet extends StatelessWidget {
  const PlaylistQueueSheet({
    super.key,
    required this.playback,
    required this.onSelectVideo,
  });

  final PlaybackSession playback;
  final ValueChanged<VideoCard> onSelectVideo;

  static Future<void> show(
    BuildContext context, {
    required PlaybackSession playback,
    required ValueChanged<VideoCard> onSelectVideo,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => PlaylistQueueSheet(
          playback: playback,
          onSelectVideo: onSelectVideo,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: playback,
      builder: (context, _) {
        final queue = playback.queue;
        final currentIdx = playback.queueIndex;

        return Container(
          height: mediaQuery.size.height * 0.72,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBackgroundCard : AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Top drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 10),
                child: Row(
                  children: [
                    AppIcons.asset(
                      AppIcons.queue,
                      size: 22,
                      color: AppColors.primaryPink,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.t('queue.title'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            AppStrings.format('queue.count', {
                              'count': AppStrings.number(queue.length),
                            }),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: AppStrings.t('common.close'),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Control chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    FilterChip(
                      avatar: Icon(
                        playback.autoplayNext
                            ? Icons.autorenew_rounded
                            : Icons.pause_circle_outline_rounded,
                        size: 16,
                        color: playback.autoplayNext
                            ? AppColors.primaryPink
                            : AppColors.textMuted,
                      ),
                      label: Text(AppStrings.t('queue.autoplay')),
                      selected: playback.autoplayNext,
                      selectedColor:
                          AppColors.primaryPink.withValues(alpha: 0.15),
                      checkmarkColor: AppColors.primaryPink,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        playback.toggleAutoplay();
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      avatar: Icon(
                        Icons.shuffle_rounded,
                        size: 16,
                        color: playback.isShuffle
                            ? AppColors.violet
                            : AppColors.textMuted,
                      ),
                      label: Text(AppStrings.t('queue.shuffle')),
                      selected: playback.isShuffle,
                      selectedColor: AppColors.violet.withValues(alpha: 0.15),
                      checkmarkColor: AppColors.violet,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        playback.toggleShuffle();
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      avatar: Icon(
                        Icons.repeat_rounded,
                        size: 16,
                        color: playback.isLoop
                            ? AppColors.info
                            : AppColors.textMuted,
                      ),
                      label: Text(AppStrings.t('queue.loop')),
                      selected: playback.isLoop,
                      selectedColor: AppColors.info.withValues(alpha: 0.15),
                      checkmarkColor: AppColors.info,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        playback.toggleLoop();
                      },
                    ),
                    if (queue.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      ActionChip(
                        avatar: const Icon(Icons.clear_all_rounded, size: 16),
                        label: Text(AppStrings.t('queue.clear')),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          playback.clearQueue();
                        },
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 10),
              const Divider(height: 1),

              // Queue items list
              Expanded(
                child: queue.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.queue_music_rounded,
                                size: 54,
                                color: isDark
                                    ? Colors.white24
                                    : AppColors.borderSubtle,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                AppStrings.t('queue.emptyTitle'),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                AppStrings.t('queue.emptySubtitle'),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                        itemCount: queue.length,
                        onReorder: (oldIdx, newIdx) {
                          HapticFeedback.selectionClick();
                          playback.reorderQueue(oldIdx, newIdx);
                        },
                        itemBuilder: (context, index) {
                          final video = queue[index];
                          final isCurrent = index == currentIdx;

                          return Container(
                            key: ValueKey(video.id),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? (isDark
                                      ? AppColors.primaryPink
                                          .withValues(alpha: 0.16)
                                      : AppColors.primaryLight)
                                  : (isDark
                                      ? const Color(0xFF221E2C)
                                      : AppColors.surfaceAlt),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isCurrent
                                    ? AppColors.primaryPink
                                    : (isDark
                                        ? AppColors.darkBorder
                                        : AppColors.border),
                                width: isCurrent ? 1.5 : 1.0,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.pop(context);
                                  onSelectVideo(video);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Row(
                                    children: [
                                      // Drag handle indicator
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: const Padding(
                                          padding: EdgeInsets.only(
                                            right: 8,
                                            left: 2,
                                          ),
                                          child: Icon(
                                            Icons.drag_indicator_rounded,
                                            size: 20,
                                            color: AppColors.textLight,
                                          ),
                                        ),
                                      ),

                                      // Thumbnail
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: SizedBox(
                                          width: 80,
                                          height: 48,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              if (video.thumbnailUrl != null)
                                                Image.network(
                                                  video.thumbnailUrl!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder:
                                                      (_, _, _) => Container(
                                                    color: AppColors.borderSubtle,
                                                    child: const Icon(
                                                      Icons.videocam_outlined,
                                                      size: 24,
                                                    ),
                                                  ),
                                                )
                                              else
                                                Container(
                                                  color: AppColors.borderSubtle,
                                                  child: const Icon(
                                                    Icons.videocam_outlined,
                                                    size: 24,
                                                  ),
                                                ),
                                              if (video.duration > 0)
                                                Positioned(
                                                  right: 4,
                                                  bottom: 4,
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 1,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black87,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      _formatDuration(
                                                        video.duration,
                                                      ),
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      const SizedBox(width: 10),

                                      // Video Info
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (isCurrent)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                  bottom: 2,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 1,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.primaryPink,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  AppStrings.t('queue.nowPlaying'),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 9,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            Text(
                                              video.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: isCurrent
                                                    ? FontWeight.w800
                                                    : FontWeight.w600,
                                                color: isCurrent
                                                    ? AppColors.primaryPink
                                                    : null,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              video.channelName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: AppColors.textMuted,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Remove button
                                      IconButton(
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                        ),
                                        tooltip: AppStrings.t('common.delete'),
                                        onPressed: () {
                                          HapticFeedback.lightImpact();
                                          playback.removeFromQueue(index);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
