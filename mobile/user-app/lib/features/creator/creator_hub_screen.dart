import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../channel/models/channel_models.dart';
import '../../channel/screens/channel_invitations_screen.dart';
import '../../channel/screens/channel_settings_screen.dart';
import '../../channel/screens/create_channel_screen.dart';
import '../../channel/services/channel_service.dart';
import '../../core/theme/app_theme.dart';
import 'creator_comments_screen.dart';
import 'creator_content_screen.dart';
import 'video_upload_screen.dart';

class CreatorHubScreen extends StatefulWidget {
  const CreatorHubScreen({super.key, required this.auth});
  final AuthController auth;
  @override
  State<CreatorHubScreen> createState() => _CreatorHubScreenState();
}

class _CreatorHubScreenState extends State<CreatorHubScreen> {
  ChannelDetail? _channel;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final channel = await ChannelService(widget.auth).getMyChannel();
      if (mounted) {
        setState(() {
          _channel = channel;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Không thể tải Creator Studio.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _load();
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
    if (_channel == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.video_call_outlined,
                size: 54,
                color: AppColors.primaryPink,
              ),
              const SizedBox(height: 12),
              const Text(
                'Tạo kênh để mở Creator Studio',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => _open(CreateChannelScreen(auth: widget.auth)),
                child: const Text('Tạo kênh'),
              ),
            ],
          ),
        ),
      );
    }
    final channel = _channel!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
      children: [
        Text(
          'Creator Studio',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text('Quản lý kênh ${channel.name} bằng dữ liệu thật từ HuTube.'),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundImage: channel.avatarUrl == null
                      ? null
                      : NetworkImage(channel.avatarUrl!),
                  child: channel.avatarUrl == null
                      ? Text(channel.name.substring(0, 1))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '@${channel.handle} · ${channel.videoCount} video · ${channel.subscriberCount} người đăng ký',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _CreatorAction(
          icon: Icons.upload_file_outlined,
          title: 'Tải video lên',
          detail:
              'Tải video có preflight quota và gửi kiểm duyệt khi công khai.',
          onTap: () =>
              _open(VideoUploadScreen(auth: widget.auth, channel: channel)),
        ),
        _CreatorAction(
          icon: Icons.video_library_outlined,
          title: 'Nội dung kênh',
          detail: 'Xem và điều chỉnh video của kênh.',
          onTap: () =>
              _open(CreatorContentScreen(auth: widget.auth, channel: channel)),
        ),
        _CreatorAction(
          icon: Icons.forum_outlined,
          title: 'Bình luận',
          detail: 'Quản lý phản hồi trên video của bạn.',
          onTap: () =>
              _open(CreatorCommentsScreen(auth: widget.auth, channel: channel)),
        ),
        _CreatorAction(
          icon: Icons.settings_outlined,
          title: 'Cài đặt kênh',
          detail: 'Tên, mô tả, ảnh đại diện và banner.',
          onTap: () =>
              _open(ChannelSettingsScreen(auth: widget.auth, channel: channel)),
        ),
        _CreatorAction(
          icon: Icons.group_outlined,
          title: 'Lời mời cộng tác',
          detail: 'Mời và phản hồi lời mời thành viên.',
          onTap: () => _open(ChannelInvitationsScreen(auth: widget.auth)),
        ),
        const _CreatorAction(
          icon: Icons.subtitles_outlined,
          title: 'Phụ đề',
          detail:
              'Trạng thái phụ đề theo video sẽ khớp web; backend chưa có authoring phụ đề.',
        ),
      ],
    );
  }
}

class _CreatorAction extends StatelessWidget {
  const _CreatorAction({
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon, color: AppColors.primaryPink),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(detail),
      trailing: onTap == null
          ? const Icon(Icons.info_outline)
          : const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}
