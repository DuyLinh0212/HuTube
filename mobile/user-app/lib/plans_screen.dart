import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'auth.dart';
import 'core/localization/app_strings.dart';

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

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
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
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(AppStrings.t('plans.storageUsed')),
                Text(
                  '${_formatBytes(used)} / ${_formatBytes(total)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 7),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 7),
            Text(
              AppStrings.format('plans.remaining', {
                'size': _formatBytes(remaining),
              }),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (endedAt.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                AppStrings.format('plans.expires', {'date': endedAt}),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _qualityText(plan),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              _featureText(plan),
              style: Theme.of(context).textTheme.bodySmall,
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
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _load,
              child: Text(AppStrings.t('common.retry')),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            AppStrings.t('plans.title'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(AppStrings.t('plans.description')),
          const SizedBox(height: 20),
          _currentPlanCard(context),
          ..._plans.map(
            (plan) => Card(
              margin: const EdgeInsets.only(bottom: 14),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan['name'] as String? ?? AppStrings.t('common.appName'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      plan['description'] as String? ??
                          AppStrings.t('plans.defaultDescription'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${_formatBytes(plan['storageLimit'])} · ${AppStrings.format('plans.maxMembers', {'count': AppStrings.number(_number(plan['maxMembers'] ?? 1))})}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _qualityText(plan),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _featureText(plan),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _sharePlan(plan),
                          icon: const Icon(Icons.share_outlined),
                          label: Text(AppStrings.t('plans.share')),
                        ),
                        if (widget.auth.authenticated)
                          FilledButton(
                            onPressed: () =>
                                _subscribe(plan['planId'] as String),
                            child: Text(AppStrings.t('plans.subscribe')),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
