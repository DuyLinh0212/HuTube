import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../channel/services/channel_service.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'moderation_service.dart';

class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  late final ModerationService _service = ModerationService(widget.auth);
  List<Map<String, dynamic>> _appeals = const [];
  Map<String, dynamic>? _strikes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final appeals = await _service.myAppeals();
      Map<String, dynamic>? strikes;
      try {
        final channel = await ChannelService(widget.auth).getMyChannel();
        if (channel != null)
          strikes = await _service.channelStrikes(channel.id);
      } on ApiFailure catch (error) {
        if (error.status != 404) rethrow;
      }
      if (mounted)
        setState(() {
          _appeals = appeals;
          _strikes = strikes;
          _loading = false;
        });
    } on ApiFailure catch (error) {
      if (mounted)
        setState(() {
          _error = AppStrings.apiError(error, fallback: 'common.error');
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _error = AppStrings.t('common.networkError');
          _loading = false;
        });
    }
  }

  Future<void> _createAppeal() async {
    final targetId = TextEditingController();
    final reason = TextEditingController();
    final evidenceUrl = TextEditingController();
    final evidenceNote = TextEditingController();
    var targetType = 'video';
    final form = await showModalBottomSheet<bool>(
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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Gửi kháng nghị',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: targetType,
                  decoration: const InputDecoration(labelText: 'Loại nội dung'),
                  items: const [
                    DropdownMenuItem(value: 'video', child: Text('Video')),
                    DropdownMenuItem(value: 'channel', child: Text('Kênh')),
                    DropdownMenuItem(
                      value: 'comment',
                      child: Text('Bình luận'),
                    ),
                    DropdownMenuItem(
                      value: 'strike',
                      child: Text('Cảnh cáo kênh'),
                    ),
                  ],
                  onChanged: (value) =>
                      refresh(() => targetType = value ?? 'video'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: targetId,
                  onChanged: (_) => refresh(() {}),
                  decoration: const InputDecoration(
                    labelText: 'ID nội dung',
                    hintText: 'UUID của video, kênh hoặc cảnh cáo',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reason,
                  minLines: 3,
                  maxLines: 5,
                  onChanged: (_) => refresh(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Lý do kháng nghị',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: evidenceUrl,
                  decoration: const InputDecoration(
                    labelText: 'Link bằng chứng (không bắt buộc)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: evidenceNote,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú bằng chứng (không bắt buộc)',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed:
                      targetId.text.trim().isEmpty || reason.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(sheetContext, true),
                  child: const Text('Gửi kháng nghị'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: Text(AppStrings.t('common.cancel')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (form != true) {
      targetId.dispose();
      reason.dispose();
      evidenceUrl.dispose();
      evidenceNote.dispose();
      return;
    }
    try {
      await _service.createAppeal(
        targetType: targetType,
        targetId: targetId.text.trim(),
        reason: reason.text.trim(),
        evidenceUrl: evidenceUrl.text,
        evidenceNote: evidenceNote.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã gửi kháng nghị.')));
        await _load();
      }
    } on ApiFailure catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
    } finally {
      targetId.dispose();
      reason.dispose();
      evidenceUrl.dispose();
      evidenceNote.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return HuTubeStateView(
        icon: Icons.gavel_rounded,
        title: _error!,
        message: AppStrings.t('common.networkError'),
        actionLabel: AppStrings.t('common.retry'),
        onAction: _load,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          HuTubeSectionHeader(
            title: 'Báo cáo & kháng nghị',
            subtitle: 'Theo dõi phản hồi kiểm duyệt và gửi kháng nghị.',
            action: 'Kháng nghị',
            onAction: _createAppeal,
          ),
          const SizedBox(height: 18),
          if (_strikes != null) ...[
            HuTubeSurface(
              color:
                  (_strikes!['isSuspended'] == true
                          ? AppColors.danger
                          : AppColors.violet)
                      .withValues(alpha: .08),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trạng thái kênh',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Cảnh cáo đang hiệu lực: ${_strikes!['activeStrikesCount'] ?? 0}',
                  ),
                  Text(
                    _strikes!['isSuspended'] == true
                        ? 'Kênh đang bị đình chỉ.'
                        : (_strikes!['hasWarning'] == true
                              ? 'Kênh đang có cảnh báo.'
                              : 'Kênh không có cảnh báo hoạt động.'),
                  ),
                  if (_strikes!['strikes'] is List)
                    for (final item
                        in (_strikes!['strikes'] as List).whereType<Map>())
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          '• ${item['reason'] ?? 'Cảnh cáo'} · ${item['severity'] ?? ''} · ${_date(item['createdAt'])}',
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (_appeals.isEmpty)
            HuTubeStateView(
              icon: Icons.fact_check_outlined,
              title: 'Chưa có kháng nghị',
              message:
                  'Nếu bạn cho rằng quyết định kiểm duyệt chưa chính xác, hãy gửi kháng nghị để đội ngũ xem xét.',
              actionLabel: 'Gửi kháng nghị',
              onAction: _createAppeal,
              compact: true,
              accent: AppColors.violet,
            )
          else
            for (final appeal in _appeals)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: HuTubeSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${appeal['targetTitle'] ?? appeal['targetType'] ?? 'Nội dung'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Chip(label: Text('${appeal['status'] ?? 'pending'}')),
                        ],
                      ),
                      Text('${appeal['reason'] ?? ''}'),
                      const SizedBox(height: 5),
                      Text(
                        'Gửi ngày ${_date(appeal['createdAt'])}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if ('${appeal['reviewNote'] ?? ''}'.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('Phản hồi: ${appeal['reviewNote']}'),
                      ],
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  String _date(dynamic value) =>
      DateTime.tryParse('$value')?.toLocal().toString().split('.').first ?? '—';
}
