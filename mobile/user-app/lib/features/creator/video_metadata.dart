import 'dart:io';
import 'package:flutter/services.dart';

class VideoMetadata {
  const VideoMetadata({
    required this.durationSeconds,
    required this.width,
    required this.height,
    this.thumbnails = const [],
  });
  final int durationSeconds, width, height;
  final List<String> thumbnails;
  static const channel = MethodChannel('hutube/media_tools');
  static const qualityHeights = [144, 240, 360, 480, 720, 1080, 1440, 2160];
  List<String> get qualities {
    final shorterSide = width < height ? width : height;
    return qualityHeights
        .where((h) => h <= shorterSide)
        .map((h) => '${h}p')
        .toList();
  }

  String selectQuality(String? preferred) =>
      qualities.contains(preferred) ? preferred! : qualities.last;

  static Future<VideoMetadata> inspect(String path) async {
    if (!Platform.isAndroid) throw UnsupportedError('Android video metadata');
    final data = await channel.invokeMapMethod<String, dynamic>(
      'inspectVideo',
      {'path': path},
    );
    if (data == null) throw const FormatException('Missing video metadata');
    final result = VideoMetadata(
      durationSeconds: ((data['durationMs'] as num) / 1000).ceil(),
      width: (data['width'] as num).toInt(),
      height: (data['height'] as num).toInt(),
      thumbnails: (data['thumbnails'] as List? ?? []).cast<String>(),
    );
    if (result.durationSeconds <= 0 || result.qualities.isEmpty) {
      throw const FormatException('Invalid video metadata');
    }
    return result;
  }
}
