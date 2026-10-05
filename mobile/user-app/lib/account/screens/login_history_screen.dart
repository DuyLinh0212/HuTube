import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../services/account_service.dart';

class LoginHistoryScreen extends StatefulWidget {
  const LoginHistoryScreen({super.key, required this.service});

  final AccountService service;

  @override
  State<LoginHistoryScreen> createState() => _LoginHistoryScreenState();
}

class _LoginHistoryScreenState extends State<LoginHistoryScreen> {
  final _items = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _pageSize = 20;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.service.getLoginHistory(page: page);
      final items = (response['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _page = (response['page'] as num?)?.toInt() ?? page;
        _pageSize = (response['pageSize'] as num?)?.toInt() ?? 20;
        _total = (response['total'] as num?)?.toInt() ?? items.length;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppStrings.t('account.loginHistoryLoadError');
      });
    }
  }

  bool get _hasPrevious => _page > 1;
  bool get _hasNext => _page * _pageSize < _total;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.t('account.loginHistoryHeading')),
        actions: [
          IconButton(
            tooltip: AppStrings.t('common.retry'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primaryPink,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text(
              AppStrings.t('account.loginHistoryDesc'),
              style: TextStyle(
                color: AppColors.textSecondaryFor(context),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 14),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!_loading && _error == null && _items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(AppStrings.t('account.loginHistoryEmpty')),
                ),
              ),
            ..._items.map((item) => _LoginHistoryCard(item: item)),
            if (!_loading && _total > _pageSize)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _hasPrevious
                            ? () => _load(page: _page - 1)
                            : null,
                        child: Text(AppStrings.t('account.previousPage')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _hasNext
                            ? () => _load(page: _page + 1)
                            : null,
                        child: Text(AppStrings.t('account.nextPage')),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoginHistoryCard extends StatelessWidget {
  const _LoginHistoryCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final platform = '${item['platform'] ?? ''}'.toLowerCase();
    final deviceName =
        '${item['deviceName'] ?? AppStrings.t('common.unknown')}';
    final ip = '${item['ipAddress'] ?? ''}'.trim();
    final rawDate = DateTime.tryParse('${item['loginAt'] ?? ''}')?.toLocal();
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryPink.withValues(alpha: .12),
          child: Icon(
            platform == 'mobile'
                ? Icons.phone_android_rounded
                : Icons.computer_rounded,
            color: AppColors.primaryPink,
          ),
        ),
        title: Text(
          deviceName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            if (rawDate != null)
              '${AppStrings.t('account.signedInAt')} ${AppStrings.dateTime(rawDate)}',
            if (ip.isNotEmpty)
              '${AppStrings.t('account.ipAddress')} ${_maskIp(ip)}',
          ].join(' · '),
        ),
      ),
    );
  }

  String _maskIp(String value) {
    final parts = value.split('.');
    if (parts.length == 4) return '${parts[0]}.${parts[1]}.•••.•••';
    return value;
  }
}
