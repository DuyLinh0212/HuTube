import 'dart:async';

import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../core/storage/app_preferences.dart';
import 'content_models.dart';
import 'content_service.dart';
import 'media_entitlements.dart';

/// App-level owner for the one active native playback session. Keeping the
/// controller above the router lets the same native session move from the
/// watch page to the in-app mini-player without stopping the video.
class PlaybackSession extends ChangeNotifier {
  NativeVideoPlayerController? player;
  BackgroundPlaybackGuard? _backgroundGuard;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<PlayerActivityState>? _stateSubscription;
  AuthController? _auth;
  ContentService? _content;
  List<Rendition> renditions = const [];
  Rendition? selectedRendition;
  MediaEntitlements entitlements = const MediaEntitlements.none();
  String? videoId;
  String title = '';
  String channelName = '';
  String? thumbnailUrl;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool ready = false;
  bool minimized = false;
  bool isPlaying = false;
  bool backgroundPlaybackEnabled = false;
  bool _initializing = false;
  int _lastSavedSecond = 0;

  // Queue & autoplay state
  List<VideoCard> queue = [];
  int queueIndex = -1;
  bool autoplayNext = true;
  bool isShuffle = false;
  bool isLoop = false;
  bool isHistoryPaused = false;
  bool _advancing = false;
  VoidCallback? onVideoCompleted;

  bool get hasVideo => player != null && videoId != null;

  bool get hasNext =>
      isLoop ||
      (queue.isNotEmpty && (isShuffle || queueIndex + 1 < queue.length));

  VideoCard? get nextVideoCard {
    if (queue.isEmpty) return null;
    if (isShuffle) {
      if (queue.length == 1) return queue.first;
      final candidates = [
        for (var i = 0; i < queue.length; i++)
          if (i != queueIndex) queue[i],
      ];
      if (candidates.isEmpty) return null;
      candidates.shuffle();
      return candidates.first;
    }
    final nextIdx = queueIndex + 1;
    if (nextIdx < queue.length) return queue[nextIdx];
    if (isLoop) return queue.first;
    return null;
  }

  bool get hasPrevious => queueIndex > 0;

  VideoCard? get previousVideoCard {
    if (queue.isEmpty || queueIndex <= 0) return null;
    return queue[queueIndex - 1];
  }

  void setQueue(List<VideoCard> items, {int initialIndex = 0}) {
    queue = List.from(items);
    queueIndex = initialIndex.clamp(0, queue.isEmpty ? 0 : queue.length - 1);
    notifyListeners();
  }

