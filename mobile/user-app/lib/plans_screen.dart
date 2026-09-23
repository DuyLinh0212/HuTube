import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'auth.dart';
import 'core/localization/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/hutube_widgets.dart';
import 'features/payments/payment_service.dart';
import 'features/plans/plan_service.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({
    super.key,
    required this.auth,
    this.invitationId,
    this.invitationToken,
  });

  final AuthController auth;
  final String? invitationId;
  final String? invitationToken;

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  late final PlanService _planService = PlanService(widget.auth);
  late final PaymentService _paymentService = PaymentService(widget.auth);
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _payments = [];
  Map<String, dynamic>? _myPlan;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.invitationId != null && widget.invitationToken != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _acceptInvitation());
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final plans = await _planService.catalogue();
      Map<String, dynamic>? myPlan;
      var payments = <Map<String, dynamic>>[];
      if (widget.auth.authenticated) {
        try {
          myPlan = await _planService.myPlan();
        } on ApiFailure {
          // The public plan catalogue remains usable if the private quota
          // snapshot is temporarily unavailable.
        }
        try {
          payments = await _paymentService.mine();
        } on ApiFailure {
          // Payment history is optional for the public plan catalogue.
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _plans = plans;
        _myPlan = myPlan;
        _payments = payments;
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
      Map<String, dynamic>? plan;
      for (final item in _plans) {
        if ('${item['planId']}' == planId) {
          plan = item;
          break;
        }
      }
      final price = _number(plan?['price']);
      if (price > 0) {
        final payment = await _paymentService.initiate(planId);
        if (!mounted) return;
        final paid = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              _PaymentDialog(payment: payment, service: _paymentService),
        );
        if (paid == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Thanh toán đã được xác nhận.')),
            );
          }
        }
      } else {
        await _planService.subscribe(planId);
      }
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
      final share = await _planService.share('${plan['planId']}');
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
      await _planService.invite(trimmed);
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

  Future<void> _acceptInvitation() async {
    final id = widget.invitationId;
    final token = widget.invitationToken;
    if (id == null || token == null || !widget.auth.authenticated) return;
    try {
      await _planService.acceptInvitation(id, token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã chấp nhận lời mời gói dịch vụ.')),
        );
        await _load();
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
      }
    }
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final id = '${member['planMemberId'] ?? ''}';
    if (id.isEmpty) return;
    try {
      await _planService.removeMember(id);
      await _load();
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
      }
    }
  }

  Future<void> _editMemberStorage(Map<String, dynamic> member) async {
    final controller = TextEditingController(
      text: '${member['allocatedStorage'] ?? ''}',
    );
    final raw = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dung lượng thành viên'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Byte (để trống dùng mặc định)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppStrings.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(AppStrings.t('common.save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (raw == null) return;
    final value = int.tryParse(raw.trim());
    if (raw.trim().isNotEmpty && value == null) return;
    try {
      await _planService.updateMemberStorage(
        '${member['planMemberId']}',
        value,
      );
      await _load();
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
      }
    }
  }

  Future<void> _editOwnerStorage() async {
    final controller = TextEditingController(
      text: '${_myPlan?['ownerAllocatedStorage'] ?? ''}',
    );
    final raw = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dung lượng của bạn'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Byte (để trống dùng mặc định)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppStrings.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(AppStrings.t('common.save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (raw == null) return;
    final value = int.tryParse(raw.trim());
    if (raw.trim().isNotEmpty && value == null) return;
    try {
      await _planService.updateOwnerStorage(value);
      await _load();
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
      }
    }
  }

  Future<void> _showPaymentDetails(String paymentId) async {
    try {
      final payment = await _paymentService.get(paymentId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${payment['planName'] ?? 'Giao dịch'}'),
          content: Text(
            'Mã: ${payment['transactionCode'] ?? '—'}\nTrạng thái: ${payment['status'] ?? '—'}\nSố tiền: ${payment['amount'] ?? '—'} ${payment['currency'] ?? ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
      }
    }
  }

  Future<void> _showPlanDetails(String planId) async {
    try {
      final plan = await _planService.get(planId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${plan['name'] ?? 'Gói HuTube'}'),
          content: SingleChildScrollView(
            child: Text(
              '${plan['description'] ?? ''}\n\n'
              'Giá: ${plan['price'] ?? 0}\n'
              'Thời hạn: ${plan['durationDays'] ?? 0} ngày\n'
              'Dung lượng: ${_formatBytes(plan['storageLimit'])}\n'
              'Dung lượng mỗi video tối đa: ${_formatBytes(plan['maxUploadSize'])}\n'
              'Thời lượng tối đa: ${plan['maxVideoDuration'] ?? 0} giây\n'
              'Chất lượng video: ${plan['maxVideoQuality'] ?? '—'}\n'
              'Thành viên: ${plan['maxMembers'] ?? 1}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
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
    final members = (plan['members'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

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
                onPressed: _editOwnerStorage,
                icon: const Icon(Icons.storage_outlined),
                label: const Text('Điều chỉnh dung lượng của bạn'),
              ),
              OutlinedButton.icon(
                onPressed: _inviteMember,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(AppStrings.t('plans.invite')),
              ),
            ],
            if (members.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Thành viên gói',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              for (final member in members)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    '${member['memberEmail'] ?? 'Thành viên'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${member['status'] ?? ''} · ${_formatBytes(member['allocatedStorage'] ?? 0)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .65),
                    ),
                  ),
                  trailing: plan['isSharedMember'] == true
                      ? null
                      : PopupMenuButton<String>(
                          iconColor: Colors.white,
                          onSelected: (choice) {
                            if (choice == 'storage') _editMemberStorage(member);
                            if (choice == 'remove') _removeMember(member);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'storage',
                              child: Text('Sửa dung lượng'),
                            ),
                            PopupMenuItem(
                              value: 'remove',
                              child: Text('Xóa thành viên'),
                            ),
                          ],
                        ),
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
          if (_payments.isNotEmpty) ...[
            HuTubeSectionHeader(
              title: 'Lịch sử thanh toán',
              subtitle: 'Theo dõi trạng thái các giao dịch gói dịch vụ.',
            ),
            const SizedBox(height: 8),
            for (final payment in _payments.take(5))
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.receipt_long_outlined,
                    color: AppColors.violet,
                  ),
                  title: Text('${payment['planName'] ?? 'Gói dịch vụ'}'),
                  subtitle: Text(
                    '${payment['transactionCode'] ?? ''} · ${payment['status'] ?? ''}',
                  ),
                  trailing: Text(
                    '${payment['amount'] ?? ''} ${payment['currency'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  onTap: () =>
                      _showPaymentDetails('${payment['paymentId'] ?? ''}'),
                ),
              ),
            const SizedBox(height: 12),
          ],
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
              onDetails: () => _showPlanDetails('${entry.value['planId']}'),
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
    required this.onDetails,
    required this.onSubscribe,
    required this.formatBytes,
    required this.qualityText,
    required this.featureText,
  });
  final Map<String, dynamic> plan;
  final int index;
  final VoidCallback onShare;
  final VoidCallback onDetails;
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
              InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: onDetails,
                child: HuTubePill(
                  label: AppStrings.t('plans.details'),
                  color: accent.withValues(alpha: .13),
                  textColor: accent,
                ),
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

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.payment, required this.service});
  final Map<String, dynamic> payment;
  final PaymentService service;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late Map<String, dynamic> _payment = widget.payment;
  Timer? _pollTimer;
  bool _checking = false;

  String get _status => '${_payment['status'] ?? 'pending'}'.toLowerCase();
  bool get _paid =>
      _status == 'paid' || _status == 'completed' || _status == 'success';
  bool get _expired =>
      _status == 'expired' || _status == 'cancelled' || _status == 'failed';

  @override
  void initState() {
    super.initState();
    if (!_paid && !_expired) {
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final latest = await widget.service.get('${widget.payment['paymentId']}');
      if (!mounted) return;
      setState(() => _payment = latest);
      if (_paid || _expired) _pollTimer?.cancel();
    } on ApiFailure {
      // Keep the pending payment visible; the user can retry by reopening it.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_paid ? 'Đã nhận thanh toán' : 'Thanh toán gói HuTube'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 540),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_paid)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 64,
                ),
              )
            else if (_expired)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.danger,
                  size: 56,
                ),
              )
            else if ('${_payment['qrCodeUrl'] ?? ''}'.startsWith('http'))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Image.network(
                  '${_payment['qrCodeUrl']}',
                  width: 210,
                  height: 210,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 210,
                    height: 210,
                    child: Icon(Icons.qr_code_2_rounded, size: 100),
                  ),
                ),
              ),
            Text(
              '${_payment['planName'] ?? 'Gói dịch vụ'}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            Text(
              '${_payment['amount'] ?? ''} ${_payment['currency'] ?? ''}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              '${_payment['transactionCode'] ?? ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: '${_payment['transactionCode'] ?? ''}'),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Đã sao chép nội dung chuyển khoản.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 17),
              label: const Text('Sao chép nội dung'),
            ),
            const SizedBox(height: 8),
            Text(
              _paid
                  ? 'Gói của bạn đã được kích hoạt.'
                  : _expired
                  ? 'Giao dịch đã hết hạn hoặc không thành công.'
                  : 'Quét mã để chuyển khoản. Ứng dụng tự kiểm tra kết quả mỗi vài giây.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_checking && !_paid && !_expired) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
        ),
      ),
    ),
    actions: [
      if (!_paid && !_expired)
        TextButton(onPressed: _poll, child: const Text('Kiểm tra ngay')),
      TextButton(
        onPressed: () => Navigator.pop(context, _paid),
        child: Text(_paid ? 'Hoàn tất' : 'Đóng'),
      ),
    ],
  );
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
