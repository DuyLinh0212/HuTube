import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/storage/app_preferences.dart';
import '../../core/theme/app_theme.dart';

class PlaybackSettingsScreen extends StatefulWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  State<PlaybackSettingsScreen> createState() => _PlaybackSettingsScreenState();
}

class _PlaybackSettingsScreenState extends State<PlaybackSettingsScreen> {
  final _prefs = const AppPreferencesStore();

  bool _autoplayNext = true;
  int _seekSeconds = 10;
  bool _zoomToFill = false;
  bool _pipEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
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
  }

  Future<void> _selectSeekSeconds() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final options = [5, 10, 15, 20, 30, 60];

    final selected = await showModalBottomSheet<int>(
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
                  AppStrings.t('playback.doubleTapSeek'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textPrimary,
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
                      color: isDark ? Colors.white : AppColors.textPrimary,
                      fontWeight:
                          sec == _seekSeconds ? FontWeight.bold : FontWeight.normal,
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
      setState(() => _seekSeconds = selected);
      await _prefs.writeDoubleTapSeek(selected);
    }
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
              AppStrings.t('playback.title'),
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator(color: activeToggleColor))
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    SwitchListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      activeTrackColor: activeToggleColor,
                      activeThumbColor: Colors.white,
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
                          style: TextStyle(fontSize: 13, color: mutedColor, height: 1.3),
                        ),
                      ),
                      value: _autoplayNext,
                      onChanged: (val) {
                        setState(() => _autoplayNext = val);
                        _prefs.writeAutoplayNext(val);
                      },
                    ),
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
                          AppStrings.format('playback.seconds', {'count': _seekSeconds}),
                          style: TextStyle(fontSize: 13, color: mutedColor),
                        ),
                      ),
                      onTap: _selectSeekSeconds,
                    ),
                    SwitchListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      activeTrackColor: activeToggleColor,
                      activeThumbColor: Colors.white,
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
                          style: TextStyle(fontSize: 13, color: mutedColor, height: 1.3),
                        ),
                      ),
                      value: _zoomToFill,
                      onChanged: (val) {
                        setState(() => _zoomToFill = val);
                        _prefs.writeZoomToFill(val);
                      },
                    ),
                    SwitchListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      activeTrackColor: activeToggleColor,
                      activeThumbColor: Colors.white,
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
                          style: TextStyle(fontSize: 13, color: mutedColor, height: 1.3),
                        ),
                      ),
                      value: _pipEnabled,
                      onChanged: (val) {
                        setState(() => _pipEnabled = val);
                        _prefs.writePipEnabled(val);
                      },
                    ),
                  ],
                ),
        );
      },
    );
  }
}
