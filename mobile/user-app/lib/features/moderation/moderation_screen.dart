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
        if (channel != null) {
          strikes = await _service.channelStrikes(channel.id);
        }
      } on ApiFailure catch (error) {
        if (error.status != 404) rethrow;
      }
      if (mounted) {
        setState(() {
          _appeals = appeals;
          _strikes = strikes;
          _loading = false;
        });
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = AppStrings.apiError(error, fallback: 'common.error');
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppStrings.t('common.networkError');
          _loading = false;
        });
      }
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
                  AppStrings.t('moderation.sendAppeal'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: targetType,
                  decoration: InputDecoration(labelText: AppStrings.t('moderation.targetType')),
                  items: [
                    DropdownMenuItem(value: 'video', child: Text(AppStrings.t('moderation.target.video'))),
                    DropdownMenuItem(value: 'channel', child: Text(AppStrings.t('moderation.target.channel'))),
                    DropdownMenuItem(
                      value: 'comment',
                      child: Text(AppStrings.t('moderation.target.comment')),
                    ),
                    DropdownMenuItem(
                      value: 'strike',
                      child: Text(AppStrings.t('moderation.target.strike')),
                    ),
                  ],
                  onChanged: (value) =>
                      refresh(() => targetType = value ?? 'video'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: targetId,
                  onChanged: (_) => refresh(() {}),
                  decoration: InputDecoration(
                    labelText: AppStrings.t('moderation.targetId'),
                    hintText: AppStrings.t('moderation.targetIdHint'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reason,
                  minLines: 3,
                  maxLines: 5,
                  onChanged: (_) => refresh(() {}),
                  decoration: InputDecoration(
                    labelText: AppStrings.t('moderation.appealReason'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: evidenceUrl,
                  decoration: InputDecoration(
                    labelText: AppStrings.t('moderation.evidenceUrl'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: evidenceNote,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: AppStrings.t('moderation.evidenceNote'),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed:
                      targetId.text.trim().isEmpty || reason.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(sheetContext, true),
                  child: Text(AppStrings.t('moderation.sendAppeal')),
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
        ).showSnackBar(SnackBar(content: Text(AppStrings.t('moderation.appealSent'))));
        await _load();
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
      }
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
            title: AppStrings.t('moderation.title'),
            subtitle: AppStrings.t('moderation.subtitle'),
            action: AppStrings.t('moderation.action'),
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
                    AppStrings.t('moderation.channelStatus'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppStrings.format('moderation.activeWarnings', {
                      'count': AppStrings.number(
                        _strikes!['activeStrikesCount'] is num
                            ? _strikes!['activeStrikesCount'] as num
                            : 0,
                      ),
                    }),
                  ),
                  Text(
                    _strikes!['isSuspended'] == true
                        ? AppStrings.t('moderation.suspended')
                        : (_strikes!['hasWarning'] == true
                              ? AppStrings.t('moderation.hasWarning')
                              : AppStrings.t('moderation.noWarning')),
                  ),
                  if (_strikes!['strikes'] is List)
                    for (final item
                        in (_strikes!['strikes'] as List).whereType<Map>())
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          '• ${item['reason'] ?? AppStrings.t('moderation.warning')} · ${item['severity'] ?? ''} · ${_date(item['createdAt'])}',
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
              title: AppStrings.t('moderation.noAppeals'),
              message: AppStrings.t('moderation.noAppealsDescription'),
              actionLabel: AppStrings.t('moderation.sendAppeal'),
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
                              '${appeal['targetTitle'] ?? _targetTypeLabel('${appeal['targetType'] ?? ''}')}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Chip(label: Text(_appealStatus('${appeal['status'] ?? 'pending'}'))),
                        ],
                      ),
                      Text('${appeal['reason'] ?? ''}'),
                      const SizedBox(height: 5),
                      Text(
                        AppStrings.format('moderation.appealDate', {'date': _date(appeal['createdAt'])}),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if ('${appeal['reviewNote'] ?? ''}'.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(AppStrings.format('moderation.reviewNote', {'note': appeal['reviewNote']})),
                      ],
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  String _targetTypeLabel(String value) {
    final key = switch (value.toLowerCase()) {
      'video' => 'moderation.target.video',
      'channel' => 'moderation.target.channel',
      'comment' => 'moderation.target.comment',
      'strike' => 'moderation.target.strike',
      _ => 'moderation.targetFallback',
    };
    return AppStrings.t(key);
  }

  String _appealStatus(String value) {
    final key = 'moderation.status.${value.toLowerCase()}';
    final translated = AppStrings.t(key);
    return translated == key ? value : translated;
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse('$value');
    return date == null ? '—' : AppStrings.dateTime(date.toLocal());
  }
}
