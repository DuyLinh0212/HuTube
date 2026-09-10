import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

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
    final deviceName = session['deviceName'] as String? ?? 'Thiết bị không rõ';
    final ipAddress = session['ipAddress'] as String? ?? 'Chưa rõ IP';
    final lastActiveAt = session['lastActiveAt'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent
              ? AppColors.primaryPink.withValues(alpha: 0.5)
              : AppColors.cardBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isCurrent
                  ? AppColors.primaryPink.withValues(alpha: 0.15)
                  : AppColors.cardBorder.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              deviceName.toLowerCase().contains('mobile') ||
                      deviceName.toLowerCase().contains('phone') ||
                      deviceName.toLowerCase().contains('ios') ||
                      deviceName.toLowerCase().contains('android')
                  ? Icons.smartphone
                  : Icons.laptop,
              color: isCurrent ? AppColors.primaryPink : AppColors.textSecondary,
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
                        style: const TextStyle(
                          color: AppColors.textPrimary,
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
                        child: const Text(
                          'Hiện tại',
                          style: TextStyle(
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
                  '$ipAddress ${lastActiveAt.isNotEmpty ? '• Hoạt động: ${_formatDate(lastActiveAt)}' : ''}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
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
                  : const Icon(
                      Icons.delete_outline,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
              tooltip: 'Thu hồi phiên này',
              onPressed: isRevoking ? null : onRevoke,
            ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
