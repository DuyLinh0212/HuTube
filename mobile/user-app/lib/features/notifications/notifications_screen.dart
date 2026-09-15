import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import 'notification_hub.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  int _page = 1;
  bool _hasMore = false;
  late final NotificationHubClient _hub = NotificationHubClient(widget.auth);

  @override
  void initState() {
    super.initState();
    _load();
    _hub.connect(onNotification: _receive);
  }

  void _receive(Map<String, dynamic> item) {
    if (!mounted) return;
    final id = '${item['notificationId'] ?? ''}';
    setState(() {
      _items = [
        item,
        ..._items.where(
          (current) => '${current['notificationId'] ?? ''}' != id,
        ),
      ];
    });
  }

  @override
  void dispose() {
    _hub.disconnect();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final nextPage = more ? _page + 1 : 1;
    if (!more) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final json = await widget.auth.protected(
        'GET',
        '/notifications?page=$nextPage&pageSize=20',
      );
      final raw = json['items'] as List? ?? const [];
      if (!mounted) return;
      setState(() {
        final items = raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _items = more ? [..._items, ...items] : items;
        _page = nextPage;
        _hasMore = items.length == 20;
        _loading = false;
      });
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = AppStrings.apiError(
            error,
            fallback: 'notifications.loadError',
          );
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppStrings.t('notifications.loadError');
          _loading = false;
        });
      }
    }
  }

  Future<void> _read(Map<String, dynamic> item) async {
    final id = '${item['notificationId'] ?? ''}';
    if (id.isEmpty) return;
    if (item['isRead'] != true) {
      try {
        await widget.auth.protected(
          'PATCH',
          '/notifications/$id/read',
          body: const {},
        );
        if (mounted) setState(() => item['isRead'] = true);
      } catch (_) {}
    }
    final link = item['link'] as String?;
    if (link == null || !mounted) return;
    if (link.startsWith('/watch/')) context.push(link);
    if (link.startsWith('/creator')) context.go('/creator');
  }

  Future<void> _readAll() async {
    try {
      await widget.auth.protected(
        'POST',
        '/notifications/read-all',
        body: const {},
      );
      if (mounted) {
        setState(() {
          for (final item in _items) {
            item['isRead'] = true;
          }
        });
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryPink),
      );
    }
    if (_error != null) {
      return Center(
        child: FilledButton(onPressed: _load, child: Text(_error!)),
      );
    }
    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.t('notifications.title'),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: _items.any((item) => item['isRead'] != true)
                    ? _readAll
                    : null,
                child: Text(AppStrings.t('notifications.readAll')),
              ),
            ],
          ),
          if (_items.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 120),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.notifications_off_outlined,
                      size: 52,
                      color: AppColors.textMutedFor(context),
                    ),
                    SizedBox(height: 12),
                    Text(AppStrings.t('notifications.empty')),
                  ],
                ),
              ),
            ),
          ..._items.map(
            (item) => Card(
              color: item['isRead'] == true
                  ? null
                  : AppColors.primaryPink.withValues(alpha: .06),
              child: ListTile(
                leading: Icon(
                  item['isRead'] == true
                      ? Icons.notifications_none_rounded
                      : Icons.notifications_rounded,
                  color: AppColors.primaryPink,
                ),
                title: Text(
                  '${item['title'] ?? AppStrings.t('notifications.defaultTitle')}',
                  style: TextStyle(
                    fontWeight: item['isRead'] == true
                        ? FontWeight.w600
                        : FontWeight.w800,
                  ),
                ),
                subtitle: Text('${item['body'] ?? ''}'),
                onTap: () => _read(item),
              ),
            ),
          ),
          if (_hasMore)
            TextButton(
              onPressed: () => _load(more: true),
              child: Text(AppStrings.t('notifications.loadMore')),
            ),
        ],
      ),
    );
  }
}
