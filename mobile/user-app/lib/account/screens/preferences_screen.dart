import 'package:flutter/material.dart';
import '../../auth.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_notifier.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/error_banner.dart';
import '../models/account_models.dart';
import '../services/account_service.dart';

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  late final AccountService _accountService;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  UserPreferencesModel _preferences = const UserPreferencesModel();

  @override
  void initState() {
    super.initState();
    _accountService = AccountService(widget.auth);
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _accountService.getPreferences();
      if (mounted) {
        setState(() {
          _preferences = res;
          _loading = false;
        });
        ThemeNotifier.setTheme(res.theme);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = AppStrings.t('prefs.loadError');
        });
      }
    }
  }

  Future<void> _save(UserPreferencesModel updated) async {
    setState(() {
      _preferences = updated;
      _saving = true;
      _error = null;
    });

    ThemeNotifier.setTheme(updated.theme);

    try {
      final res = await _accountService.updatePreferences(updated);
      if (mounted) setState(() => _preferences = res);
    } catch (_) {
      if (mounted) setState(() => _error = AppStrings.t('prefs.saveError'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.t('prefs.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primaryPink),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null) ...[
                    ErrorBanner(message: _error!),
                    const SizedBox(height: 16),
                  ],

                  // Theme Selection
                  Text(
                    AppStrings.t('prefs.themeHeading'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _themeOption(
                        'system',
                        AppStrings.t('prefs.themeSystem'),
                        Icons.settings_suggest_outlined,
                        isDark,
                      ),
                      const SizedBox(width: 8),
                      _themeOption(
                        'light',
                        AppStrings.t('prefs.themeLight'),
                        Icons.light_mode_outlined,
                        isDark,
                      ),
                      const SizedBox(width: 8),
                      _themeOption(
                        'dark',
                        AppStrings.t('prefs.themeDark'),
                        Icons.dark_mode_outlined,
                        isDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Language Selection
                  Text(
                    AppStrings.t('prefs.langHeading'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _langOption(
                        'vi',
                        AppStrings.t('prefs.langVi'),
                        '🇻🇳',
                        isDark,
                      ),
                      const SizedBox(width: 12),
                      _langOption(
                        'en',
                        AppStrings.t('prefs.langEn'),
                        '🇺🇸',
                        isDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Playback
                  Text(
                    AppStrings.t('prefs.playbackHeading'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _switchTile(
                    title: AppStrings.t('prefs.autoplay'),
                    subtitle: AppStrings.t('prefs.autoplaySub'),
                    value: _preferences.autoplayNext,
                    onChanged: (val) =>
                        _save(_preferences.copyWith(autoplayNext: val)),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.t('prefs.quality'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            AppStrings.t('prefs.qualitySub'),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      DropdownButton<String>(
                        value: _preferences.defaultPlaybackQuality,
                        underline: const SizedBox(),
                        dropdownColor: isDark
                            ? AppColors.darkBackgroundCard
                            : Colors.white,
                        onChanged: _saving
                            ? null
                            : (val) {
                                if (val != null) {
                                  _save(
                                    _preferences.copyWith(
                                      defaultPlaybackQuality: val,
                                    ),
                                  );
                                }
                              },
                        items: const [
                          DropdownMenuItem(
                            value: 'auto',
                            child: Text('Tự động / Auto'),
                          ),
                          DropdownMenuItem(
                            value: '1080p',
                            child: Text('1080p (FHD)'),
                          ),
                          DropdownMenuItem(
                            value: '720p',
                            child: Text('720p (HD)'),
                          ),
                          DropdownMenuItem(
                            value: '480p',
                            child: Text('480p (SD)'),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Privacy
                  Text(
                    AppStrings.t('prefs.privacyHeading'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _switchTile(
                    title: AppStrings.t('prefs.subsPrivate'),
                    subtitle: AppStrings.t('prefs.subsPrivateSub'),
                    value: _preferences.keepSubscriptionsPrivate,
                    onChanged: (val) => _save(
                      _preferences.copyWith(keepSubscriptionsPrivate: val),
                    ),
                  ),
                  const Divider(height: 24),
                  _switchTile(
                    title: AppStrings.t('prefs.playlistsPrivate'),
                    subtitle: AppStrings.t('prefs.playlistsPrivateSub'),
                    value: _preferences.keepPlaylistsPrivate,
                    onChanged: (val) =>
                        _save(_preferences.copyWith(keepPlaylistsPrivate: val)),
                  ),

                  if (_saving) ...[
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primaryPink,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppStrings.t('prefs.autoSaving'),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _themeOption(String key, String label, IconData icon, bool isDark) {
    final selected = _preferences.theme == key;
    final cardBg = isDark
        ? AppColors.darkBackgroundCard
        : AppColors.backgroundCard;
    final cardBorder = isDark ? AppColors.darkCardBorder : AppColors.cardBorder;
    final defaultText = isDark
        ? AppColors.darkTextPrimary
        : AppColors.textPrimary;

    return Expanded(
      child: GestureDetector(
        onTap: _saving ? null : () => _save(_preferences.copyWith(theme: key)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryPink.withValues(alpha: 0.15)
                : cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primaryPink : cardBorder,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected
                    ? AppColors.primaryPink
                    : AppColors.textSecondary,
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected ? AppColors.primaryPink : defaultText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _langOption(String key, String label, String flag, bool isDark) {
    final selected = AppStrings.currentLang.value == key;
    final cardBg = isDark
        ? AppColors.darkBackgroundCard
        : AppColors.backgroundCard;
    final cardBorder = isDark ? AppColors.darkCardBorder : AppColors.cardBorder;
    final defaultText = isDark
        ? AppColors.darkTextPrimary
        : AppColors.textPrimary;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            AppStrings.setLanguage(key);
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryPink.withValues(alpha: 0.15)
                : cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primaryPink : cardBorder,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(flag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected ? AppColors.primaryPink : defaultText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch.adaptive(
          value: value,
          activeTrackColor: AppColors.primaryPink,
          activeThumbColor: Colors.white,
          onChanged: _saving ? null : onChanged,
        ),
      ],
    );
  }
}
