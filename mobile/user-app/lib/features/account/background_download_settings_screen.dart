import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/storage/app_preferences.dart';
import '../../core/theme/app_theme.dart';

class BackgroundDownloadSettingsScreen extends StatefulWidget {
  const BackgroundDownloadSettingsScreen({super.key});

  @override
  State<BackgroundDownloadSettingsScreen> createState() =>
      _BackgroundDownloadSettingsScreenState();
}

class _BackgroundDownloadSettingsScreenState
    extends State<BackgroundDownloadSettingsScreen> {
  final _prefs = const AppPreferencesStore();

  String _bgMode = 'always';
  bool _smartDownload = false;
  String _downloadQuality = 'ask';
  bool _wifiOnly = false;
  bool _recommendations = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final bgMode = await _prefs.readBackgroundPlaybackMode();
    final smart = await _prefs.readSmartDownload();
    final quality = await _prefs.readDownloadQuality();
    final wifi = await _prefs.readDownloadWifiOnly();
    final rec = await _prefs.readDownloadRecommendations();

    if (mounted) {
      setState(() {
        _bgMode = bgMode;
        _smartDownload = smart;
        _downloadQuality = quality;
        _wifiOnly = wifi;
        _recommendations = rec;
        _loading = false;
      });
    }
  }

  String _bgModeLabel(String mode) {
    switch (mode) {
      case 'off':
        return AppStrings.t('bgDownload.off');
      case 'headphones':
        return AppStrings.t('bgDownload.headphonesOnly');
      case 'always':
      default:
        return AppStrings.t('bgDownload.alwaysOn');
    }
  }

  String _qualityLabel(String quality) {
    switch (quality) {
      case '1080p':
      case 'Chất lượng cao (1080p)':
        return AppStrings.t('bgDownload.qualityHigh');
      case '720p':
      case 'Chất lượng tiêu chuẩn (720p)':
        return AppStrings.t('bgDownload.qualityMedium');
      case '480p':
      case 'Chất lượng trung bình (480p)':
        return AppStrings.t('bgDownload.qualityLow');
      case '360p':
      case 'Chất lượng thấp (360p)':
        return AppStrings.t('bgDownload.qualityLowest');
      case 'ask':
      case 'Hỏi mỗi lần':
      default:
        return AppStrings.t('bgDownload.qualityAsk');
    }
  }

  Future<void> _selectBgMode() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final options = [
      {'key': 'always', 'label': AppStrings.t('bgDownload.alwaysOn')},
      {'key': 'headphones', 'label': AppStrings.t('bgDownload.headphonesOnly')},
      {'key': 'off', 'label': AppStrings.t('bgDownload.off')},
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  AppStrings.t('bgDownload.sectionBg'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
              const Divider(),
              ...options.map(
                (opt) {
                  final isSelected = opt['key'] == _bgMode;
                  return ListTile(
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: isSelected ? AppColors.primaryPink : Colors.grey,
                    ),
                    title: Text(
                      opt['label']!,
                      style: TextStyle(
                        color: isDark ? Colors.white : AppColors.textPrimary,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, opt['key']),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    if (selected != null && mounted) {
      setState(() => _bgMode = selected);
      await _prefs.writeBackgroundPlaybackMode(selected);
    }
  }

  Future<void> _selectDownloadQuality() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final options = [
      {'key': 'ask', 'label': AppStrings.t('bgDownload.qualityAsk')},
      {'key': '1080p', 'label': AppStrings.t('bgDownload.qualityHigh')},
      {'key': '720p', 'label': AppStrings.t('bgDownload.qualityMedium')},
      {'key': '480p', 'label': AppStrings.t('bgDownload.qualityLow')},
      {'key': '360p', 'label': AppStrings.t('bgDownload.qualityLowest')},
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  AppStrings.t('bgDownload.quality'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
              const Divider(),
              ...options.map(
                (opt) {
                  final isSelected = opt['key'] == _downloadQuality ||
                      opt['label'] == _downloadQuality;
                  return ListTile(
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: isSelected ? AppColors.primaryPink : Colors.grey,
                    ),
                    title: Text(
                      opt['label']!,
                      style: TextStyle(
                        color: isDark ? Colors.white : AppColors.textPrimary,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, opt['key']),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    if (selected != null && mounted) {
      setState(() => _downloadQuality = selected);
      await _prefs.writeDownloadQuality(selected);
    }
  }

  void _showSmartStorageDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: Text(AppStrings.t('bgDownload.adjustStorage')),
        content: Text(AppStrings.t('bgDownload.adjustStorageDesc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.t('bgDownload.dialogDone')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppStrings.currentLang,
      builder: (context, currentLang, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? Colors.white : AppColors.textPrimary;
        final mutedColor = isDark ? const Color(0xFFAAAAAA) : AppColors.textMuted;
        final bgColor = isDark ? const Color(0xFF0F0F0F) : AppColors.background;
        const activeToggleColor = AppColors.primaryPink;

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: bgColor,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: textColor),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              AppStrings.t('bgDownload.title'),
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator(color: activeToggleColor))
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // SECTION: Phát trong nền
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text(
                        AppStrings.t('bgDownload.sectionBg'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: mutedColor,
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                      title: Text(
                        AppStrings.t('bgDownload.playback'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      subtitle: Text(
                        _bgModeLabel(_bgMode),
                        style: TextStyle(fontSize: 13, color: mutedColor),
                      ),
                      onTap: _selectBgMode,
                    ),

                    const SizedBox(height: 16),

                    // SECTION: Tải xuống
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text(
                        AppStrings.t('bgDownload.sectionDownload'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: mutedColor,
                        ),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      activeTrackColor: activeToggleColor,
                      activeThumbColor: Colors.white,
                      title: Text(
                        AppStrings.t('bgDownload.smartDownload'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          AppStrings.t('bgDownload.smartDownloadDesc'),
                          style: TextStyle(fontSize: 13, color: mutedColor, height: 1.3),
                        ),
                      ),
                      value: _smartDownload,
                      onChanged: (val) {
                        setState(() => _smartDownload = val);
                        _prefs.writeSmartDownload(val);
                      },
                    ),
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      title: Text(
                        AppStrings.t('bgDownload.adjustStorage'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          AppStrings.t('bgDownload.adjustStorageDesc'),
                          style: TextStyle(fontSize: 13, color: mutedColor, height: 1.3),
                        ),
                      ),
                      onTap: _showSmartStorageDialog,
                    ),
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      title: Text(
                        AppStrings.t('bgDownload.quality'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _qualityLabel(_downloadQuality),
                          style: TextStyle(fontSize: 13, color: mutedColor),
                        ),
                      ),
                      onTap: _selectDownloadQuality,
                    ),
                    SwitchListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      activeTrackColor: activeToggleColor,
                      activeThumbColor: Colors.white,
                      title: Text(
                        AppStrings.t('bgDownload.wifiOnly'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      value: _wifiOnly,
                      onChanged: (val) {
                        setState(() => _wifiOnly = val);
                        _prefs.writeDownloadWifiOnly(val);
                      },
                    ),
                    SwitchListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      activeTrackColor: activeToggleColor,
                      activeThumbColor: Colors.white,
                      title: Text(
                        AppStrings.t('bgDownload.recommendations'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      value: _recommendations,
                      onChanged: (val) {
                        setState(() => _recommendations = val);
                        _prefs.writeDownloadRecommendations(val);
                      },
                    ),
                  ],
                ),
        );
      },
    );
  }
}
