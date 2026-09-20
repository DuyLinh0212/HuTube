import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
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
    final link = (item['actionUrl'] ?? item['link']) as String?;
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
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
        children: [
          const _NotificationSkeleton(),
          const SizedBox(height: 12),
          const _NotificationSkeleton(),
          const SizedBox(height: 12),
          const _NotificationSkeleton(),
        ],
      );
    }
    if (_error != null) {
      return HuTubeStateView(
        icon: Icons.notifications_off_outlined,
        title: _error!,
        message: AppStrings.t('common.networkError'),
        actionLabel: AppStrings.t('common.retry'),
        onAction: _load,
      );
    }
    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.t('notifications.title'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.45,
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
            HuTubeStateView(
              icon: Icons.notifications_off_outlined,
              title: AppStrings.t('notifications.empty'),
              message: 'Khi có hoạt động mới, bạn sẽ thấy cập nhật ở đây.',
              compact: true,
            ),
          ..._items.map(
            (item) => _NotificationCard(item: item, onTap: () => _read(item)),
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

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = item['isRead'] != true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: unread
            ? AppColors.primary.withValues(alpha: .06)
            : AppColors.surfaceFor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: unread
              ? AppColors.primary.withValues(alpha: .22)
              : AppColors.borderFor(context),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            unread
                ? Icons.notifications_rounded
                : Icons.notifications_none_rounded,
            color: AppColors.primary,
          ),
        ),
        title: Text(
          '${item['title'] ?? AppStrings.t('notifications.defaultTitle')}',
          style: TextStyle(
            fontWeight: unread ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
        subtitle: Text('${item['content'] ?? item['body'] ?? ''}'),
        trailing: unread
            ? Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              )
            : const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _NotificationSkeleton extends StatelessWidget {
  const _NotificationSkeleton();

  @override
  Widget build(BuildContext context) => Container(
    height: 82,
    decoration: BoxDecoration(
      color: AppColors.borderSubtle,
      borderRadius: BorderRadius.circular(14),
    ),
  );
}
