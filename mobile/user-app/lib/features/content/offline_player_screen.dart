import 'dart:async';
import 'dart:io';

import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import 'local_download_manager.dart';
import 'media_entitlements.dart';

class OfflinePlayerScreen extends StatefulWidget {
  const OfflinePlayerScreen({
    super.key,
    required this.auth,
    required this.download,
  });
  final AuthController auth;
  final LocalDownload download;
  @override
  State<OfflinePlayerScreen> createState() => _OfflinePlayerScreenState();
}

class _OfflinePlayerScreenState extends State<OfflinePlayerScreen> {
  NativeVideoPlayerController? _player;
  BackgroundPlaybackGuard? _backgroundPlaybackGuard;
  MediaEntitlements _entitlements = const MediaEntitlements.none();
  bool _ready = false;
  bool _backgroundPlaybackEnabled = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_identityChanged);
    _open();
  }

  void _identityChanged() {
    if (LocalDownloadManager.instance.ownerId != widget.auth.user?['userId'] ||
        !widget.auth.authenticated) {
      unawaited(_player?.dispose());
      _player = null;
      if (mounted) setState(() => _error = AppStrings.t('common.loginAgain'));
    }
  }

  Future<void> _open() async {
    final owner = widget.auth.user?['userId'];
    if (owner == null ||
        LocalDownloadManager.instance.ownerId != owner ||
        !LocalDownloadManager.instance.items.any(
          (item) => item.id == widget.download.id,
        )) {
      setState(() => _error = AppStrings.t('common.loginAgain'));
      return;
    }
    final path = widget.download.filePath;
    if (path == null || !await File(path).exists()) {
      if (mounted) {
        setState(() => _error = AppStrings.t('offline.missingFile'));
      }
      return;
    }
    final entitlements = await MediaEntitlements.load(widget.auth);
    if (!mounted) return;
    final player = NativeVideoPlayerController(
      id: widget.download.id.hashCode & 0x7fffffff,
      autoPlay: false,
      showNativeControls: true,
      allowsPictureInPicture: entitlements.pictureInPicture,
      canStartPictureInPictureAutomatically: entitlements.pictureInPicture,
    );
    final guard = BackgroundPlaybackGuard(
      player,
      // Background playback is opt-in for each offline video as well.
      pauseInBackground: true,
    );
    setState(() {
      _entitlements = entitlements;
      _player = player;
      _backgroundPlaybackGuard = guard;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_player, player)) {
        unawaited(_initializePlayer(player, path));
      }
    });
  }

  Future<void> _initializePlayer(
    NativeVideoPlayerController player,
    String path,
  ) async {
    try {
      await player.initialize();
      await player.loadFile(path: path);
      if (mounted && identical(_player, player)) {
        setState(() => _ready = true);
      }
    } catch (_) {
      if (!mounted || !identical(_player, player)) return;
      _backgroundPlaybackGuard?.dispose();
      _backgroundPlaybackGuard = null;
      _player = null;
      unawaited(player.dispose());
      setState(() => _error = AppStrings.t('offline.openError'));
    }
  }

  Future<void> _enterPictureInPicture() async {
    final player = _player;
    if (player == null || !_ready) return;
    if (Platform.isAndroid && !player.isFullScreen) {
      await player.enterFullScreen();
    }
    final started = await player.enterPictureInPicture();
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('offline.pipUnsupported'))),
      );
    }
  }

  void _toggleBackgroundPlayback() {
    if (!_entitlements.backgroundPlayback || _backgroundPlaybackGuard == null) {
      return;
    }
    final enabled = !_backgroundPlaybackEnabled;
    _backgroundPlaybackGuard!.pauseInBackground = !enabled;
    setState(() => _backgroundPlaybackEnabled = enabled);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? AppStrings.t('watch.backgroundEnabled')
              : AppStrings.t('watch.backgroundDisabled'),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _backgroundPlaybackGuard?.dispose();
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.download.title),
        actions: [
          if (_entitlements.backgroundPlayback)
            IconButton(
              tooltip: AppStrings.t('watch.background'),
              icon: Icon(
                _backgroundPlaybackEnabled
                    ? Icons.headphones_rounded
                    : Icons.headphones_outlined,
              ),
              onPressed: _ready ? _toggleBackgroundPlayback : null,
            ),
          if (_entitlements.pictureInPicture)
            IconButton(
              tooltip: AppStrings.t('offline.pipTooltip'),
              icon: const Icon(Icons.picture_in_picture_alt_outlined),
              onPressed: _ready ? _enterPictureInPicture : null,
            ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : player == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Flexible(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      children: [
                        NativeVideoPlayer(controller: player),
                        if (!_ready)
                          const Positioned.fill(
                            child: ColoredBox(
                              color: Color(0xB3171927),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primaryPink,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_entitlements.backgroundPlayback)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton.icon(
                      onPressed: _ready ? _toggleBackgroundPlayback : null,
                      icon: Icon(
                        _backgroundPlaybackEnabled
                            ? Icons.headphones_rounded
                            : Icons.headphones_outlined,
                      ),
                      label: Text(
                        _backgroundPlaybackEnabled
                            ? AppStrings.t('watch.backgroundEnabledShort')
                            : AppStrings.t('watch.background'),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
