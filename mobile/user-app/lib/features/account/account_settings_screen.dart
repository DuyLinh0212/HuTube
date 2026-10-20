import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/storage/app_preferences.dart';
import '../../core/widgets/scrollable_sheet.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_notifier.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../../account/models/account_models.dart';
import '../../account/screens/change_password_screen.dart';
import '../../account/screens/edit_profile_screen.dart';
import '../../account/screens/notification_settings_screen.dart';
import '../../account/screens/preferences_screen.dart';
import '../../account/screens/active_sessions_screen.dart';
import '../../account/services/account_service.dart';
import '../../account/state/account_controller.dart';
import '../../channel/models/channel_models.dart';
import '../../channel/screens/create_channel_screen.dart';
import '../../channel/services/channel_service.dart';
import '../content/content_service.dart';
import '../notifications/notification_center.dart';
import '../playlists/playlist_service.dart';
import 'background_download_settings_screen.dart';
import 'playback_settings_screen.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({
    super.key,
    required this.auth,
    required this.notifications,
  });

  final AuthController auth;
  final NotificationCenter notifications;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  late final AccountService _accountService;
  late final ChannelService _channelService;
  final _prefs = const AppPreferencesStore();

  ChannelDetail? _myChannel;
  String? _channelHandle;
  UserProfile? _profile;

  int _playlistCount = 0;
  int _subscribedCount = 0;
  int _likedCount = 0;

  @override
  void initState() {
    super.initState();
    _accountService = AccountService(widget.auth);
    _channelService = ChannelService(widget.auth);
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    if (!widget.auth.authenticated) return;

    try {
      final channel = await _channelService.getMyChannel();

      UserProfile? profile;
      try {
        profile = await _accountService.getProfile();
      } catch (_) {}

      int playlistCount = 0;
      try {
        final pls = await PlaylistService(widget.auth).mine();
        playlistCount = pls.length;
      } catch (_) {}

      int subscribedCount = 0;
      try {
        final subs = await _channelService.getSubscribedChannels();
        subscribedCount = subs.length;
      } catch (_) {}

      int likedCount = 0;
      try {
        final liked = await ContentService(widget.auth).liked(page: 1);
        likedCount = liked.total > 0 ? liked.total : liked.items.length;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _myChannel = channel;
          _channelHandle = channel?.handle;
          _profile = profile;
          _playlistCount = playlistCount;
          _subscribedCount = subscribedCount;
          _likedCount = likedCount;
        });
      }
    } catch (_) {}
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _loadInitialData();
  }

  Future<void> _openProfileEditor() async {
    try {
      final UserProfile profile =
          _profile ?? await _accountService.getProfile();
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
    final controller = AccountController(_accountService);
    await controller.loadSessions();
    if (!mounted) {
      controller.dispose();
      return;
    }
    await _open(
      ActiveSessionsScreen(
        controller: controller,
        onLogoutAll: () async {
          await _accountService.revokeAllSessions();
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

  void _showAccountSettingsSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textPrimary;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ScrollableSheet(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(
                  AppStrings.t('settings.accountSettings'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
              const Divider(),
              const SizedBox(height: 8),
              _actionTile(
                icon: Icons.person_outline_rounded,
                title: AppStrings.t('settings.accountSheet.profile'),
                subtitle: AppStrings.t('settings.accountSheet.profileDesc'),
                textColor: textColor,
                onTap: () {
                  Navigator.pop(ctx);
                  _openProfileEditor();
                },
              ),
              const SizedBox(height: 8),
              _actionTile(
                icon: Icons.lock_outline_rounded,
                title: AppStrings.t('settings.accountSheet.security'),
                subtitle: AppStrings.t('settings.accountSheet.securityDesc'),
                textColor: textColor,
                onTap: () {
                  Navigator.pop(ctx);
                  _open(ChangePasswordScreen(auth: widget.auth));
                },
              ),
              const SizedBox(height: 8),
              _actionTile(
                icon: Icons.notifications_none_outlined,
                title: AppStrings.t('settings.accountSheet.notifications'),
                subtitle: AppStrings.t(
                  'settings.accountSheet.notificationsDesc',
                ),
                textColor: textColor,
                onTap: () {
                  Navigator.pop(ctx);
                  _open(
                    NotificationSettingsScreen(
                      auth: widget.auth,
                      notifications: widget.notifications,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              _actionTile(
                icon: Icons.devices_rounded,
                title: AppStrings.t('settings.accountSheet.sessions'),
                subtitle: AppStrings.t('settings.accountSheet.sessionsDesc'),
                textColor: textColor,
                onTap: () {
                  Navigator.pop(ctx);
                  _openSessions();
                },
              ),
              const SizedBox(height: 8),
              _actionTile(
                icon: Icons.tune_rounded,
                title: AppStrings.t('settings.accountSheet.playbackPref'),
                subtitle: AppStrings.t(
                  'settings.accountSheet.playbackPrefDesc',
                ),
                textColor: textColor,
                onTap: () {
                  Navigator.pop(ctx);
                  _open(PreferencesScreen(auth: widget.auth));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguageDialog() {
    final current = AppStrings.currentLang.value;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ScrollableSheet(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(
                  AppStrings.t('settings.selectLanguage'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                leading: Icon(
                  current == 'vi'
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: current == 'vi'
                      ? AppColors.primaryPink
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: const Text('Tiếng Việt'),
                onTap: () {
                  Navigator.pop(ctx);
                  AppStrings.setLanguage('vi');
                  _prefs.writeLanguage('vi');
                  setState(() {});
                },
              ),
              ListTile(
                leading: Icon(
                  current == 'en'
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: current == 'en'
                      ? AppColors.primaryPink
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: const Text('English'),
                onTap: () {
                  Navigator.pop(ctx);
                  AppStrings.setLanguage('en');
                  _prefs.writeLanguage('en');
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.t('auth.logout')),
        content: Text(AppStrings.t('settings.logoutConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.t('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.t('auth.logout')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.auth.logout();
      if (mounted) context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppStrings.currentLang,
      builder: (context, currentLang, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? Colors.white : AppColors.textPrimary;
        final user = widget.auth.user;

        final displayName =
            (user?['displayName'] as String?)?.isNotEmpty == true
            ? user!['displayName'] as String
            : AppStrings.t('common.user');
        final username = (user?['username'] as String?)?.isNotEmpty == true
            ? user!['username'] as String
            : '';
        final email = (user?['email'] as String?)?.isNotEmpty == true
            ? user!['email'] as String
            : '';

        final cardBorderColor = Theme.of(context).dividerColor;
        final cardBgColor = Theme.of(context).colorScheme.surface;

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: textColor),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              AppStrings.t('settings.title'),
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                // ================= HEADER PROFILE (Image 5) =================
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      HuTubeAvatar(
                        url: _profile?.avatarUrl,
                        label: displayName,
                        radius: 27,
                      ),
                      const SizedBox(width: 14),
                      // Name, handle, email
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            if (username.isNotEmpty)
                              Text(
                                '@$username',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? const Color(0xFFAAAAAA)
                                      : AppColors.textMuted,
                                ),
                              ),
                            const SizedBox(height: 1),
                            if (email.isNotEmpty)
                              Text(
                                email,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isDark
                                      ? const Color(0xFFAAAAAA)
                                      : AppColors.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Quick Theme Switch Icon Button on top right
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? const Color(0xFF242424)
                              : Colors.white,
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF383838)
                                : const Color(0xFFE0E0E0),
                          ),
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: isDark
                              ? AppStrings.t('settings.themeLightTooltip')
                              : AppStrings.t('settings.themeDarkTooltip'),
                          icon: Icon(
                            isDark
                                ? Icons.wb_sunny_outlined
                                : Icons.nightlight_round,
                            size: 20,
                            color: isDark
                                ? Colors.amber
                                : const Color(0xFF222222),
                          ),
                          onPressed: () {
                            ThemeNotifier.setTheme(isDark ? 'light' : 'dark');
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ================= SECTION: KÊNH CỦA BẠN (Image 5) =================
                Text(
                  AppStrings.t('settings.yourChannel'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: isDark
                        ? const Color(0xFF9E9E9E)
                        : AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 10),

                // Channel Card
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    if (_myChannel != null) {
                      context.push('/channels/${_myChannel!.handle}');
                    } else {
                      _open(CreateChannelScreen(auth: widget.auth));
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardBgColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cardBorderColor),
                    ),
                    child: Row(
                      children: [
                        if (_myChannel != null) ...[
                          HuTubeAvatar(
                            url: _myChannel!.avatarUrl,
                            label: _myChannel!.name,
                            radius: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _myChannel!.name,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '@${_myChannel!.handle}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? const Color(0xFFAAAAAA)
                                        : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark
                                  ? const Color(0xFF272727)
                                  : AppColors.surfaceAlt,
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              size: 26,
                              color: AppColors.primaryPink,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppStrings.t('settings.createFirstChannel'),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  AppStrings.t('settings.startCreating'),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: isDark
                                        ? const Color(0xFFAAAAAA)
                                        : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey,
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // 3-Column Stats Card (Image 5)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cardBorderColor),
                  ),
                  child: Row(
                    children: [
                      // Col 1: Danh sách phát
                      Expanded(
                        child: InkWell(
                          onTap: () => context.push('/playlists'),
                          child: Column(
                            children: [
                              Text(
                                '$_playlistCount',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppStrings.t('nav.playlists'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? const Color(0xFFAAAAAA)
                                      : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(width: 1, height: 32, color: cardBorderColor),
                      // Col 2: Kênh đăng ký
                      Expanded(
                        child: InkWell(
                          onTap: () => context.push('/subscriptions'),
                          child: Column(
                            children: [
                              Text(
                                '$_subscribedCount',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppStrings.t('nav.subscriptions'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? const Color(0xFFAAAAAA)
                                      : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(width: 1, height: 32, color: cardBorderColor),
                      // Col 3: Đã thích
                      Expanded(
                        child: InkWell(
                          onTap: () => context.push('/library'),
                          child: Column(
                            children: [
                              Text(
                                '$_likedCount',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppStrings.t('library.liked'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? const Color(0xFFAAAAAA)
                                      : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ================= ACTION LIST ITEMS (Image 5) =================
                _actionTile(
                  icon: Icons.storefront_outlined,
                  title: AppStrings.t('settings.channelSettings'),
                  subtitle: AppStrings.t('settings.customizeChannel'),
                  textColor: textColor,
                  onTap: () {
                    if (_channelHandle != null) {
                      context.push('/creator');
                    } else {
                      _open(CreateChannelScreen(auth: widget.auth));
                    }
                  },
                ),
                const SizedBox(height: 8),
                _actionTile(
                  icon: Icons.workspace_premium_outlined,
                  title: AppStrings.t('settings.plans'),
                  subtitle: AppStrings.t('settings.managePlans'),
                  textColor: textColor,
                  onTap: () => context.push('/plans'),
                ),
                const SizedBox(height: 8),
                _actionTile(
                  icon: Icons.play_circle_outline_rounded,
                  title: AppStrings.t('settings.playback'),
                  subtitle: AppStrings.t('settings.playbackDesc'),
                  textColor: textColor,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PlaybackSettingsScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _actionTile(
                  icon: Icons.download_rounded,
                  title: AppStrings.t('settings.bgAndDownloads'),
                  subtitle: AppStrings.t('settings.bgAndDownloadsDesc'),
                  textColor: textColor,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BackgroundDownloadSettingsScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _actionTile(
                  icon: Icons.manage_accounts_outlined,
                  title: AppStrings.t('settings.accountSettings'),
                  subtitle: AppStrings.t('settings.accountSettingsDesc'),
                  textColor: textColor,
                  onTap: _showAccountSettingsSheet,
                ),
                const SizedBox(height: 8),
                _actionTile(
                  icon: Icons.translate_rounded,
                  title: AppStrings.t('settings.language'),
                  subtitle: currentLang == 'vi' ? 'Tiếng Việt' : 'English',
                  textColor: textColor,
                  onTap: _showLanguageDialog,
                ),

                const SizedBox(height: 20),

                // ================= SECTION: LIÊN KẾT CỦA TÔI (Image 5) =================
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Text(
                      AppStrings.t('settings.myLinks'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    TextButton(
                      onPressed: _openProfileEditor,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primaryPink,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        AppStrings.t('common.edit'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cardBorderColor),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.link_rounded,
                        size: 20,
                        color: AppColors.primaryPink,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _profile?.bio?.isNotEmpty == true
                              ? _profile!.bio!
                              : AppStrings.t('settings.noLinksYet'),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark
                                ? const Color(0xFFAAAAAA)
                                : AppColors.textMuted,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ================= LOGOUT BUTTON =================
                OutlinedButton.icon(
                  onPressed: _logout,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: .06),
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha: .18),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label: Text(
                    AppStrings.t('auth.logout'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: .5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 21, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
