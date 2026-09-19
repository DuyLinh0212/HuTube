import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'auth.dart';
import 'core/localization/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/hutube_widgets.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  List<Map<String, dynamic>> _plans = [];
  Map<String, dynamic>? _myPlan;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dynamic result = await widget.auth.api.request('GET', '/plans');
      Map<String, dynamic>? myPlan;
      if (widget.auth.authenticated) {
        try {
          final current = await widget.auth.protected('GET', '/plans/my-plan');
          if (current.isNotEmpty) {
            myPlan = current;
          }
        } on ApiFailure {
          // The public plan catalogue remains usable if the private quota
          // snapshot is temporarily unavailable.
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        final rawPlans = result is List
            ? List<dynamic>.from(result)
            : <dynamic>[];
        _plans = rawPlans
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _myPlan = myPlan;
        _loading = false;
      });
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = AppStrings.apiError(error, fallback: 'plans.loadError');
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppStrings.t('plans.loadError');
          _loading = false;
        });
      }
    }
  }

  Future<void> _subscribe(String planId) async {
    try {
      await widget.auth.protected(
        'POST',
        '/plans/$planId/subscribe',
        body: {'autoRenew': false},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.t('plans.subscribeSuccess'))),
        );
        await _load();
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.apiError(error, fallback: 'plans.subscribeError'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _sharePlan(Map<String, dynamic> plan) async {
    try {
      final share = await widget.auth.api.request(
        'GET',
        '/plans/${plan['planId']}/share',
      );
      final url = share['shareUrl'] as String?;
      if (url == null || url.isEmpty) {
        return;
      }
      try {
        await Share.share(
          '${plan['name'] ?? AppStrings.t('common.appName')}\n$url',
          subject: AppStrings.format('plans.shareSubject', {
            'name': plan['name'] ?? AppStrings.t('common.appName'),
          }),
        );
      } catch (_) {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppStrings.t('plans.shareCopied'))),
          );
        }
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.apiError(error, fallback: 'plans.shareError'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _inviteMember() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.t('plans.inviteDialogTitle')),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppStrings.t('plans.inviteEmail'),
            hintText: AppStrings.t('plans.inviteEmailHint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppStrings.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(AppStrings.t('common.send')),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = email?.trim() ?? '';
    if (trimmed.isEmpty) return;
    if (!trimmed.contains('@')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.t('auth.emailInvalid'))),
        );
      }
      return;
    }
    try {
      await widget.auth.protected(
        'POST',
        '/plans/members/invite',
        body: {'email': trimmed},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.t('plans.inviteSent'))),
        );
        await _load();
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.apiError(error, fallback: 'plans.inviteError'),
            ),
          ),
        );
      }
    }
  }

  String _formatBytes(dynamic raw) {
    final bytes = raw is num ? raw.toDouble() : 0;
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(bytes >= 100 * 1024 * 1024 * 1024 ? 0 : 2)} GB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  double _number(dynamic raw) =>
      raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '') ?? 0;

  String _formatDate(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) {
      return '';
    }
    return AppStrings.date(date);
  }

  Map<String, dynamic> _features(dynamic raw) => raw is Map
      ? raw.map((key, value) => MapEntry(key.toString(), value))
      : <String, dynamic>{};

  String _featureText(Map<String, dynamic> plan) {
    final features = _features(plan['features']);
    final labels = <String>[];
    if (features['download'] == true) {
      labels.add(AppStrings.t('common.download'));
    }
    if (features['background_play'] == true) {
      labels.add(AppStrings.t('watch.background'));
    }
    if (features['pip'] == true) labels.add(AppStrings.t('watch.pipAction'));
    return labels.isEmpty
        ? AppStrings.t('plans.featuresNone')
        : labels.join(' · ');
  }

  String _qualityText(Map<String, dynamic> plan) {
    final upload = plan['maxVideoQuality'] as String? ?? '720p';
    final download = plan['maxDownloadQuality'] as String? ?? upload;
    return AppStrings.format('plans.quality', {
      'upload': upload,
      'download': download,
    });
  }

  Widget _currentPlanCard(BuildContext context) {
    final plan = _myPlan;
    if (plan == null) {
      return const SizedBox.shrink();
    }

    final total = _number(plan['storageLimit']);
    final used = _number(plan['usedStorage']);
    final remaining = _number(plan['remainingStorage']);
    final progress = total <= 0
        ? 0.0
        : (used / total).clamp(0.0, 1.0).toDouble();
    final subscription = plan['subscription'] is Map
        ? Map<String, dynamic>.from(plan['subscription'] as Map)
        : null;
    final endedAt = _formatDate(subscription?['endedAt']);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.ink, Color(0xFF36263C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.format('plans.currentTitle', {
                'name':
                    plan['name'] as String? ?? AppStrings.t('common.appName'),
              }),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.t('plans.storageUsed'),
                  style: TextStyle(color: Colors.white.withValues(alpha: .75)),
                ),
                Text(
                  '${_formatBytes(used)} / ${_formatBytes(total)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            LinearProgressIndicator(
              value: progress,
              color: AppColors.primary,
              backgroundColor: Colors.white.withValues(alpha: .14),
            ),
            const SizedBox(height: 7),
            Text(
              AppStrings.format('plans.remaining', {
                'size': _formatBytes(remaining),
              }),
              style: TextStyle(color: Colors.white.withValues(alpha: .7)),
            ),
            if (endedAt.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                AppStrings.format('plans.expires', {'date': endedAt}),
                style: TextStyle(color: Colors.white.withValues(alpha: .7)),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _qualityText(plan),
              style: TextStyle(color: Colors.white.withValues(alpha: .7)),
            ),
            const SizedBox(height: 4),
            Text(
              _featureText(plan),
              style: TextStyle(color: Colors.white.withValues(alpha: .7)),
            ),
            if (plan['isSharedMember'] != true) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _inviteMember,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(AppStrings.t('plans.invite')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
        children: const [
          _PlanSkeleton(height: 150),
          SizedBox(height: 18),
          _PlanSkeleton(height: 180),
          SizedBox(height: 12),
          _PlanSkeleton(height: 180),
        ],
      );
    }
    if (_error != null) {
      return HuTubeStateView(
        icon: Icons.workspace_premium_outlined,
        title: _error!,
        message: AppStrings.t('common.networkError'),
        actionLabel: AppStrings.t('common.retry'),
        onAction: _load,
        accent: AppColors.violet,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          HuTubeSectionHeader(
            title: AppStrings.t('plans.title'),
            subtitle: AppStrings.t('plans.description'),
          ),
          const SizedBox(height: 20),
          _currentPlanCard(context),
          if (_plans.isEmpty)
            HuTubeStateView(
              icon: Icons.auto_awesome_outlined,
              title: AppStrings.t('plans.noPlans'),
              message: 'Danh mục gói hiện chưa có dữ liệu từ máy chủ.',
              compact: true,
              accent: AppColors.violet,
            ),
          ..._plans.asMap().entries.map(
            (entry) => _PlanCard(
              plan: entry.value,
              index: entry.key,
              onShare: () => _sharePlan(entry.value),
              onSubscribe: widget.auth.authenticated
                  ? () => _subscribe(entry.value['planId'] as String)
                  : null,
              formatBytes: _formatBytes,
              qualityText: _qualityText,
              featureText: _featureText,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.index,
    required this.onShare,
    required this.onSubscribe,
    required this.formatBytes,
    required this.qualityText,
    required this.featureText,
  });
  final Map<String, dynamic> plan;
  final int index;
  final VoidCallback onShare;
  final VoidCallback? onSubscribe;
  final String Function(dynamic) formatBytes;
  final String Function(Map<String, dynamic>) qualityText;
  final String Function(Map<String, dynamic>) featureText;

  @override
  Widget build(BuildContext context) {
    final accents = [AppColors.primary, AppColors.violet, AppColors.success];
    final accent = accents[index % accents.length];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan['name'] as String? ?? AppStrings.t('common.appName'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              HuTubePill(
                label: AppStrings.t('plans.details'),
                color: accent.withValues(alpha: .13),
                textColor: accent,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            plan['description'] as String? ??
                AppStrings.t('plans.defaultDescription'),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 14),
          Text(
            '${formatBytes(plan['storageLimit'])} · ${AppStrings.format('plans.maxMembers', {'count': AppStrings.number(plan['maxMembers'] ?? 1)})}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 7),
          Text(qualityText(plan), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 5),
          Text(featureText(plan), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: Text(AppStrings.t('plans.share')),
                ),
              ),
              if (onSubscribe != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: onSubscribe,
                    child: Text(AppStrings.t('plans.subscribe')),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanSkeleton extends StatelessWidget {
  const _PlanSkeleton({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: AppColors.borderSubtle,
      borderRadius: BorderRadius.circular(16),
    ),
  );
}
