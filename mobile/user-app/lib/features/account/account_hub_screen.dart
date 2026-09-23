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
import '../../core/localization/app_strings.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../../account/models/account_models.dart';
import '../../account/services/account_service.dart';
import '../../account/state/account_controller.dart';
import '../../account/screens/profile_screen.dart';

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
      if (mounted) {
        setState(() {
          _channelHandle = channel?.handle;
          _loadingChannel = false;
        });
      }
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
        SnackBar(content: Text(AppStrings.t('account.profileLoadError'))),
      );
    }
  }

  Future<void> _openSessions() async {
    final controller = AccountController(AccountService(widget.auth));
    await controller.loadSessions();
    if (!mounted) return;
    await _open(
      ProfileScreen(
        auth: widget.auth,
        sessions: controller.sessions,
        sessionsLoading: controller.loadingSessions,
        onRefreshSessions: controller.loadSessions,
        onRevokeSession: (id) async {
          await controller.revokeSession(id);
        },
        onLogoutOthers: () async {
          await controller.revokeOtherSessions();
        },
        onLogoutAll: () async {
          await AccountService(widget.auth).revokeAllSessions();
          await widget.auth.logout();
          if (mounted) context.go('/auth');
        },
        onLogout: () async {
          await widget.auth.logout();
          if (mounted) context.go('/auth');
        },
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name =
        (widget.auth.user?['displayName'] as String?) ??
        AppStrings.t('common.userHuTube');
    final email = (widget.auth.user?['email'] as String?) ?? '';
    final avatarUrl = widget.auth.user?['avatarUrl'] as String?;
    final verified = widget.auth.user?['emailVerified'] == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text(
          AppStrings.t('account.hubTitle'),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Quản lý hồ sơ, nội dung và trải nghiệm HuTube của bạn.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.ink, Color(0xFF36263C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              HuTubeAvatar(
                url: avatarUrl,
                label: name,
                radius: 31,
                backgroundColor: AppColors.primary.withValues(alpha: .18),
                foregroundColor: Colors.white,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .7),
                      ),
                    ),
                    const SizedBox(height: 10),
                    HuTubePill(
                      label: AppStrings.t(
                        verified
                            ? 'profile.emailVerified'
                            : 'profile.emailUnverified',
                      ),
                      icon: verified
                          ? Icons.verified_rounded
                          : Icons.info_outline_rounded,
                      color: (verified ? AppColors.success : AppColors.warning)
                          .withValues(alpha: .18),
                      textColor: verified
                          ? const Color(0xFF8BF0C6)
                          : const Color(0xFFFFD37B),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: AppStrings.t('account.editTooltip'),
                onPressed: _openProfileEditor,
                icon: const Icon(Icons.edit_outlined, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Heading(AppStrings.t('account.heading')),
        _Tile(
          icon: Icons.person_outline,
          title: AppStrings.t('account.editProfile'),
          onTap: _openProfileEditor,
        ),
        _Tile(
          icon: Icons.lock_outline,
          title: AppStrings.t('account.passwordSecurity'),
          onTap: () => _open(ChangePasswordScreen(auth: widget.auth)),
        ),
        _Tile(
          icon: Icons.devices_outlined,
          title: 'Phiên đăng nhập & thiết bị',
          subtitle: 'Xem và đăng xuất thiết bị đang dùng tài khoản.',
          onTap: _openSessions,
        ),
        _Tile(
          icon: Icons.tune_rounded,
          title: AppStrings.t('account.appearance'),
          onTap: () => _open(PreferencesScreen(auth: widget.auth)),
        ),
        _Tile(
          icon: Icons.notifications_outlined,
          title: AppStrings.t('account.notificationSettings'),
          onTap: () => _open(NotificationSettingsScreen(auth: widget.auth)),
        ),
        const SizedBox(height: 18),
        _Heading(AppStrings.t('account.channelHeading')),
        if (_loadingChannel)
          ListTile(
            leading: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text(AppStrings.t('account.checkingChannel')),
          )
        else if (_channelHandle == null)
          _Tile(
            icon: Icons.add_to_queue_rounded,
            title: AppStrings.t('account.createChannel'),
            subtitle: AppStrings.t('account.createChannelDesc'),
            onTap: () => _open(CreateChannelScreen(auth: widget.auth)),
          )
        else ...[
          _Tile(
            icon: Icons.mail_outline,
            title: AppStrings.t('account.invitations'),
            onTap: () => _open(ChannelInvitationsScreen(auth: widget.auth)),
          ),
          _Tile(
            icon: Icons.dashboard_outlined,
            title: AppStrings.t('account.creatorStudio'),
            onTap: () => context.go('/creator'),
          ),
        ],
        const SizedBox(height: 18),
        _Heading(AppStrings.t('account.serviceHeading')),
        _Tile(
          icon: Icons.workspace_premium_outlined,
          title: AppStrings.t('account.plans'),
          onTap: () => context.go('/plans'),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () async {
            await widget.auth.logout();
            if (!context.mounted) return;
            context.go('/home');
          },
          icon: const Icon(Icons.logout_rounded),
          label: Text(AppStrings.t('account.logout')),
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
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    decoration: BoxDecoration(
      color: AppColors.surfaceFor(context),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: AppColors.borderFor(context)),
    ),
    child: ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}
