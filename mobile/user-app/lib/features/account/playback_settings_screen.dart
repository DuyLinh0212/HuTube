import '../../core/widgets/scrollable_sheet.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/storage/app_preferences.dart';
import '../../core/theme/app_theme.dart';

class PlaybackSettingsScreen extends StatefulWidget {
  const PlaybackSettingsScreen({
    super.key,
    this.preferences = const AppPreferencesStore(),
  });
  final AppPreferencesStore preferences;

  @override
  State<PlaybackSettingsScreen> createState() => _PlaybackSettingsScreenState();
}

class _PlaybackSettingsScreenState extends State<PlaybackSettingsScreen> {
  AppPreferencesStore get _prefs => widget.preferences;

  bool _autoplayNext = true;
  int _seekSeconds = 10;
  bool _zoomToFill = false;
  bool _pipEnabled = false;
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
      final autoplay = await _prefs.readAutoplayNext();
      final seek = await _prefs.readDoubleTapSeek();
      final zoom = await _prefs.readZoomToFill();
      final pip = await _prefs.readPipEnabled();
      if (mounted) {
        setState(() {
          _autoplayNext = autoplay;
          _seekSeconds = seek;
          _zoomToFill = zoom;
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

  Future<void> _selectSeekSeconds() async {
    final options = [5, 10, 15, 20, 30, 60];

    final selected = await showModalBottomSheet<int>(
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
                  AppStrings.t('playback.doubleTapSeek'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
              ),
              const Divider(),
              ...options.map(
                (sec) => ListTile(
                  leading: Icon(
                    sec == _seekSeconds
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: sec == _seekSeconds
                        ? AppColors.primaryPink
                        : Colors.grey,
                  ),
                  title: Text(
                    AppStrings.format('playback.seconds', {'count': sec}),
                    style: TextStyle(
                      color: AppColors.textPrimaryFor(context),
                      fontWeight: sec == _seekSeconds
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, sec),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected != null && mounted) {
      await _save(
        () => _prefs.writeDoubleTapSeek(selected),
        () => _seekSeconds = selected,
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
              AppStrings.t('playback.title'),
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 20,
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
                              AppStrings.t('playback.autoplayNext'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                AppStrings.t('playback.autoplayNextDesc'),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: mutedColor,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            value: _autoplayNext,
                            onChanged: _saving
                                ? null
                                : (val) => _save(
                                    () => _prefs.writeAutoplayNext(val),
                                    () => _autoplayNext = val,
                                  ),
                          ),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 4,
                            ),
                            title: Text(
                              AppStrings.t('playback.doubleTapSeek'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                AppStrings.format('playback.seconds', {
                                  'count': _seekSeconds,
                                }),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: mutedColor,
                                ),
                              ),
                            ),
                            onTap: _saving ? null : _selectSeekSeconds,
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
                              AppStrings.t('playback.zoomToFill'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                AppStrings.t('playback.zoomToFillDesc'),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: mutedColor,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            value: _zoomToFill,
                            onChanged: _saving
                                ? null
                                : (val) => _save(
                                    () => _prefs.writeZoomToFill(val),
                                    () => _zoomToFill = val,
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
                              AppStrings.t('playback.pip'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                AppStrings.t('playback.pipDesc'),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: mutedColor,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            value: _pipEnabled,
                            onChanged: _saving
                                ? null
                                : (val) => _save(
                                    () => _prefs.writePipEnabled(val),
                                    () => _pipEnabled = val,
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
