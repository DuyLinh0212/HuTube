import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'local_download_manager.dart';
import 'offline_player_screen.dart';
import 'content_service.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, required this.auth});
  final AuthController auth;
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final _downloads = LocalDownloadManager.instance;
  late final ContentService _content = ContentService(widget.auth);
  List<Map<String, dynamic>> _remote = const [];
  bool _remoteLoading = true;
  @override
  void initState() {
    super.initState();
    _downloads.ensureLoaded();
    _loadRemote();
  }

  Future<void> _loadRemote() async {
    try {
      final items = await _content.downloads();
      if (mounted) {
        setState(() {
          _remote = items;
          _remoteLoading = false;
        });
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() {
          _remoteLoading = false;
          if (error.status != 404) _remote = const [];
        });
      }
    } catch (_) {
      if (mounted) setState(() => _remoteLoading = false);
    }
  }

  Future<void> _operate(Map<String, dynamic> item, String operation) async {
    final id = '${item['videoDownloadId'] ?? ''}';
    if (id.isEmpty) return;
    try {
      await _content.updateDownload(id, operation);
      await _loadRemote();
      if (operation == 'cancel') await _downloads.remove(id);
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
      }
    }
  }

  Future<void> _removeRemote(Map<String, dynamic> item) async {
    final id = '${item['videoDownloadId'] ?? ''}';
    if (id.isEmpty) return;
    try {
      await _content.deleteDownload(id);
      await _downloads.remove(id);
      await _loadRemote();
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
      }
    }
  }

  Future<void> _deleteAllRemote() async {
    final ids = _remote
        .map((item) => '${item['videoDownloadId'] ?? ''}')
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa tất cả yêu cầu tải?'),
        content: const Text('Các yêu cầu tải khỏi tài khoản sẽ bị xóa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.t('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _content.deleteDownloads(ids);
      for (final id in ids) {
        await _downloads.remove(id);
      }
      await _loadRemote();
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.apiError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _downloads,
    builder: (_, _) {
      final items = _downloads.items;
      if (items.isEmpty && _remote.isEmpty && !_remoteLoading) {
        return HuTubeStateView(
          icon: Icons.download_done_outlined,
          title: AppStrings.t('downloads.empty'),
          message:
              'Video đã tải sẽ được lưu trên thiết bị để xem khi không có mạng.',
          accent: AppColors.violet,
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          HuTubeSectionHeader(
            title: AppStrings.t('downloads.title'),
            subtitle: 'Theo dõi yêu cầu tải và video đã lưu trên thiết bị.',
            action: _remote.isEmpty ? null : 'Xóa tất cả',
            onAction: _deleteAllRemote,
          ),
          const SizedBox(height: 14),
          if (_remoteLoading)
            const LinearProgressIndicator(minHeight: 2)
          else if (_remote.isNotEmpty) ...[
            Text(
              'Yêu cầu tải xuống',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            for (final item in _remote)
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.cloud_download_outlined,
                    color: AppColors.violet,
                  ),
                  title: Text(
                    '${item['title'] ?? 'Video'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${item['quality'] ?? ''} · ${_remoteStatus('${item['status'] ?? ''}')}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (choice) {
                      if (choice == 'delete') {
                        _removeRemote(item);
                      } else {
                        _operate(item, choice);
                      }
                    },
                    itemBuilder: (_) {
                      final status = '${item['status'] ?? ''}'.toLowerCase();
                      return [
                        if (status.contains('pause') || status.contains('hold'))
                          const PopupMenuItem(
                            value: 'resume',
                            child: Text('Tiếp tục'),
                          ),
                        if (status.contains('progress') ||
                            status.contains('download'))
                          const PopupMenuItem(
                            value: 'pause',
                            child: Text('Tạm dừng'),
                          ),
                        if (status.contains('fail'))
                          const PopupMenuItem(
                            value: 'retry',
                            child: Text('Thử lại'),
                          ),
                        if (!status.contains('complete'))
                          const PopupMenuItem(
                            value: 'cancel',
                            child: Text('Hủy tải'),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Xóa yêu cầu'),
                        ),
                      ];
                    },
                  ),
                ),
              ),
            const SizedBox(height: 10),
          ],
          if (items.isNotEmpty) ...[
            Text(
              'Video trên thiết bị',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 18),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceFor(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderFor(context)),
                ),
                child: ListTile(
                  onTap: item.completed
                      ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => OfflinePlayerScreen(
                              auth: widget.auth,
                              download: item,
                            ),
                          ),
                        )
                      : null,
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.violet.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.download_outlined,
                      color: AppColors.violet,
                    ),
                  ),
                  title: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${item.quality} · ${_label(item)}'),
                      if (item.active)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: LinearProgressIndicator(
                            value: item.progress,
                            color: AppColors.primaryPink,
                          ),
                        ),
                      if (item.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            AppStrings.t('downloads.error'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                  isThreeLine: item.active || item.error != null,
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'retry') _downloads.retry(item.id);
                      if (value == 'delete') _downloads.remove(item.id);
                    },
                    itemBuilder: (_) => [
                      if (!item.active && !item.completed)
                        PopupMenuItem(
                          value: 'retry',
                          child: Text(AppStrings.t('common.retry')),
                        ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(AppStrings.t('downloads.remove')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
  String _label(LocalDownload item) => switch (item.status) {
    'queued' => AppStrings.t('downloads.queued'),
    'downloading' => AppStrings.format('downloads.downloading', {
      'percent': AppStrings.number((item.progress * 100).round()),
    }),
    'completed' => AppStrings.t('downloads.completed'),
    'paused' => AppStrings.t('downloads.paused'),
    _ => AppStrings.t('downloads.failed'),
  };

  String _remoteStatus(String status) => switch (status.toLowerCase()) {
    'queued' || 'pending' => 'Đang chờ',
    'downloading' || 'in_progress' => 'Đang tải',
    'paused' => 'Đã tạm dừng',
    'completed' || 'complete' => 'Hoàn tất',
    'failed' || 'error' => 'Thất bại',
    'cancelled' || 'canceled' => 'Đã hủy',
    _ => status.isEmpty ? 'Đang xử lý' : status,
  };
}
