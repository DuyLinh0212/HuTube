import 'dart:async';
import 'dart:io';

import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/material.dart';

import '../../auth.dart';
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
  String? _error;
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final path = widget.download.filePath;
    if (path == null || !await File(path).exists()) {
      if (mounted)
        setState(() => _error = 'Không tìm thấy file trên thiết bị.');
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
      pauseInBackground: !entitlements.backgroundPlayback,
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
      setState(() => _error = 'Không thể mở file video này.');
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
        const SnackBar(
          content: Text('Thiết bị không hỗ trợ PiP cho video này.'),
        ),
      );
    }
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
          if (_entitlements.pictureInPicture)
            IconButton(
              tooltip: 'Picture-in-Picture',
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
                AspectRatio(
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
                if (_entitlements.backgroundPlayback)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Chip(
                      avatar: Icon(Icons.headphones_outlined),
                      label: Text('Phát nền đang khả dụng cho gói của bạn'),
                    ),
                  ),
              ],
            ),
    );
  }
}
