import 'package:flutter/material.dart';

import '../../auth.dart';
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
    appBar: AppBar(title: const Text('Bản tải xuống')),
    body: AnimatedBuilder(
      animation: _downloads,
      builder: (_, __) {
        final items = _downloads.items;
        if (items.isEmpty)
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.download_done_outlined,
                  size: 56,
                  color: AppColors.textSecondary,
                ),
                SizedBox(height: 12),
                Text('Chưa có video tải xuống.'),
              ],
            ),
          );
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
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
                leading: const CircleAvatar(
                  backgroundColor: Color(0x1AFF3B70),
                  child: Icon(
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
                          item.error!,
                          style: const TextStyle(color: Colors.red),
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
                      const PopupMenuItem(
                        value: 'retry',
                        child: Text('Thử lại'),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Xóa khỏi thiết bị'),
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
  static String _label(LocalDownload item) => switch (item.status) {
    'queued' => 'Đang chờ',
    'downloading' => 'Đang tải ${(item.progress * 100).round()}%',
    'completed' => 'Đã lưu trên thiết bị',
    'paused' => 'Đã tạm dừng',
    _ => 'Tải thất bại',
  };
}
