import 'package:flutter/material.dart';
import 'appeal_evidence.dart';
import 'appeal_composer.dart';
import '../../channel/models/channel_models.dart';

import '../../auth.dart';
import '../../channel/services/channel_service.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'moderation_service.dart';

class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key, required this.auth, this.channel});
  final AuthController auth;
  final ChannelDetail? channel;

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  late final ModerationService _service = ModerationService(widget.auth);
  List<Map<String, dynamic>> _appeals = const [];
  Map<String, dynamic>? _strikes;
  ChannelDetail? _channel;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final appeals = await _service.myAppeals();
      Map<String, dynamic>? strikes;
      try {
        final channel =
            widget.channel ?? await ChannelService(widget.auth).getMyChannel();
        _channel = channel;
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
    final result = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => AppealComposer(
        auth: widget.auth,
        targetId: (_channel ?? widget.channel)?.id ?? '',
        targetLabel: (_channel ?? widget.channel)?.name ?? '',
        targetType: (_channel ?? widget.channel) == null ? 'video' : 'channel',
      ),
    );
    if (result == true && mounted) await _load();
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
          Text(
            AppStrings.t('moderation.title'),
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.t('moderation.subtitle'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textMutedFor(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          if (_strikes != null || _channel != null) ...[
            _statusCard(),
            const SizedBox(height: 24),
          ],
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                AppStrings.t('moderation.appealsHeading'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              FilledButton.tonalIcon(
                onPressed: _createAppeal,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(AppStrings.t('moderation.sendAppeal')),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_appeals.isEmpty)
            HuTubeStateView(
              icon: Icons.fact_check_outlined,
              title: AppStrings.t('moderation.noAppeals'),
              message: AppStrings.t('moderation.noAppealsDescription'),
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
                          const SizedBox(width: 8),
                          Chip(
                            label: Text(
                              _appealStatus('${appeal['status'] ?? 'pending'}'),
                            ),
                          ),
                        ],
                      ),
                      Text('${appeal['reason'] ?? ''}'),
                      if ('${appeal['evidenceUrl'] ?? ''}'.isNotEmpty)
                        AppealEvidence(
                          key: ValueKey('evidence-${appeal['appealId']}'),
                          auth: widget.auth,
                          appealId: '${appeal['appealId']}',
                        ),
                      const SizedBox(height: 5),
                      Text(
                        AppStrings.format('moderation.appealDate', {
                          'date': _date(appeal['createdAt']),
                        }),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if ('${appeal['reviewNote'] ?? ''}'.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          AppStrings.format('moderation.reviewNote', {
                            'note': appeal['reviewNote'],
                          }),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final colors = Theme.of(context).colorScheme;
    final suspended =
        _strikes?['isSuspended'] == true || _channel?.status == 'suspended';
    final strikes =
        (_strikes?['strikes'] is List ? _strikes!['strikes'] as List : const [])
            .whereType<Map>()
            .toList();
    final count = _strikes?['activeStrikesCount'] is num
        ? _strikes!['activeStrikesCount'] as num
        : 0;
    final tint = suspended
        ? colors.error
        : count > 0
        ? colors.tertiary
        : colors.primary;
    return HuTubeSurface(
      color: colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  suspended
                      ? Icons.pause_circle_outline_rounded
                      : Icons.verified_user_outlined,
                  color: tint,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.t('moderation.channelStatus'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _channel?.name ?? '',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMutedFor(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      AppStrings.t(
                        suspended
                            ? 'channel.suspendedTitle'
                            : count > 0
                            ? 'moderation.hasWarning'
                            : 'moderation.status.active',
                      ),
                      style: TextStyle(
                        color: tint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Text(
            AppStrings.format('moderation.activeWarnings', {
              'count': AppStrings.number(count),
            }),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          for (final item in strikes)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: tint),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item['reason'] ?? AppStrings.t('moderation.warning')}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${_severity('${item['severity'] ?? ''}')} · ${_date(item['createdAt'])}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.textMutedFor(context),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _severity(String value) {
    final key = 'moderation.severity.${value.toLowerCase()}';
    final translated = AppStrings.t(key);
    return translated == key ? AppStrings.t('moderation.warning') : translated;
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
