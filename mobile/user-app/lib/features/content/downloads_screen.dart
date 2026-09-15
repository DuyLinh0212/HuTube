import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppStrings.t('downloads.title'))),
    body: AnimatedBuilder(
      animation: _downloads,
      builder: (_, _) {
        final items = _downloads.items;
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.download_done_outlined,
                  size: 56,
                  color: AppColors.textSecondaryFor(context),
                ),
                SizedBox(height: 12),
                Text(AppStrings.t('downloads.empty')),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, index) {
            final item = items[index];
            return Card(
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
                leading: CircleAvatar(
                  backgroundColor: AppColors.primaryPink.withValues(alpha: .12),
                  child: const Icon(
                    Icons.download_outlined,
                    color: AppColors.primaryPink,
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
            );
          },
        );
      },
    ),
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
