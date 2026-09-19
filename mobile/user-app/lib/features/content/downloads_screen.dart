import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'local_download_manager.dart';
import 'offline_player_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, required this.auth});
  final AuthController auth;
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final _downloads = LocalDownloadManager.instance;
  @override
  void initState() {
    super.initState();
    _downloads.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _downloads,
    builder: (_, _) {
      final items = _downloads.items;
      if (items.isEmpty) {
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
            subtitle: 'Quản lý video đã lưu trên thiết bị.',
          ),
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
}
