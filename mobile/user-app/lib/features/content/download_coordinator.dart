import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../auth.dart';
import '../../core/media/device_conditions.dart';
import '../../core/storage/app_preferences.dart';
import 'content_models.dart';
import 'content_service.dart';
import 'download_preferences.dart';
import 'local_download_manager.dart';

/// Applies settings for the whole app, including when Downloads is not open.
class DownloadCoordinator extends ChangeNotifier {
  DownloadCoordinator(
    this.auth, {
    LocalDownloadManager? manager,
    DeviceConditions? conditions,
    this.store = const AppPreferencesStore(),
  }) : manager = manager ?? LocalDownloadManager.instance,
       conditions = conditions ?? DeviceConditions.instance,
       content = ContentService(auth);
  final AuthController auth;
  final LocalDownloadManager manager;
  final DeviceConditions conditions;
  final AppPreferencesStore store;
  final ContentService content;
  DownloadPreferences preferences = const DownloadPreferences();
  List<VideoCard> _suggestions = [];
  List<VideoCard> get suggestions => preferences.recommendations
      ? _suggestions
            .where((v) => !manager.items.any((d) => d.videoId == v.id))
            .toList()
      : const [];
  bool loading = false;
  bool suggestionsFailed = false;
  bool settingsFailed = false;
  String? smartStatus;
  final Set<String> requesting = {};
  final Set<String> _attempted = {};
  int _generation = 0;
  int _session = -1;
  String? _owner;
  bool _signedIn = false;
  bool _disposed = false;
  Future<void>? _initialization;
  bool _suggestionsRequested = false;
  Future<void> _smartWork = Future.value();

  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    auth.addListener(_identityChanged);
    conditions.addListener(_conditionsChanged);
    AppPreferencesStore.mediaChanges.addListener(_settingsChanged);
    await conditions.initialize();
    if (_disposed) return;
    await refreshSettings();
  }

  void _identityChanged() {
    if (_session == auth.sessionGeneration &&
        _owner == auth.user?['userId'] &&
        _signedIn == auth.authenticated) {
      return;
    }
    _owner = auth.user?['userId'] as String?;
    _signedIn = auth.authenticated;
    _session = auth.sessionGeneration;
    _generation++;
    _suggestions = [];
    loading = false;
    requesting.clear();
    smartStatus = null;
    _attempted.clear();
    if (!_disposed) notifyListeners();
    unawaited(refreshSettings());
  }

  void _settingsChanged() => unawaited(refreshSettings());
  void _conditionsChanged() {
    unawaited(_applyPolicy());
    _queueSmart();
  }

  bool _current(int generation, int session) =>
      !_disposed &&
      generation == _generation &&
      session == auth.sessionGeneration &&
      auth.authenticated;

  Future<void> refreshSettings() async {
    if (_disposed) return;
    final generation = ++_generation;
    final session = auth.sessionGeneration;
    _session = session;
    _owner = auth.user?['userId'] as String?;
    _signedIn = auth.authenticated;
    try {
      final next = await DownloadPreferences.load(store);
      if (_disposed || generation != _generation) return;
      preferences = next;
      settingsFailed = false;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      // Storage failures must not start unrequested downloads over mobile data.
      preferences = const DownloadPreferences(recommendations: false);
      settingsFailed = true;
    }
    loading = false;
    if (!preferences.recommendations) _suggestions = [];
    notifyListeners();
    await _applyPolicy();
    if (!_current(generation, session)) return;
    if (_suggestionsRequested && preferences.recommendations) {
      unawaited(loadSuggestions());
    }
    _queueSmart();
  }

  Future<void> _applyPolicy() => manager.configurePolicy(
    connected: conditions.connected,
    wifi: conditions.wifi,
    wifiOnly: preferences.wifiOnly,
    smartEnabled: preferences.smart,
    smartBudget: preferences.limitBytes,
  );

  Future<void> loadSuggestions() async {
    _suggestionsRequested = true;
    if (_disposed ||
        !auth.authenticated ||
        !preferences.recommendations ||
        loading) {
      return;
    }
    final generation = _generation, session = auth.sessionGeneration;
    loading = true;
    suggestionsFailed = false;
    notifyListeners();
    try {
      final page = await content.feed(
        explore: false,
        pageSize: 12,
        recommendationBudget: const Duration(milliseconds: 1200),
      );
      if (!_current(generation, session)) return;
      _suggestions = page.items.take(6).toList();
    } catch (_) {
      if (_current(generation, session)) suggestionsFailed = true;
    } finally {
      if (_current(generation, session)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void _queueSmart() {
    if (_disposed) return;
    _smartWork = _smartWork.then((_) => _runSmart()).catchError((Object _) {});
  }

  @visibleForTesting
  Future<void> get smartIdle => _smartWork;

  Future<void> _runSmart() async {
    final generation = _generation, session = auth.sessionGeneration;
    bool current() =>
        _current(generation, session) && preferences.smart && conditions.wifi;
    if (!current()) return;
    smartStatus = null;
    await manager.ensureLoaded();
    if (!current() || manager.ownerId != auth.user?['userId']) return;
    final existing = await content.downloads();
    if (!current()) return;
    final page = await content.feed(
      explore: false,
      pageSize: 12,
      recommendationBudget: const Duration(milliseconds: 1200),
    );
    if (!current()) return;
    for (final video in page.items.take(12)) {
      if (!current()) return;
      final smart = manager.items
          .where((d) => d.smart && d.status != 'failed')
          .toList();
      final used = smart.fold<int>(0, (sum, d) => sum + d.totalBytes);
      if (smart.length >= 3 || used >= preferences.limitBytes) return;
      if (existing.any((d) => d['videoId'] == video.id) ||
          manager.items.any((d) => d.videoId == video.id) ||
          !_attempted.add(video.id)) {
        continue;
      }
      try {
        final options = await content.downloadOptions(video.id);
        if (!current()) return;
        final chosen = selectDownloadRendition(
          options,
          preferences.quality,
          automatic: true,
        );
        if (chosen == null ||
            chosen.fileSize <= 0 ||
            chosen.fileSize > preferences.limitBytes - used) {
          continue;
        }
        await _create(video, chosen, generation, session, smart: true);
      } on ApiFailure catch (error) {
        if (current() && error.code == 'DOWNLOAD_NOT_INCLUDED') {
          smartStatus = 'downloads.planRequired';
          notifyListeners();
          return;
        }
      } catch (_) {
        // A video with no download permission is skipped, never bypassed.
      }
    }
    if (current() && !manager.items.any((d) => d.smart)) {
      smartStatus = 'downloads.smartUnavailable';
      notifyListeners();
    }
  }

  Future<bool> download(
    VideoCard video, {
    Future<Rendition?> Function(List<Rendition>)? choose,
  }) async {
    if (!auth.authenticated || !requesting.add(video.id)) return false;
    final generation = _generation, session = auth.sessionGeneration;
    notifyListeners();
    try {
      final options = await content.downloadOptions(video.id);
      if (!_current(generation, session)) return false;
      final chosen =
          selectDownloadRendition(options, preferences.quality) ??
          (choose == null ? null : await choose(options));
      if (chosen == null || !_current(generation, session)) return false;
      return await _create(video, chosen, generation, session);
    } finally {
      if (!_disposed) {
        requesting.remove(video.id);
        notifyListeners();
      }
    }
  }

  Future<bool> _create(
    VideoCard video,
    Rendition chosen,
    int generation,
    int session, {
    bool smart = false,
  }) async {
    if (!_current(generation, session)) return false;
    final record = await content.createDownload(video.id, chosen.quality);
    if (!_current(generation, session) ||
        manager.ownerId != auth.user?['userId']) {
      return false;
    }
    if (smart && (!preferences.smart || !conditions.wifi)) return false;
    final size = asInt(record['fileSize']);
    if (smart && (size <= 0 || size > chosen.fileSize)) return false;
    await manager.enqueue(
      id: '${record['videoDownloadId'] ?? ''}',
      videoId: video.id,
      title: '${record['title'] ?? video.title}',
      quality: '${record['quality'] ?? chosen.quality}',
      url: '${record['fileUrl'] ?? ''}',
      fileSize: size,
      smart: smart,
    );
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    auth.removeListener(_identityChanged);
    conditions.removeListener(_conditionsChanged);
    AppPreferencesStore.mediaChanges.removeListener(_settingsChanged);
    super.dispose();
  }
}
