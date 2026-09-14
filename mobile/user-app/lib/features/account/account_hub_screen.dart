import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../account/screens/change_password_screen.dart';
import '../../account/screens/edit_profile_screen.dart';
import '../../account/screens/notification_settings_screen.dart';
import '../../account/screens/preferences_screen.dart';
import '../../auth.dart';
import '../../channel/screens/channel_invitations_screen.dart';
import '../../channel/screens/create_channel_screen.dart';
import '../../channel/services/channel_service.dart';
import '../../core/theme/app_theme.dart';
import '../../account/models/account_models.dart';
import '../../account/services/account_service.dart';

class AccountHubScreen extends StatefulWidget {
  const AccountHubScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<AccountHubScreen> createState() => _AccountHubScreenState();
}

class _AccountHubScreenState extends State<AccountHubScreen> {
  bool _loadingChannel = true;
  String? _channelHandle;

  @override
  void initState() {
    super.initState();
    _loadChannel();
  }

  Future<void> _loadChannel() async {
    try {
      final channel = await ChannelService(widget.auth).getMyChannel();
      if (mounted)
        setState(() {
          _channelHandle = channel?.handle;
          _loadingChannel = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingChannel = false);
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _loadChannel();
  }

  Future<void> _openProfileEditor() async {
    try {
      final UserProfile profile = await AccountService(
        widget.auth,
      ).getProfile();
      if (!mounted) return;
      await _open(EditProfileScreen(auth: widget.auth, profile: profile));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể tải hồ sơ để chỉnh sửa.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name =
        (widget.auth.user?['displayName'] as String?) ?? 'Người dùng HuTube';
    final email = (widget.auth.user?['email'] as String?) ?? '';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
      children: [
        Text(
          'Bạn',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 31,
                  backgroundColor: AppColors.primaryPink.withValues(alpha: .14),
                  child: Text(
                    name.isEmpty ? 'H' : name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 24,
                      color: AppColors.primaryPink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(email, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Chỉnh sửa hồ sơ',
                  onPressed: _openProfileEditor,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const _Heading('Tài khoản'),
        _Tile(
          icon: Icons.person_outline,
          title: 'Chỉnh sửa hồ sơ',
          onTap: _openProfileEditor,
        ),
        _Tile(
          icon: Icons.lock_outline,
          title: 'Mật khẩu và bảo mật',
          onTap: () => _open(ChangePasswordScreen(auth: widget.auth)),
        ),
        _Tile(
          icon: Icons.tune_rounded,
          title: 'Tùy chọn giao diện',
          onTap: () => _open(PreferencesScreen(auth: widget.auth)),
        ),
        _Tile(
          icon: Icons.notifications_outlined,
          title: 'Cài đặt thông báo',
          onTap: () => _open(NotificationSettingsScreen(auth: widget.auth)),
        ),
        const SizedBox(height: 18),
        const _Heading('Kênh của bạn'),
        if (_loadingChannel)
          const ListTile(
            leading: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('Đang kiểm tra kênh…'),
          )
        else if (_channelHandle == null)
          _Tile(
            icon: Icons.add_to_queue_rounded,
            title: 'Tạo kênh',
            subtitle: 'Bắt đầu đăng video với một kênh HuTube.',
            onTap: () => _open(CreateChannelScreen(auth: widget.auth)),
          )
        else ...[
          _Tile(
            icon: Icons.mail_outline,
            title: 'Lời mời cộng tác',
            onTap: () => _open(ChannelInvitationsScreen(auth: widget.auth)),
          ),
          _Tile(
            icon: Icons.dashboard_outlined,
            title: 'Creator Studio',
            onTap: () => context.go('/creator'),
          ),
        ],
        const SizedBox(height: 18),
        const _Heading('Gói dịch vụ'),
        _Tile(
          icon: Icons.workspace_premium_outlined,
          title: 'Gói và dung lượng',
          onTap: () => context.go('/plans'),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () async {
            await widget.auth.logout();
            if (mounted) context.go('/home');
          },
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Đăng xuất'),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    leading: Icon(icon),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}
