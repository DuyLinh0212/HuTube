import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import 'playback_session.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.session});
  final PlaybackSession session;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      final player = session.player;
      final videoId = session.videoId;
      if (!session.minimized || player == null || videoId == null) {
        return const SizedBox.shrink();
      }
      final width = (MediaQuery.sizeOf(context).width * .64).clamp(
        205.0,
        270.0,
      );
      return Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.bottomRight,
          child: Container(
            width: width,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: .12)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 22,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    session.restore();
                    context.push('/watch/$videoId');
                  },
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NativeVideoPlayer(controller: player),
                        Positioned(
                          top: 3,
                          right: 3,
                          child: IconButton.filledTonal(
                            tooltip: 'Đóng trình phát thu nhỏ',
                            onPressed: session.dismiss,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black.withValues(
                                alpha: .72,
                              ),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(40, 40),
                            ),
                            icon: const Icon(Icons.close_rounded, size: 20),
                          ),
                        ),
                        if (!session.ready)
                          const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primaryPink,
                              strokeWidth: 2,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      const SizedBox(width: 11),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            session.restore();
                            context.push('/watch/$videoId');
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                session.channelName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: session.isPlaying ? 'Tạm dừng' : 'Phát',
                        onPressed: session.togglePlayback,
                        color: Colors.white,
                        icon: Icon(
                          session.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
                LinearProgressIndicator(
                  value: session.duration.inMilliseconds <= 0
                      ? 0
                      : (session.position.inMilliseconds /
                                session.duration.inMilliseconds)
                            .clamp(0.0, 1.0),
                  minHeight: 3,
                  color: AppColors.primaryPink,
                  backgroundColor: Colors.white12,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
