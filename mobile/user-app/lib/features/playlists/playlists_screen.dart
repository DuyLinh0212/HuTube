import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';

/// Playlist destination kept ready for the playlist API contract.
class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
    children: [
      HuTubeSectionHeader(
        title: 'Playlist',
        subtitle: 'Lưu và sắp xếp những video bạn muốn xem lại.',
        action: auth.authenticated ? 'Tạo mới' : null,
        onAction: () => _notice(context),
      ),
      const SizedBox(height: 18),
      HuTubeSurface(
        color: AppColors.primaryLight,
        border: BorderSide(color: AppColors.primary.withValues(alpha: .14)),
        child: Row(
          children: [
            const Icon(Icons.playlist_add_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tạo playlist riêng để gom các video theo chủ đề.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
      HuTubeStateView(
        icon: Icons.playlist_play_rounded,
        title: 'Playlist chưa sẵn sàng',
        message: auth.authenticated
            ? 'Dữ liệu playlist sẽ xuất hiện khi API playlist được kết nối.'
            : 'Đăng nhập để lưu playlist của bạn khi tính năng được mở.',
        actionLabel: auth.authenticated ? null : 'Đăng nhập',
        onAction: auth.authenticated ? null : () => context.go('/auth'),
        compact: true,
        accent: AppColors.primary,
      ),
    ],
  );

  void _notice(BuildContext context) =>
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tạo playlist sẽ hoạt động khi API playlist được kết nối.',
          ),
        ),
      );
}
