import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../core/theme/app_theme.dart';

class PoliciesScreen extends StatefulWidget {
  const PoliciesScreen({super.key, required this.auth, this.initialGroup});
  final AuthController auth;
  final String? initialGroup;
  @override
  State<PoliciesScreen> createState() => _PoliciesScreenState();
}

class _PoliciesScreenState extends State<PoliciesScreen> {
  List<Map<String, dynamic>> _policies = [];
  bool _loading = true;
  String _group = 'guidelines';

  @override
  void initState() {
    super.initState();
    _group = widget.initialGroup ?? _group;
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.auth.api.requestList('GET', '/policies');
      if (mounted) {
        setState(() {
          _policies = list
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _policies
        .where((item) => '${item['group'] ?? ''}'.toLowerCase() == _group)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
      children: [
        Text(
          'Trung tâm chính sách',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        const Text(
          'Tiêu chuẩn giúp HuTube an toàn, rõ ràng và tôn trọng cộng đồng.',
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final item in const [
                ('guidelines', 'Cộng đồng'),
                ('privacy', 'Quyền riêng tư'),
                ('terms', 'Điều khoản'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(item.$2),
                    selected: _group == item.$1,
                    onSelected: (_) => setState(() => _group = item.$1),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primaryPink),
            ),
          )
        else if (current.isEmpty)
          const _PolicyFallback()
        else
          ...current.map(
            (policy) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${policy['title'] ?? 'Chính sách'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('${policy['description'] ?? policy['content'] ?? ''}'),
                    if (policy['version'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          'Phiên bản ${policy['version']}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PolicyFallback extends StatelessWidget {
  const _PolicyFallback();
  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nội dung chính sách đang được cập nhật',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 8),
          Text(
            'Không đăng nội dung gây hại, vi phạm bản quyền, lừa đảo hoặc xâm phạm quyền riêng tư. HuTube có thể kiểm tra nội dung trước khi xuất bản.',
          ),
        ],
      ),
    ),
  );
}
