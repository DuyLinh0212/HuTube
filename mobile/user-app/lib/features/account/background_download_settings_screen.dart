import '../../auth.dart';
import '../content/media_feature_gate.dart';
import '../../core/widgets/scrollable_sheet.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/storage/app_preferences.dart';
import '../../core/theme/app_theme.dart';

class BackgroundDownloadSettingsScreen extends StatefulWidget {
  const BackgroundDownloadSettingsScreen({
    super.key,
    this.auth,
    this.preferences = const AppPreferencesStore(),
  });
  final AuthController? auth;
  final AppPreferencesStore preferences;

  @override
  State<BackgroundDownloadSettingsScreen> createState() =>
      _BackgroundDownloadSettingsScreenState();
}

class _BackgroundDownloadSettingsScreenState
    extends State<BackgroundDownloadSettingsScreen> {
  AppPreferencesStore get _prefs => widget.preferences;

  String _bgMode = 'off';
  String _downloadQuality = 'ask';
  bool _wifiOnly = false;
  bool _pipEnabled = false;
  bool _recommendations = true;
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
      final quality = await _prefs.readDownloadQuality();
      final wifi = await _prefs.readDownloadWifiOnly();
      final rec = await _prefs.readDownloadRecommendations();
      final pip = await _prefs.readPipEnabled();

      if (mounted) {
        setState(() {
          _bgMode = bgMode;
          _downloadQuality = quality;
          _wifiOnly = wifi;
          _recommendations = rec;
          _pipEnabled = pip;
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
      useRootNavigator: true,
      useSafeArea: true,
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
      if (selected != 'off' &&
          widget.auth != null &&
          !await requireMediaFeature(
            context,
            widget.auth!,
            PlanMediaFeature.background,
          )) {
        return;
      }
      if (!mounted) return;
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
      useRootNavigator: true,
      useSafeArea: true,
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

  Future<void> _togglePip(bool value) async {
    if (value &&
        widget.auth != null &&
        !await requireMediaFeature(
          context,
          widget.auth!,
          PlanMediaFeature.pip,
        )) {
      return;
    }
    if (!mounted) return;
    await _save(() => _prefs.writePipEnabled(value), () => _pipEnabled = value);
  }

  Widget _heading(String key, IconData icon) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            AppStrings.t(key),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: AppStrings.currentLang,
    builder: (context, _, _) => Scaffold(
      appBar: AppBar(title: Text(AppStrings.t('media.settingsTitle'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                if (_error != null)
                  HuTubeNotice(
                    message: _error!,
                    actionLabel: AppStrings.t('common.retry'),
                    onAction: _saving ? null : _loadSettings,
                  ),
                if (_saving) const LinearProgressIndicator(),
                _heading(
                  'media.playbackSection',
                  Icons.play_circle_outline_rounded,
                ),
                HuTubeSurface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        key: const ValueKey('automatic-pip-toggle'),
                        title: Text(AppStrings.t('playback.pip')),
                        subtitle: Text(AppStrings.t('media.pipAutomatic')),
                        value: _pipEnabled,
                        onChanged: _saving ? null : _togglePip,
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        title: Text(AppStrings.t('bgDownload.sectionBg')),
                        subtitle: Text(_bgModeLabel(_bgMode)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _saving ? null : _selectBgMode,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.workspace_premium_outlined,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              AppStrings.t('media.premiumHint'),
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(height: 1.5),
                            ),
                          ),
                        ],
                      ),
                      if (widget.auth != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () =>
                                openMediaPlans(context, widget.auth!),
                            child: Text(AppStrings.t('media.viewPlans')),
                          ),
                        ),
                    ],
                  ),
                ),
                _heading('bgDownload.sectionDownload', Icons.download_outlined),
                HuTubeSurface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(AppStrings.t('bgDownload.quality')),
                        subtitle: Text(_qualityLabel(_downloadQuality)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _saving ? null : _selectDownloadQuality,
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile.adaptive(
                        title: Text(AppStrings.t('bgDownload.wifiOnly')),
                        subtitle: Text(AppStrings.t('media.wifiHint')),
                        value: _wifiOnly,
                        onChanged: _saving
                            ? null
                            : (value) => _save(
                                () => _prefs.writeDownloadWifiOnly(value),
                                () => _wifiOnly = value,
                              ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile.adaptive(
                        title: Text(AppStrings.t('bgDownload.recommendations')),
                        subtitle: Text(
                          AppStrings.t('media.recommendationsHint'),
                        ),
                        value: _recommendations,
                        onChanged: _saving
                            ? null
                            : (value) => _save(
                                () =>
                                    _prefs.writeDownloadRecommendations(value),
                                () => _recommendations = value,
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    ),
  );
}
