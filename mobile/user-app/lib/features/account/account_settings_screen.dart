import '../../core/widgets/modal_header.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../channel/screens/channel_links_screen.dart';
import '../../channel/models/channel_links.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/storage/app_preferences.dart';
import '../../core/theme/app_icons.dart';
import '../../core/widgets/scrollable_sheet.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_notifier.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../../core/widgets/logout_confirmation_dialog.dart';
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

    final session = widget.auth.sessionGeneration;
    Future<T?> optional<T>(Future<T> request) async {
      try {
        return await request;
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait<Object?>([
      optional<ChannelDetail?>(_channelService.getMyChannel()),
      optional(_accountService.getProfile()),
      optional(
        PlaylistService(widget.auth).mine().then((items) => items.length),
      ),
      optional(
        _channelService.getSubscribedChannels().then((items) => items.length),
      ),
      optional(
        ContentService(widget.auth)
            .liked(page: 1)
            .then((page) => page.total > 0 ? page.total : page.items.length),
      ),
    ]);
    if (!mounted || session != widget.auth.sessionGeneration) return;
    setState(() {
      _myChannel = results[0] as ChannelDetail?;
      _channelHandle = _myChannel?.handle;
      _profile = results[1] as UserProfile?;
      _playlistCount = results[2] as int? ?? 0;
      _subscribedCount = results[3] as int? ?? 0;
      _likedCount = results[4] as int? ?? 0;
    });
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

  Future<void> _openLinksEditor() async {
    final channel = _myChannel;
    if (channel == null) {
      await _open(CreateChannelScreen(auth: widget.auth));
    } else {
      await _open(ChannelLinksScreen(auth: widget.auth, channel: channel));
    }
  }

  Future<void> _setAppearance({String? language, String? theme}) async {
    final session = widget.auth.sessionGeneration;
    if (language != null) {
      AppStrings.setLanguage(language);
    }
    if (theme != null) ThemeNotifier.setTheme(theme);
    if (mounted) setState(() {});
    try {
      if (language != null) await _prefs.writeLanguage(language);
      if (!widget.auth.authenticated ||
          session != widget.auth.sessionGeneration) {
        return;
      }
      await _accountService.updateAppearance(language: language, theme: theme);
    } catch (_) {
      if (mounted && session == widget.auth.sessionGeneration) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.t('prefs.syncError'))),
        );
      }
    }
  }

  Future<void> _openPublicLink(String url) async {
    if (!isPublicWebLink(url)) return;
    try {
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.t('auth.linkError'))));
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
              ModalHeader(
                title: AppStrings.t('settings.accountSettings'),
                icon: Icons.manage_accounts_outlined,
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.person_outline_rounded, color: textColor),
                title: Text(
                  AppStrings.t('settings.accountSheet.profile'),
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  AppStrings.t('settings.accountSheet.profileDesc'),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(ctx);
                  _openProfileEditor();
                },
              ),
              ListTile(
                leading: Icon(Icons.lock_outline_rounded, color: textColor),
                title: Text(
                  AppStrings.t('settings.accountSheet.security'),
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  AppStrings.t('settings.accountSheet.securityDesc'),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(ctx);
                  _open(ChangePasswordScreen(auth: widget.auth));
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.notifications_none_outlined,
                  color: textColor,
                ),
                title: Text(
                  AppStrings.t('settings.accountSheet.notifications'),
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  AppStrings.t('settings.accountSheet.notificationsDesc'),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
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
              ListTile(
                leading: Icon(Icons.devices_rounded, color: textColor),
                title: Text(
                  AppStrings.t('settings.accountSheet.sessions'),
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  AppStrings.t('settings.accountSheet.sessionsDesc'),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(ctx);
                  _openSessions();
                },
              ),
              ListTile(
                leading: Icon(Icons.tune_rounded, color: textColor),
                title: Text(
                  AppStrings.t('settings.accountSheet.playbackPref'),
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  AppStrings.t('settings.accountSheet.playbackPrefDesc'),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
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
              ModalHeader(
                title: AppStrings.t('settings.selectLanguage'),
                icon: Icons.translate_rounded,
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
                title: const Text('Tiếng Việt (VI) 🇻🇳'),
                onTap: () {
                  Navigator.pop(ctx);
                  _setAppearance(language: 'vi');
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
                title: const Text('English (EN) 🇺🇸'),
                onTap: () {
                  Navigator.pop(ctx);
                  _setAppearance(language: 'en');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showLogoutConfirmation(context);

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
        final avatarLetter = displayName.isNotEmpty
            ? displayName[0].toUpperCase()
            : 'D';

        final cardBorderColor = isDark
            ? const Color(0xFF2C2C2C)
            : const Color(0xFFE5E5E5);
        final cardBgColor = isDark ? const Color(0xFF161616) : Colors.white;

        return Scaffold(
          backgroundColor: isDark
              ? const Color(0xFF0F0F0F)
              : AppColors.background,
          appBar: AppBar(
            backgroundColor: isDark
                ? const Color(0xFF0F0F0F)
                : AppColors.surface,
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
                      // Circular Avatar
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(
                            0xFFFF1744,
                          ), // Pink/Red circle like Image 5
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFFF1744,
                              ).withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          avatarLetter,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
                            _setAppearance(theme: isDark ? 'light' : 'dark');
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
                      context.push('/channels/${_myChannel!.id}');
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
                  customIcon: AppIcons.asset(
                    AppIcons.myChannel,
                    size: 24,
                    color: textColor,
                  ),
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
                const Divider(height: 1),
                _actionTile(
                  customIcon: AppIcons.asset(
                    AppIcons.plan,
                    size: 24,
                    color: textColor,
                  ),
                  title: AppStrings.t('settings.plans'),
                  subtitle: AppStrings.t('settings.managePlans'),
                  textColor: textColor,
                  onTap: () => context.push('/plans'),
                ),
                const Divider(height: 1),
                _actionTile(
                  icon: Icons.play_circle_outline_rounded,
                  title: AppStrings.t('settings.playback'),
                  subtitle: AppStrings.t('settings.playbackDesc'),
                  textColor: textColor,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlaybackSettingsScreen(auth: widget.auth),
                    ),
                  ),
                ),
                const Divider(height: 1),
                _actionTile(
                  customIcon: AppIcons.asset(
                    AppIcons.download,
                    size: 24,
                    color: textColor,
                  ),
                  title: AppStrings.t('settings.bgAndDownloads'),
                  subtitle: AppStrings.t('settings.bgAndDownloadsDesc'),
                  textColor: textColor,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          BackgroundDownloadSettingsScreen(auth: widget.auth),
                    ),
                  ),
                ),
                const Divider(height: 1),
                _actionTile(
                  customIcon: AppIcons.asset(
                    AppIcons.setting,
                    size: 24,
                    color: textColor,
                  ),
                  title: AppStrings.t('settings.accountSettings'),
                  subtitle: AppStrings.t('settings.accountSettingsDesc'),
                  textColor: textColor,
                  onTap: _showAccountSettingsSheet,
                ),
                const Divider(height: 1),
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
                      key: const ValueKey('settings-edit-links'),
                      onPressed: _openLinksEditor,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primaryPink,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(48, 48),
                      ),
                      child: Text(
                        AppStrings.t(
                          _myChannel == null
                              ? 'creator.createChannel'
                              : 'common.edit',
                        ),
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
                  child: channelLinks(_myChannel?.settings).isNotEmpty
                      ? Column(
                          children: channelLinks(_myChannel?.settings)
                              .map(
                                (link) => Material(
                                  type: MaterialType.transparency,
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.link_rounded),
                                    title: Text(
                                      link['title']!.isEmpty
                                          ? Uri.parse(link['url']!).host
                                          : link['title']!,
                                    ),
                                    subtitle: Text(
                                      link['url']!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: const Icon(
                                      Icons.open_in_new_rounded,
                                      size: 18,
                                    ),
                                    onTap: () => _openPublicLink(link['url']!),
                                  ),
                                ),
                              )
                              .toList(),
                        )
                      : Row(
                          children: [
                            const Icon(
                              Icons.link_rounded,
                              size: 20,
                              color: AppColors.primaryPink,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                AppStrings.t('settings.noLinksYet'),
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

                if (_profile?.userId.isNotEmpty == true)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.fingerprint_rounded),
                    title: Text(AppStrings.t('account.userId')),
                    subtitle: Text(
                      _profile!.userId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.copy_rounded, size: 18),
                    onTap: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _profile!.userId),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(AppStrings.t('common.copied')),
                          ),
                        );
                      }
                    },
                  ),
                const SizedBox(height: 16),
                // ================= LOGOUT BUTTON =================
                OutlinedButton.icon(
                  onPressed: _logout,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(
                      color: Colors.redAccent.withValues(alpha: 0.5),
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
    IconData? icon,
    Widget? customIcon,
    required String title,
    required String subtitle,
    required Color textColor,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          if (customIcon != null)
            customIcon
          else if (icon != null)
            Icon(icon, size: 24, color: textColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                ),
              ],
            ),
          ),
          const Text(
            '›',
            style: TextStyle(fontSize: 22, color: Colors.grey, height: 1),
          ),
        ],
      ),
    ),
  );
}
