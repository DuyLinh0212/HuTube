import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';

bool showPlanStorageAllocation(Map<String, dynamic> plan) =>
    plan['isSharedMember'] != true &&
    (plan['maxMembers'] as num? ?? 1) > 1 &&
    (plan['members'] as List? ?? const []).whereType<Map>().any(
      (member) =>
          member['status'] == 'pending' || member['status'] == 'accepted',
    );

bool showFamilyStorageUsage(Map<String, dynamic> plan) {
  final usage = (plan['storageUsageBreakdown'] as List? ?? const [])
      .whereType<Map>();
  return plan['isSharedMember'] != true &&
      usage.isNotEmpty &&
      ((plan['members'] as List? ?? const []).whereType<Map>().any(
            (member) => member['status'] == 'accepted',
          ) ||
          usage.any(
            (item) =>
                item['isOwner'] != true &&
                (item['storageUsed'] as num? ?? 0) > 0,
          ));
}

class FamilyStorageUsage extends StatelessWidget {
  const FamilyStorageUsage({
    super.key,
    required this.usage,
    required this.totalBytes,
    required this.usedBytes,
    this.onDark = false,
  });

  final List<Map> usage;
  final num totalBytes;
  final num usedBytes;
  final bool onDark;

  String _formatBytes(num bytes) => bytes >= 1024 * 1024 * 1024
      ? '${AppStrings.number(bytes / (1024 * 1024 * 1024))} GB'
      : '${AppStrings.number(bytes / (1024 * 1024))} MB';

  @override
  Widget build(BuildContext context) {
    const colors = [
      Color(0xFF60A5FA),
      Color(0xFF2DD4BF),
      Color(0xFFFBBF24),
      Color(0xFFA78BFA),
      Color(0xFFF472B6),
    ];
    final parts = <({String label, double bytes, Color color})>[];
    for (var i = 0; i < usage.length; i++) {
      final item = usage[i];
      final name = '${item['displayName'] ?? ''}'.trim();
      final label = item['isOwner'] == true
          ? AppStrings.t('plans.storageOwner')
          : item['userId'] == null
          ? AppStrings.t('plans.storageOther')
          : item['isFormerMember'] == true
          ? AppStrings.format('plans.storageFormerMember', {
              'name': name.isEmpty ? AppStrings.t('plans.storageMember') : name,
            })
          : name.isEmpty
          ? AppStrings.t('plans.storageMember')
          : name;
      parts.add((
        label: label,
        bytes: ((item['storageUsed'] as num?) ?? 0)
            .clamp(0, double.infinity)
            .toDouble(),
        color: item['isOwner'] == true
            ? AppColors.primary
            : colors[(i == 0 ? 0 : i - 1) % colors.length],
      ));
    }
    parts.add((
      label: AppStrings.t('plans.storageFree'),
      bytes: (totalBytes - usedBytes).clamp(0, double.infinity).toDouble(),
      color: onDark ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
    ));
    final sum = parts.fold<double>(0, (sum, part) => sum + part.bytes);
    final scale = [
      totalBytes.toDouble(),
      sum,
      1.0,
    ].reduce((a, b) => a > b ? a : b);
    final textColor = onDark
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: parts
              .map((part) => '${part.label}: ${_formatBytes(part.bytes)}')
              .join('; '),
          child: ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LayoutBuilder(
                builder: (context, bounds) => SizedBox(
                  key: const ValueKey('family-storage-bar'),
                  height: 12,
                  child: Row(
                    children: [
                      for (final part in parts.where((part) => part.bytes > 0))
                        SizedBox(
                          width: bounds.maxWidth * part.bytes / scale,
                          height: 12,
                          child: ColoredBox(color: part.color),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (final part in parts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: SizedBox(
                    width: 10,
                    height: 10,
                    child: ColoredBox(color: part.color),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    part.label,
                    style: TextStyle(color: textColor, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatBytes(part.bytes),
                  style: TextStyle(
                    color: textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
