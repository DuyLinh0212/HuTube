import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  List<Map<String, dynamic>> _plans = [];
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
      if (!mounted) return;
      setState(() {
        final rawPlans = result is List ? List<dynamic>.from(result) : <dynamic>[];
        _plans = rawPlans.map((item) => Map<String, dynamic>.from(item as Map)).toList();
        _loading = false;
      });
    } on ApiFailure catch (error) {
      if (mounted) setState(() { _error = error.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Không thể tải gói dịch vụ.'; _loading = false; });
    }
  }

  Future<void> _subscribe(String planId) async {
    try {
      await widget.auth.protected('POST', '/plans/$planId/subscribe', body: {'autoRenew': false});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đăng ký gói thành công.')));
    } on ApiFailure catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _copyShare(String planId) async {
    final share = await widget.auth.api.request('GET', '/plans/$planId/share');
    final url = share['shareUrl'] as String?;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã sao chép liên kết gói.')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Gói dịch vụ', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text('Chọn gói phù hợp với kênh và chia sẻ thông tin gói bằng liên kết công khai.'),
          const SizedBox(height: 20),
          ..._plans.map((plan) => Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(plan['name'] as String? ?? 'Gói HuTube', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(plan['description'] as String? ?? 'Gói dành cho nhà sáng tạo.'),
                const SizedBox(height: 12),
                Text('${plan['storageLimit'] ?? 0} MB · tối đa ${plan['maxMembers'] ?? 1} thành viên'),
                const SizedBox(height: 12),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(onPressed: () => _copyShare(plan['planId'] as String), icon: const Icon(Icons.share_outlined), label: const Text('Chia sẻ')),
                  if (widget.auth.authenticated) FilledButton(onPressed: () => _subscribe(plan['planId'] as String), child: const Text('Đăng ký')),
                ]),
              ]),
            ),
          )),
        ],
      ),
    );
  }
}