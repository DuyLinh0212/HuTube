import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../content_models.dart';

/// Owned by the watch route, so this notice cannot leak into the next video.
class AutoplayNextNotice extends StatelessWidget {
  const AutoplayNextNotice({
    super.key,
    required this.video,
    required this.onCancel,
  });

  final VideoCard video;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Material(
          color: colors.surfaceContainerHigh,
          elevation: 8,
          shadowColor: colors.shadow.withValues(alpha: .18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colors.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(seconds: 2),
            builder: (context, elapsed, _) {
              final seconds = ((1 - elapsed) * 2).ceil().clamp(1, 2);
              final copy = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppStrings.format('watch.autoPlayingNext', {
                      'seconds': '$seconds',
                    }),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              );
              final cancel = TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: colors.onSurfaceVariant,
                  minimumSize: const Size(64, 48),
                ),
                onPressed: onCancel,
                child: Text(AppStrings.t('common.cancel')),
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 300 ||
                            MediaQuery.textScalerOf(context).scale(14) > 20) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              copy,
                              Align(
                                alignment: Alignment.centerRight,
                                child: cancel,
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            ExcludeSemantics(
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: colors.onSurface,
                                  size: 28,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: copy),
                            const SizedBox(width: 8),
                            cancel,
                          ],
                        );
                      },
                    ),
                  ),
                  ExcludeSemantics(
                    child: LinearProgressIndicator(
                      value: MediaQuery.disableAnimationsOf(context)
                          ? seconds / 2
                          : 1 - elapsed,
                      minHeight: 3,
                      color: colors.primary,
                      backgroundColor: colors.surfaceContainerHighest,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
