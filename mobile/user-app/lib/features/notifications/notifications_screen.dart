import 'dart:async';

import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_icons.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'notification_center.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.auth,
    required this.notifications,
  });
  final AuthController auth;
  final NotificationCenter notifications;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _markingRead = false;
  int _generation = 0;
  String? _error;
  int _page = 1;
  bool _hasMore = false;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _notificationSubscription = widget.notifications.newNotifications.listen(
      _receive,
    );
    _load();
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
    unawaited(_notificationSubscription?.cancel());
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_loading || _loadingMore || !_hasMore)) return;
    if (!more) ++_generation;
    final generation = _generation;
    final session = widget.auth.sessionGeneration;
    bool current() =>
        mounted &&
        generation == _generation &&
        session == widget.auth.sessionGeneration;
    final nextPage = more ? _page + 1 : 1;
    if (more) setState(() => _loadingMore = true);
    if (!more) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _error = null;
      });
    }
    try {
      final json = await widget.auth.protected(
        'GET',
        '/notifications?page=$nextPage&pageSize=20',
      );
      final raw = json['items'] as List? ?? const [];
      if (!current()) return;
      setState(() {
        final items = raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        final seen = <String>{};
        _items = (more ? [..._items, ...items] : items)
            .where((item) => seen.add('${item['notificationId']}'))
            .toList();
        final unreadCount = json['unreadCount'];
        if (!more && unreadCount is num) {
          widget.notifications.setUnreadCount(unreadCount.toInt());
        }
        _page = nextPage;
        _hasMore = items.length == 20;
        _loading = false;
        _loadingMore = false;
      });
    } on ApiFailure catch (error) {
      if (current()) {
        setState(() {
          _error = AppStrings.apiError(
            error,
            fallback: 'notifications.loadError',
          );
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (current()) {
        setState(() {
          _error = AppStrings.t('notifications.loadError');
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _read(Map<String, dynamic> item) async {
    final id = '${item['notificationId'] ?? ''}';
    if (id.isEmpty) return;
    if (item['isRead'] != true && id.isNotEmpty) {
      final marked = await widget.notifications.markRead(id);
      if (mounted && marked) setState(() => item['isRead'] = true);
    }
    if (mounted) widget.notifications.openNotification(item);
  }

  Future<void> _readAll() async {
    if (_markingRead) return;
    setState(() => _markingRead = true);
    try {
      await widget.notifications.markAllRead();
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.t('common.networkError'))),
        );
      }
    } finally {
      if (mounted) setState(() => _markingRead = false);
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
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _items.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            final theme = Theme.of(context);
            final unread = _items
                .where((item) => item['isRead'] != true)
                .length;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.t('notifications.title'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (unread > 0)
                        Text(
                          AppStrings.format('notifications.unreadCount', {
                            'count': '$unread',
                          }),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      TextButton.icon(
                        onPressed: unread > 0 && !_markingRead
                            ? _readAll
                            : null,
                        icon: _markingRead
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.done_all_rounded, size: 18),
                        label: Text(AppStrings.t('notifications.readAll')),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }
          if (index <= _items.length) {
            final item = _items[index - 1];
            return _NotificationCard(
              key: ValueKey(item['notificationId']),
              item: item,
              onTap: () => _read(item),
            );
          }
          if (_items.isEmpty) {
            return HuTubeStateView(
              icon: Icons.notifications_none_rounded,
              title: AppStrings.t('notifications.empty'),
              message: AppStrings.t('notifications.emptyDescription'),
              compact: true,
            );
          }
          return _hasMore
              ? Center(
                  child: TextButton(
                    onPressed: _loadingMore ? null : () => _load(more: true),
                    child: Text(AppStrings.t('notifications.loadMore')),
                  ),
                )
              : const SizedBox(height: 16);
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({super.key, required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final unread = item['isRead'] != true;
    final createdAt = DateTime.tryParse('${item['createdAt'] ?? ''}');
    final content = '${item['content'] ?? item['body'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: unread
            ? colors.primary.withValues(alpha: .07)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: unread
                        ? colors.primary.withValues(alpha: .12)
                        : colors.surfaceContainerHighest,
                  ),
                  child: Center(
                    child: AppIcons.asset(
                      AppIcons.notification,
                      size: 22,
                      color: unread ? colors.primary : colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['title'] ?? AppStrings.t('notifications.defaultTitle')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: unread
                              ? FontWeight.w700
                              : FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                      if (content.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                      if (createdAt != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          AppStrings.relativeDate(createdAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: unread
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: unread
                      ? Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                          ),
                        )
                      : Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                ),
              ],
            ),
          ),
        ),
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
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
    ),
  );
}