  void addToQueue(VideoCard item) {
    if (!queue.any((element) => element.id == item.id)) {
      queue.add(item);
      notifyListeners();
    }
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < queue.length) {
      queue.removeAt(index);
      if (queueIndex >= queue.length) {
        queueIndex = queue.length - 1;
      }
      notifyListeners();
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= queue.length ||
        newIndex < 0 ||
        newIndex > queue.length) {
      return;
    }
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final currentPlaying = queueIndex >= 0 && queueIndex < queue.length
        ? queue[queueIndex]
        : null;
    final item = queue.removeAt(oldIndex);
    queue.insert(newIndex, item);
    if (currentPlaying != null) {
      queueIndex = queue.indexOf(currentPlaying);
    }
    notifyListeners();
  }

  void clearQueue() {
    queue = [];
    queueIndex = -1;
    notifyListeners();
  }

  void toggleAutoplay() {
    autoplayNext = !autoplayNext;
    notifyListeners();
  }

  void toggleShuffle() {
    isShuffle = !isShuffle;
    notifyListeners();
  }

  void toggleLoop() {
    isLoop = !isLoop;
    notifyListeners();
  }

  void setHistoryPaused(bool paused) {
    isHistoryPaused = paused;
    notifyListeners();
  }

  Future<NativeVideoPlayerController> start({
    required AuthController auth,
    required VideoDetail video,
    required List<Rendition> videoRenditions,
    required MediaEntitlements mediaEntitlements,
    required String sourceUrl,
    required int resumeAt,
  }) async {
    _advancing = false;
    final matchedIdx = queue.indexWhere((item) => item.id == video.id);
    if (matchedIdx >= 0) {
      queueIndex = matchedIdx;
    }

    if (videoId == video.id && player != null) {
      title = video.title;
      channelName = video.channelName;
      thumbnailUrl = video.thumbnailUrl;
      renditions = _sort(videoRenditions);
      minimized = false;
      notifyListeners();
      return player!;
    }

    await dismiss(notify: false);
    final prefs = const AppPreferencesStore();
    final pipPref = await prefs.readPipEnabled();
    final allowPip = mediaEntitlements.pictureInPicture || pipPref;
    autoplayNext = await prefs.readAutoplayNext();

    final controller = NativeVideoPlayerController(
      id: video.id.hashCode & 0x7fffffff,
      autoPlay: false,
      showNativeControls: false,
      mediaInfo: NativeVideoPlayerMediaInfo(
        title: video.title,
        subtitle: video.channelName,
        artworkUrl: video.thumbnailUrl,
      ),
      allowsPictureInPicture: allowPip,
      canStartPictureInPictureAutomatically: allowPip,
    );
    _auth = auth;
    _content = ContentService(auth);
    videoId = video.id;
    title = video.title;
    channelName = video.channelName;
    thumbnailUrl = video.thumbnailUrl;
    entitlements = mediaEntitlements;
    renditions = _sort(videoRenditions);
    selectedRendition = _forUrl(renditions, sourceUrl);
    position = Duration(seconds: resumeAt);
    duration = Duration(seconds: video.duration);
    ready = false;
    minimized = false;
    isPlaying = false;
    backgroundPlaybackEnabled = false;
    _initializing = false;
    _lastSavedSecond = resumeAt;
    player = controller;
    _backgroundGuard = BackgroundPlaybackGuard(
      controller,
      // Background playback is opt-in for each active video. The native
      // player will still publish its MediaSession when it is playing, but
      // this guard keeps normal video playback from continuing silently when
      // the user leaves the app.
      pauseInBackground: true,
    );
    _positionSubscription = controller.positionStream.listen((value) {
      position = value;
      final seconds = value.inSeconds;
      if (_auth?.authenticated == true && seconds - _lastSavedSecond >= 10) {
        _lastSavedSecond = seconds;
        final id = videoId;
        if (id != null) {
          unawaited(
            _content?.progress(id, seconds, saveHistory: !isHistoryPaused),
          );
        }
      }

      // Detect end of video for loop or autoplay next
      if (duration > Duration.zero &&
          position >= duration - const Duration(milliseconds: 400) &&
          !_advancing) {
        if (isLoop) {
          seekTo(Duration.zero);
          player?.play();
        } else if (autoplayNext) {
          _advancing = true;
          onVideoCompleted?.call();
          Future.delayed(const Duration(seconds: 2), () {
            _advancing = false;
          });
        }
      }

      notifyListeners();
    });
    _stateSubscription = controller.playerStateStream.listen((state) {
      isPlaying = state.isPlaying;
      notifyListeners();
    });
    _durationSubscription = controller.durationStream.listen((value) {
      duration = value;
      notifyListeners();
    });
    notifyListeners();
    return controller;
  }

  List<Rendition> _sort(List<Rendition> items) =>
      [...items]..sort((a, b) => a.height.compareTo(b.height));

  Rendition? _forUrl(List<Rendition> items, String url) {
    for (final item in items) {
      if (item.url == url) return item;
    }
    return items.isEmpty ? null : items.last;
  }

  Future<void> initialize(String url, {required int resumeAt}) async {
    final controller = player;
    if (controller == null || ready || _initializing) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw const FormatException('Invalid playback URL');
    }
    _initializing = true;
    try {
      await controller.initialize();
      await controller.loadUrl(
        url: url,
        startAt: resumeAt > 0 ? Duration(seconds: resumeAt) : null,
      );
      if (!identical(player, controller)) return;
      ready = true;
      duration = controller.duration;
      position = controller.currentPosition;
      notifyListeners();
    } catch (_) {
      if (identical(player, controller)) {
        await dismiss();
      }
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  Future<void> changeQuality(Rendition rendition) async {
    final controller = player;
    if (controller == null || !ready) return;
    final wasPlaying = controller.activityState.isPlaying;
    final at = controller.currentPosition;
    await controller.loadUrl(url: rendition.url, startAt: at, force: true);
    selectedRendition = rendition;
    if (wasPlaying) await controller.play();
    notifyListeners();
  }

  Future<void> setSpeed(double value) async {
    await player?.setSpeed(value);
    notifyListeners();
  }

  Future<void> togglePlayback() async {
    final controller = player;
    if (controller == null || !ready) return;
    if (controller.activityState.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  /// Enables background audio for the current video after an explicit user
  /// action. The native player already owns the Android MediaSession/iOS Now
  /// Playing integration, so changing the guard is enough to keep its audio
  /// alive when the app is backgrounded.
  Future<bool> setBackgroundPlaybackEnabled(bool enabled) async {
    if (enabled && !entitlements.backgroundPlayback) return false;
    final guard = _backgroundGuard;
    if (guard == null || !hasVideo) return false;
    guard.pauseInBackground = !enabled;
    backgroundPlaybackEnabled = enabled;
    notifyListeners();
    return true;
  }

  Future<void> seekBy(int seconds) async {
    final controller = player;
    if (controller == null || !ready) return;
    final target = controller.currentPosition + Duration(seconds: seconds);
    final max = controller.duration;
    await controller.seekTo(
      target < Duration.zero ? Duration.zero : (target > max ? max : target),
    );
  }

  Future<void> seekTo(Duration target) async {
    final controller = player;
    if (controller == null || !ready) return;
    await controller.seekTo(target);
  }

  void minimize() {
    if (!hasVideo) return;
    minimized = true;
    notifyListeners();
  }

  void restore() {
    if (!hasVideo) return;
    minimized = false;
    notifyListeners();
  }

  Future<void> dismiss({bool notify = true}) async {
    final oldPlayer = player;
    final finalVideoId = videoId;
    final finalSeconds = position.inSeconds;
    if (_auth?.authenticated == true &&
        finalVideoId != null &&
        finalSeconds > _lastSavedSecond) {
      unawaited(
        _content?.progress(
          finalVideoId,
          finalSeconds,
          saveHistory: !isHistoryPaused,
        ),
      );
    }
    player = null;
    videoId = null;
    minimized = false;
    ready = false;
    isPlaying = false;
    backgroundPlaybackEnabled = false;
    title = '';
    channelName = '';
    thumbnailUrl = null;
    renditions = const [];
    selectedRendition = null;
    _backgroundGuard?.dispose();
    _backgroundGuard = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await _durationSubscription?.cancel();
    _durationSubscription = null;
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    if (notify) notifyListeners();
    if (oldPlayer != null) {
      // Let Flutter detach the platform view before releasing its controller.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(oldPlayer.dispose());
      });
    }
  }

  @override
  void dispose() {
    _backgroundGuard?.dispose();
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_stateSubscription?.cancel());
    unawaited(player?.dispose());
    super.dispose();
  }
}
