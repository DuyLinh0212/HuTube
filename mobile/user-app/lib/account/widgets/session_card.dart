import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/app_strings.dart';

class SessionCard extends StatelessWidget {
  const SessionCard({
    super.key,
    required this.session,
    required this.onRevoke,
    this.isRevoking = false,
  });

  final Map<String, dynamic> session;
  final VoidCallback onRevoke;
  final bool isRevoking;

  @override
  Widget build(BuildContext context) {
    final isCurrent = session['isCurrent'] as bool? ?? false;
    final deviceName =
        session['deviceName'] as String? ??
        AppStrings.t('session.unknownDevice');
    final ipAddress =
        session['ipAddress'] as String? ?? AppStrings.t('session.unknownIp');
    final lastActiveAt = session['lastActiveAt'] as String? ?? '';

    final cardBg = Theme.of(context).cardColor;
    final borderColor = isCurrent
        ? AppColors.primaryPink.withValues(alpha: 0.5)
        : Theme.of(context).dividerColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isCurrent
                  ? AppColors.primaryPink.withValues(alpha: 0.15)
                  : Theme.of(context).dividerColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              deviceName.toLowerCase().contains('mobile') ||
                      deviceName.toLowerCase().contains('phone') ||
                      deviceName.toLowerCase().contains('ios') ||
                      deviceName.toLowerCase().contains('android')
                  ? Icons.smartphone
                  : Icons.laptop,
              color: isCurrent
                  ? AppColors.primaryPink
                  : AppColors.textSecondaryFor(context),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        deviceName,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryPink.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          AppStrings.t('session.current'),
                          style: const TextStyle(
                            color: AppColors.primaryPink,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$ipAddress ${lastActiveAt.isNotEmpty ? '• ${_formatDate(lastActiveAt)}' : ''}',
                  style: TextStyle(
                    color: AppColors.textMutedFor(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (!isCurrent)
            IconButton(
              icon: isRevoking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.delete_outline,
                      color: AppColors.textMutedFor(context),
                      size: 20,
                    ),
              tooltip: AppStrings.t('session.revoke'),
              onPressed: isRevoking ? null : onRevoke,
            ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return AppStrings.dateTime(dt);
    } catch (_) {
      return iso;
    }
  }
}
