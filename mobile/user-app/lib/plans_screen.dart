import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'auth.dart';

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
          _error = error.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Không thể tải gói dịch vụ.';
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
          const SnackBar(content: Text('Đăng ký gói thành công.')),
        );
        await _load();
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
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
          '${plan['name'] ?? 'Gói HuTube'}\n$url',
          subject: 'Gói ${plan['name'] ?? 'HuTube'}',
        );
      } catch (_) {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Thiết bị chưa hỗ trợ chia sẻ. Đã sao chép liên kết gói.',
              ),
            ),
          );
        }
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
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
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  Map<String, dynamic> _features(dynamic raw) => raw is Map
      ? raw.map((key, value) => MapEntry(key.toString(), value))
      : <String, dynamic>{};

  String _featureText(Map<String, dynamic> plan) {
    final features = _features(plan['features']);
    final labels = <String>[];
    if (features['download'] == true) labels.add('Tải xuống');
    if (features['background_play'] == true) labels.add('Phát nền');
    if (features['pip'] == true) labels.add('PiP');
    return labels.isEmpty ? 'Không có quyền lợi nâng cao' : labels.join(' · ');
  }

  String _qualityText(Map<String, dynamic> plan) {
    final upload = plan['maxVideoQuality'] as String? ?? '720p';
    final download = plan['maxDownloadQuality'] as String? ?? upload;
    return 'Upload $upload · tải xuống $download';
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
              'Gói hiện tại: ${plan['name'] as String? ?? 'HuTube'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Dung lượng đã dùng'),
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
              'Còn lại ${_formatBytes(remaining)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (endedAt.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                'Hết hạn: $endedAt',
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
      return Center(child: Text(_error!));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Gói dịch vụ',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Chọn gói phù hợp với kênh và chia sẻ thông tin gói bằng liên kết công khai.',
          ),
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
                      plan['name'] as String? ?? 'Gói HuTube',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      plan['description'] as String? ??
                          'Gói dành cho nhà sáng tạo.',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${_formatBytes(plan['storageLimit'])} · tối đa ${plan['maxMembers'] ?? 1} thành viên',
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
                          label: const Text('Chia sẻ'),
                        ),
                        if (widget.auth.authenticated)
                          FilledButton(
                            onPressed: () =>
                                _subscribe(plan['planId'] as String),
                            child: const Text('Đăng ký'),
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
