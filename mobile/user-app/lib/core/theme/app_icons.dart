import 'package:flutter/material.dart';

class AppIcons {
  static const String _path = 'assets/icons/';
  static const String _utilityPath = 'assets/icons/utility/';

  // Core & Navigation
  static const String home = '${_path}home.png';
  static const String compass = '${_path}compass.png';
  static const String huAi = '${_path}HuAI.png';
  static const String notification = '${_path}notification.png';
  static const String user = '${_path}user.png';
  static const String channel = '${_path}channel.png';
  static const String myChannel = '${_path}my_channel.png';

  // Player & Watch Actions
  static const String playlist = '${_path}playlist.png';
  static const String bookmark = '${_utilityPath}icon-utility-bookmark.png';
  static const String share = '${_utilityPath}icon-utility-share.png';
  static const String send = '${_utilityPath}icon-utility-send.png';
  static const String star = '${_utilityPath}icon-utility-star.png';
  static const String download = '${_path}download.png';
  static const String queue = '${_path}queue.png';
  static const String report = '${_path}report.png';
  static const String history = '${_path}history.png';
  static const String favorite = '${_path}favorite.png';

  // Search & Utility
  static const String filter = '${_utilityPath}icon-utility-filter-sliders.png';
  static const String search = '${_utilityPath}icon-utility-search.png';
  static const String back = '${_utilityPath}icon-utility-back.png';
  static const String more = '${_utilityPath}icon-utility-more.png';
  static const String bell = '${_utilityPath}icon-utility-bell.png';

  // Creator & Moderation
  static const String upload = '${_path}upload_video.png';
  static const String myVideo = '${_path}my_video.png';
  static const String dashboard = '${_path}dashboard.png';
  static const String statistics = '${_path}statistics.png';
  static const String plan = '${_path}plan.png';
  static const String revenue = '${_path}revenue.png';
  static const String warningStrike = '${_path}warning_strike.png';
  static const String appeals = '${_path}appeals.png';
  static const String censor = '${_path}censor.png';
  static const String device = '${_path}device.png';
  static const String setting = '${_path}setting.png';
  static const String topics = '${_path}topics.png';

  /// Helper displaying an image asset icon with customizable size and tint color
  static Widget asset(
    String path, {
    double size = 22,
    Color? color,
    BoxFit fit = BoxFit.contain,
  }) => Image.asset(
    path,
    width: size,
    height: size,
    color: color,
    fit: fit,
    errorBuilder: (_, _, _) => Icon(Icons.broken_image, size: size, color: color),
  );
}
