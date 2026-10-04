import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists device-level UI preferences that should be available before the
/// first authenticated API request. Account data remains owned by the API;
/// this store only keeps presentation choices local to the installation.
class AppPreferencesStore {
  const AppPreferencesStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const languageKey = 'hutube.language';
  static const themeKey = 'hutube.theme';
  static const historyPausedKey = 'hutube.history_paused';
  static const recentSearchesKey = 'hutube.recent_searches';
  static const playbackAutoplayNextKey = 'hutube.playback_autoplay_next';
  static const playbackDoubleTapSeekKey = 'hutube.playback_double_tap_seek';
  static const playbackZoomToFillKey = 'hutube.playback_zoom_to_fill';
  static const playbackPipKey = 'hutube.playback_pip';
  static const backgroundPlaybackModeKey = 'hutube.bg_playback_mode';
  static const downloadSmartKey = 'hutube.download_smart';
  static const downloadQualityKey = 'hutube.download_quality';
  static const downloadWifiOnlyKey = 'hutube.download_wifi_only';
  static const downloadRecommendationsKey = 'hutube.download_recommendations';
  static const downloadUseSdKey = 'hutube.download_use_sd';

  Future<String?> readLanguage() => _storage.read(key: languageKey);

  Future<void> writeLanguage(String language) =>
      _storage.write(key: languageKey, value: language);

  Future<String?> readTheme() => _storage.read(key: themeKey);

  Future<void> writeTheme(String theme) =>
      _storage.write(key: themeKey, value: theme);

  Future<bool> readHistoryPaused() async =>
      (await _storage.read(key: historyPausedKey)) == 'true';

  Future<void> writeHistoryPaused(bool paused) =>
      _storage.write(key: historyPausedKey, value: '$paused');

  Future<bool> readAutoplayNext() async =>
      (await _storage.read(key: playbackAutoplayNextKey)) != 'false';

  Future<void> writeAutoplayNext(bool value) =>
      _storage.write(key: playbackAutoplayNextKey, value: '$value');

  Future<int> readDoubleTapSeek() async {
    final raw = await _storage.read(key: playbackDoubleTapSeekKey);
    return int.tryParse(raw ?? '') ?? 10;
  }

  Future<void> writeDoubleTapSeek(int seconds) =>
      _storage.write(key: playbackDoubleTapSeekKey, value: '$seconds');

  Future<bool> readZoomToFill() async =>
      (await _storage.read(key: playbackZoomToFillKey)) == 'true';

  Future<void> writeZoomToFill(bool value) =>
      _storage.write(key: playbackZoomToFillKey, value: '$value');

  Future<bool> readPipEnabled() async =>
      (await _storage.read(key: playbackPipKey)) == 'true';

  Future<void> writePipEnabled(bool value) =>
      _storage.write(key: playbackPipKey, value: '$value');

  Future<String> readBackgroundPlaybackMode() async =>
      (await _storage.read(key: backgroundPlaybackModeKey)) ?? 'always';

  Future<void> writeBackgroundPlaybackMode(String mode) =>
      _storage.write(key: backgroundPlaybackModeKey, value: mode);

  Future<bool> readSmartDownload() async =>
      (await _storage.read(key: downloadSmartKey)) == 'true';

  Future<void> writeSmartDownload(bool value) =>
      _storage.write(key: downloadSmartKey, value: '$value');

  Future<String> readDownloadQuality() async =>
      (await _storage.read(key: downloadQualityKey)) ?? 'Hỏi mỗi lần';

  Future<void> writeDownloadQuality(String quality) =>
      _storage.write(key: downloadQualityKey, value: quality);

  Future<bool> readDownloadWifiOnly() async =>
      (await _storage.read(key: downloadWifiOnlyKey)) == 'true';

  Future<void> writeDownloadWifiOnly(bool value) =>
      _storage.write(key: downloadWifiOnlyKey, value: '$value');

  Future<bool> readDownloadRecommendations() async =>
      (await _storage.read(key: downloadRecommendationsKey)) != 'false';

  Future<void> writeDownloadRecommendations(bool value) =>
      _storage.write(key: downloadRecommendationsKey, value: '$value');

  Future<bool> readDownloadUseSd() async =>
      (await _storage.read(key: downloadUseSdKey)) != 'false';

  Future<void> writeDownloadUseSd(bool value) =>
      _storage.write(key: downloadUseSdKey, value: '$value');

  Future<List<String>> readRecentSearches() async {
    final raw = await _storage.read(key: recentSearchesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  Future<void> writeRecentSearches(List<String> searches) =>
      _storage.write(key: recentSearchesKey, value: jsonEncode(searches));
}
