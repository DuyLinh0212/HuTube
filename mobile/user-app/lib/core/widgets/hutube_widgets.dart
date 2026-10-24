import 'scrollable_sheet.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class HuTubeSectionHeader extends StatelessWidget {
  const HuTubeSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.onAction,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth < 380 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
                (compact
                        ? Theme.of(context).textTheme.titleMedium
                        : Theme.of(context).textTheme.titleLarge)
                    ?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: compact ? -.2 : -.35,
                      fontSize: compact ? 18 : null,
                    ),
          ),
          if (subtitle != null) ...[
            SizedBox(height: compact ? 2 : 3),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondaryFor(context),
                height: 1.5,
              ),
            ),
          ],
        ],
      );
      final button = action == null
          ? null
          : TextButton(onPressed: onAction, child: Text(action!));
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, ?button],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: heading),
          ?button,
        ],
      );
    },
  );
}

class HuTubeSurface extends StatelessWidget {
  const HuTubeSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderRadius = 14,
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double borderRadius;
  final BorderSide? border;

  @override
  Widget build(BuildContext context) => Material(
    color: color ?? AppColors.surfaceFor(context),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      side: border ?? BorderSide(color: AppColors.borderFor(context)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class HuTubePill extends StatelessWidget {
  const HuTubePill({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.textColor,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final foreground = textColor ?? AppColors.textSecondaryFor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color ?? AppColors.surfaceAltFor(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HuTubeStateView extends StatelessWidget {
  const HuTubeStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.primary;
    return HuTubeScrollable(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: EdgeInsets.symmetric(
            horizontal: 24,
            vertical: compact ? 28 : 48,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 58 : 72,
                height: compact ? 58 : 72,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: compact ? 27 : 34, color: color),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (message != null) ...[
                const SizedBox(height: 7),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondaryFor(context),
                    height: 1.5,
                  ),
                ),
              ],
              if (actionLabel != null) ...[
                const SizedBox(height: 18),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class HuTubeMetricCard extends StatelessWidget {
  const HuTubeMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppColors.violet,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: .16)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(height: 16),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class HuTubeAvatar extends StatelessWidget {
  const HuTubeAvatar({
    super.key,
    this.url,
    this.label = 'H',
    this.radius = 20,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String? url;
  final String label;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final cleanLabel = label.trim();
    final fallback = Center(
      child: Text(
        cleanLabel.isEmpty ? 'H' : cleanLabel.characters.first.toUpperCase(),
        style: TextStyle(
          color: foregroundColor ?? Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w800,
          fontSize: radius * .72,
        ),
      ),
    );
    final uri = Uri.tryParse(url ?? '');
    final hasImage =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    return SizedBox.square(
      dimension: radius * 2,
      child: ClipOval(
        child: ColoredBox(
          color:
              backgroundColor ??
              Theme.of(context).colorScheme.primary.withValues(alpha: .12),
          child: hasImage
              ? Image.network(
                  url!,
                  fit: BoxFit.cover,
                  cacheWidth: (radius * 4).round().clamp(48, 256),
                  cacheHeight: (radius * 4).round().clamp(48, 256),
                  errorBuilder: (_, _, _) => fallback,
                  frameBuilder: (_, child, frame, _) =>
                      frame == null ? fallback : child,
                )
              : fallback,
        ),
      ),
    );
  }
}

/// Static placeholders respect reduced motion and use the active theme.
class HuTubeSkeleton extends StatelessWidget {
  const HuTubeSkeleton({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
  });
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.skeletonFor(context),
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
  );
}

/// Recoverable failures keep already loaded content visible and usable.
class HuTubeNotice extends StatelessWidget {
  const HuTubeNotice({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: HuTubeSurface(
      color: Theme.of(context).colorScheme.errorContainer,
      border: BorderSide.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(actionLabel),
          ),
        ],
      ),
    ),
  );
}
