import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import 'moderation_service.dart';

Future<void> showContentReportDialog(
  BuildContext context, {
  required AuthController auth,
  required String targetType,
  required String targetId,
}) async {
  if (!auth.authenticated) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đăng nhập để gửi báo cáo.')));
    return;
  }
  final service = ModerationService(auth);
  try {
    final types = await service.violationTypes();
    if (!context.mounted) return;
    if (types.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hiện chưa có lý do báo cáo khả dụng.')),
      );
      return;
    }
    final description = TextEditingController();
    String? selected = '${types.first['violationTypeId'] ?? ''}';
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, refresh) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Báo cáo ${_targetLabel(targetType)}',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text('Chọn lý do phù hợp và mô tả ngắn gọn sự việc.'),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'Lý do'),
                items: [
                  for (final type in types)
                    DropdownMenuItem(
                      value: '${type['violationTypeId'] ?? ''}',
                      child: Text('${type['name'] ?? type['code'] ?? 'Khác'}'),
                    ),
                ],
                onChanged: (value) => refresh(() => selected = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                minLines: 3,
                maxLines: 5,
                maxLength: 1000,
                onChanged: (_) => refresh(() {}),
                decoration: const InputDecoration(
                  labelText: 'Mô tả',
                  hintText: 'Cho chúng tôi biết nội dung vi phạm ở đâu…',
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: selected == null || description.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(sheetContext, true),
                child: const Text('Gửi báo cáo'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext, false),
                child: Text(AppStrings.t('common.cancel')),
              ),
            ],
          ),
        ),
      ),
    );
    if (submitted != true || selected == null || !context.mounted) {
      description.dispose();
      return;
    }
    try {
      final details = description.text.trim();
      switch (targetType) {
        case 'video':
          await service.reportVideo(
            videoId: targetId,
            violationTypeId: selected!,
            description: details,
          );
        case 'channel':
          await service.reportChannel(
            channelId: targetId,
            violationTypeId: selected!,
            description: details,
          );
        case 'comment':
          await service.reportComment(
            commentId: targetId,
            violationTypeId: selected!,
            description: details,
          );
        default:
          await service.createReport(
            targetType: targetType,
            targetId: targetId,
            violationTypeId: selected!,
            description: details,
          );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã gửi báo cáo. Cảm ơn bạn đã phản hồi.'),
          ),
        );
      }
    } on ApiFailure catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
      }
    } finally {
      description.dispose();
    }
  } on ApiFailure catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
    }
  }
}

String _targetLabel(String targetType) => switch (targetType) {
  'video' => 'video',
  'channel' => 'kênh',
  'comment' => 'bình luận',
  _ => 'nội dung',
};
