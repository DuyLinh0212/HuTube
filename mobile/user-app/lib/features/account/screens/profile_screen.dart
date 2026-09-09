import 'dart:async';
import 'package:flutter/material.dart';
import '../../../auth.dart';
import '../../../core/theme/app_theme.dart';
import '../../channel/models/channel_models.dart';
import '../../channel/services/channel_service.dart';
import '../../channel/screens/channel_screen.dart';
import '../../channel/screens/create_channel_screen.dart';
import '../../channel/screens/channel_settings_screen.dart';
import '../../channel/screens/channel_invitations_screen.dart';
import '../models/account_models.dart';
import '../services/account_service.dart';
import 'edit_profile_screen.dart';
import 'change_password_screen.dart';
import 'notification_settings_screen.dart';
import 'preferences_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.auth,
    required this.sessions,
    required this.sessionsLoading,
    required this.onRefreshSessions,
    required this.onRevokeSession,
    required this.onLogoutOthers,
    required this.onLogout,
  });

  final AuthController auth;
  final List<Map<String, dynamic>> sessions;
  final bool sessionsLoading;
  final Future<void> Function() onRefreshSessions;
  final Future<void> Function(String sessionId) onRevokeSession;
  final Future<void> Function() onLogoutOthers;
  final Future<void> Function() onLogout;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final AccountService _accountService;
  late final ChannelService _channelService;

  UserProfile? _profile;
  ChannelDetail? _channel;
  bool _loadingChannel = true;

  @override
  void initState() {
    super.initState();
    _accountService = AccountService(widget.auth);
    _channelService = ChannelService(widget.auth);
    _loadData();
  }

  Future<void> _loadData() async {
    unawaited(_loadProfile());
    unawaited(_loadChannel());
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _accountService.getProfile();
      if (mounted) {
        setState(() {
          _profile = p;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadChannel() async {
    try {
      final c = await _channelService.getMyChannel();
      if (mounted) {
        setState(() {
          _channel = c;
          _loadingChannel = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingChannel = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.user ?? {};
    final displayName =
        _profile?.displayName ?? user['displayName'] as String? ?? 'Người dùng';
    final email = _profile?.email ?? user['email'] as String? ?? '';
    final username = _profile?.username ?? user['username'] as String? ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header title for test compatibility & UI hierarchy
          const Text(
            'Tài khoản của bạn',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          // User Card (Header)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.primaryLight,
                  backgroundImage: _profile?.avatarUrl != null
                      ? NetworkImage(_profile!.avatarUrl!)
                      : null,
                  child: _profile?.avatarUrl == null
                      ? Text(
                          (displayName.isNotEmpty ? displayName[0] : 'U')
                              .toUpperCase(),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@$username',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: AppColors.primary,
                  ),
                  tooltip: 'Chỉnh sửa hồ sơ',
                  onPressed: () async {
                    if (_profile == null) return;
                    final updated = await Navigator.of(context)
                        .push<UserProfile>(
                          MaterialPageRoute(
                            builder: (_) => EditProfileScreen(
                              auth: widget.auth,
                              profile: _profile!,
                            ),
                          ),
                        );
                    if (updated != null) {
                      setState(() => _profile = updated);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Channel Section (1 User = Max 1 Channel rule)
          if (_loadingChannel)
            Container(
              height: 90,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(color: AppColors.primary),
            )
          else if (_channel != null) ...[
            // Has channel card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF0F4), Color(0xFFFAF8F7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFCCD8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.primary,
                        backgroundImage: _channel!.avatarUrl != null
                            ? NetworkImage(_channel!.avatarUrl!)
                            : null,
                        child: _channel!.avatarUrl == null
                            ? Text(
                                _channel!.name.isNotEmpty
                                    ? _channel!.name[0].toUpperCase()
                                    : 'K',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _channel!.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                              ],
                            ),
                            Text(
                              '@${_channel!.handle} · ${_channel!.subscriberCount} người đăng ký',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            minimumSize: const Size.fromHeight(40),
                          ),
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChannelScreen(
                                  auth: widget.auth,
                                  channelOrHandle: _channel!.handle,
                                ),
                              ),
                            );
                            _loadChannel();
                          },
                          child: const Text(
                            'Xem kênh',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(40),
                          ),
                          onPressed: () async {
                            final res = await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => ChannelSettingsScreen(
                                  auth: widget.auth,
                                  channel: _channel!,
                                ),
                              ),
                            );
                            if (res == true) _loadChannel();
                          },
                          child: const Text(
                            'Quản lý',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            // No channel card -> Create Channel CTA
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.video_call_rounded,
                        color: AppColors.primary,
                        size: 28,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Bạn chưa có kênh HuTube',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tạo kênh để xuất bản video, xây dựng cộng đồng và tiếp cận hàng triệu khán giả.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(44),
                    ),
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Tạo kênh ngay'),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              CreateChannelScreen(auth: widget.auth),
                        ),
                      );
                      _loadChannel();
                    },
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Menu Options List
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _menuTile(
                  icon: Icons.person_outline_rounded,
                  title: 'Chỉnh sửa thông tin hồ sơ',
                  onTap: () async {
                    if (_profile == null) return;
                    final updated = await Navigator.of(context)
                        .push<UserProfile>(
                          MaterialPageRoute(
                            builder: (_) => EditProfileScreen(
                              auth: widget.auth,
                              profile: _profile!,
                            ),
                          ),
                        );
                    if (updated != null) setState(() => _profile = updated);
                  },
                ),
                const Divider(height: 1),
                _menuTile(
                  icon: Icons.lock_outline_rounded,
                  title: 'Đổi mật khẩu',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChangePasswordScreen(auth: widget.auth),
                    ),
                  ),
                ),
                const Divider(height: 1),
                _menuTile(
                  icon: Icons.notifications_none_rounded,
                  title: 'Cài đặt thông báo',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          NotificationSettingsScreen(auth: widget.auth),
                    ),
                  ),
                ),
                const Divider(height: 1),
                _menuTile(
                  icon: Icons.mark_email_unread_outlined,
                  title: 'Lời mời tham gia kênh',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ChannelInvitationsScreen(auth: widget.auth),
                    ),
                  ),
                ),
                const Divider(height: 1),
                _menuTile(
                  icon: Icons.tune_rounded,
                  title: 'Cài đặt & Giao diện',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PreferencesScreen(auth: widget.auth),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Sessions Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Thiết bị đăng nhập',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Tải lại thiết bị',
                onPressed: widget.onRefreshSessions,
              ),
            ],
          ),
          const Text(
            'Thu hồi phiên trên thiết bị bạn không còn sử dụng.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),

          if (widget.sessionsLoading)
            const LinearProgressIndicator(color: AppColors.primary)
          else if (widget.sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Chưa tải được danh sách thiết bị.'),
            )
          else
            ...widget.sessions.map((session) {
              final isCurrent = session['isCurrent'] == true;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isCurrent ? AppColors.primary : AppColors.border,
                    width: isCurrent ? 1.5 : 1.0,
                  ),
                ),
                child: ListTile(
                  leading: Icon(
                    session['platform'] == 'mobile'
                        ? Icons.phone_android
                        : Icons.computer,
                    color: isCurrent
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  title: Text(
                    session['deviceName'] as String? ?? 'Thiết bị',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    isCurrent ? 'Thiết bị này' : 'Phiên đăng nhập',
                    style: TextStyle(
                      color: isCurrent
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  trailing: isCurrent
                      ? const Icon(
                          Icons.check_circle_outline,
                          color: AppColors.primary,
                        )
                      : TextButton(
                          onPressed: () => widget.onRevokeSession(
                            session['sessionId'] as String,
                          ),
                          child: const Text('Thu hồi'),
                        ),
                ),
              );
            }),

          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: widget.onLogoutOthers,
            child: const Text('Đăng xuất thiết bị khác'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: widget.onLogout,
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: AppColors.textSecondary,
        size: 20,
      ),
      onTap: onTap,
    );
  }
}
