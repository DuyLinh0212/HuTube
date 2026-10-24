import '../../core/widgets/scrollable_sheet.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/storage/app_preferences.dart';
import '../../core/theme/app_theme.dart';

class BackgroundDownloadSettingsScreen extends StatefulWidget {
  const BackgroundDownloadSettingsScreen({
    super.key,
    this.preferences = const AppPreferencesStore(),
  });
  final AppPreferencesStore preferences;

  @override
  State<BackgroundDownloadSettingsScreen> createState() =>
      _BackgroundDownloadSettingsScreenState();
}

class _BackgroundDownloadSettingsScreenState
    extends State<BackgroundDownloadSettingsScreen> {
  AppPreferencesStore get _prefs => widget.preferences;

  String _bgMode = 'off';
  bool _smartDownload = false;
  String _downloadQuality = 'ask';
  bool _wifiOnly = false;
  bool _recommendations = true;
  int _smartLimitMb = 256;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  Future<void> _save(Future<void> Function() write, VoidCallback apply) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await write();
      if (mounted) setState(apply);
    } catch (_) {
      if (mounted) setState(() => _error = AppStrings.t('prefs.saveError'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bgMode = await _prefs.readBackgroundPlaybackMode();
      final smart = await _prefs.readSmartDownload();
      final quality = await _prefs.readDownloadQuality();
      final wifi = await _prefs.readDownloadWifiOnly();
      final rec = await _prefs.readDownloadRecommendations();
      final limit = await _prefs.readSmartDownloadLimitMb();

      if (mounted) {
        setState(() {
          _bgMode = bgMode;
          _smartDownload = smart;
          _downloadQuality = quality;
          _wifiOnly = wifi;
          _recommendations = rec;
          _smartLimitMb = limit;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = AppStrings.t('prefs.loadError'));
    } finally {
      if (mounted) setState(() => _loading = false);
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
    final options = [
      {'key': 'always', 'label': AppStrings.t('bgDownload.alwaysOn')},
      {'key': 'headphones', 'label': AppStrings.t('bgDownload.headphonesOnly')},
      {'key': 'off', 'label': AppStrings.t('bgDownload.off')},
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceFor(context),
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
                  AppStrings.t('bgDownload.sectionBg'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
              ),
              const Divider(),
              ...options.map((opt) {
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
                      color: AppColors.textPrimaryFor(context),
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, opt['key']),
                );
              }),
            ],
          ),
        ),
      ),
    );

    if (selected != null && mounted) {
      await _save(
        () => _prefs.writeBackgroundPlaybackMode(selected),
        () => _bgMode = selected,
      );
    }
  }

  Future<void> _selectDownloadQuality() async {
    final options = [
      {'key': 'ask', 'label': AppStrings.t('bgDownload.qualityAsk')},
      {'key': '1080p', 'label': AppStrings.t('bgDownload.qualityHigh')},
      {'key': '720p', 'label': AppStrings.t('bgDownload.qualityMedium')},
      {'key': '480p', 'label': AppStrings.t('bgDownload.qualityLow')},
      {'key': '360p', 'label': AppStrings.t('bgDownload.qualityLowest')},
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceFor(context),
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
                  AppStrings.t('bgDownload.quality'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
              ),
              const Divider(),
              ...options.map((opt) {
                final isSelected =
                    opt['key'] == _downloadQuality ||
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
                      color: AppColors.textPrimaryFor(context),
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, opt['key']),
                );
              }),
            ],
          ),
        ),
      ),
    );

    if (selected != null && mounted) {
      await _save(
        () => _prefs.writeDownloadQuality(selected),
        () => _downloadQuality = selected,
      );
    }
  }

  Future<void> _selectSmartStorage() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => ScrollableSheet(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.t('bgDownload.adjustStorage'),
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppStrings.t('bgDownload.adjustStorageDesc'),
                        style: Theme.of(ctx).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                for (final limit in [128, 256, 512, 1024])
                  ListTile(
                    leading: Icon(
                      limit == _smartLimitMb
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: Theme.of(ctx).colorScheme.primary,
                    ),
                    title: Text(
                      AppStrings.format('bgDownload.storageLimitValue', {
                        'limit': limit,
                      }),
                    ),
                    onTap: () => Navigator.pop(ctx, limit),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      await _save(
        () => _prefs.writeSmartDownloadLimitMb(selected),
        () => _smartLimitMb = selected,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppStrings.currentLang,
      builder: (context, currentLang, _) {
        final textColor = AppColors.textPrimaryFor(context);
        final mutedColor = AppColors.textSecondaryFor(context);
        final bgColor = Theme.of(context).scaffoldBackgroundColor;
        final activeToggleColor = Theme.of(context).colorScheme.primary;

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: bgColor,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
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
              ? Center(
                  child: CircularProgressIndicator(color: activeToggleColor),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    if (_error != null) ...[
                      HuTubeNotice(
                        message: _error!,
                        actionLabel: AppStrings.t('common.retry'),
                        onAction: _saving ? null : _loadSettings,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_saving) const LinearProgressIndicator(),
                    HuTubeSurface(
                      padding: EdgeInsets.zero,
                      child: Column(
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
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 2,
                            ),
                            title: Text(
                              AppStrings.t('bgDownload.playback'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            subtitle: Text(
                              '${_bgModeLabel(_bgMode)}\n${AppStrings.t('bgDownload.backgroundRequirements')}',
                              style: TextStyle(fontSize: 14, color: mutedColor),
                            ),
                            onTap: _saving ? null : _selectBgMode,
                            trailing: const Icon(Icons.chevron_right_rounded),
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
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 4,
                            ),
                            activeTrackColor: activeToggleColor,
                            activeThumbColor: Theme.of(
                              context,
                            ).colorScheme.onPrimary,
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
                                style: TextStyle(
                                  fontSize: 14,
                                  color: mutedColor,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            value: _smartDownload,
                            onChanged: _saving
                                ? null
                                : (val) => _save(
                                    () => _prefs.writeSmartDownload(val),
                                    () => _smartDownload = val,
                                  ),
                          ),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 4,
                            ),
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
                                AppStrings.format(
                                  'bgDownload.storageLimitValue',
                                  {'limit': _smartLimitMb},
                                ),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: mutedColor,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            onTap: _saving ? null : _selectSmartStorage,
                            trailing: const Icon(Icons.chevron_right_rounded),
                          ),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 4,
                            ),
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
                                style: TextStyle(
                                  fontSize: 14,
                                  color: mutedColor,
                                ),
                              ),
                            ),
                            onTap: _saving ? null : _selectDownloadQuality,
                            trailing: const Icon(Icons.chevron_right_rounded),
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 4,
                            ),
                            activeTrackColor: activeToggleColor,
                            activeThumbColor: Theme.of(
                              context,
                            ).colorScheme.onPrimary,
                            title: Text(
                              AppStrings.t('bgDownload.wifiOnly'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            value: _wifiOnly,
                            onChanged: _saving
                                ? null
                                : (val) => _save(
                                    () => _prefs.writeDownloadWifiOnly(val),
                                    () => _wifiOnly = val,
                                  ),
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 4,
                            ),
                            activeTrackColor: activeToggleColor,
                            activeThumbColor: Theme.of(
                              context,
                            ).colorScheme.onPrimary,
                            title: Text(
                              AppStrings.t('bgDownload.recommendations'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            value: _recommendations,
                            onChanged: _saving
                                ? null
                                : (val) => _save(
                                    () => _prefs.writeDownloadRecommendations(
                                      val,
                                    ),
                                    () => _recommendations = val,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
