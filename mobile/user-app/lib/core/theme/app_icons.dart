import 'package:flutter/material.dart';

class AppIcons {
  static const String _path = 'assets/icons/';
  static const String _utilityPath = 'assets/icons/utility/';

  // Core & Navigation
  static const String home = '${_path}home.webp';
  static const String compass = '${_path}compass.webp';
  static const String huAi = '${_path}HuAI.webp';
  static const String notification = '${_path}notification.webp';
  static const String user = '${_path}user.webp';
  static const String channel = '${_path}channel.webp';
  static const String myChannel = '${_path}my_channel.webp';

  // Player & Watch Actions
  static const String playlist = '${_path}playlist.webp';
  static const String bookmark = '${_utilityPath}icon-utility-bookmark.webp';
  static const String share = '${_utilityPath}icon-utility-share.webp';
  static const String send = '${_utilityPath}icon-utility-send.webp';
  static const String star = '${_utilityPath}icon-utility-star.webp';
  static const String download = '${_path}download.webp';
  static const String queue = '${_path}queue.webp';
  static const String report = '${_path}report.webp';
  static const String history = '${_path}history.webp';
  static const String favorite = '${_path}favorite.webp';

  // Search & Utility
  static const String filter = '${_utilityPath}icon-utility-filter-sliders.webp';
  static const String search = '${_utilityPath}icon-utility-search.webp';
  static const String back = '${_utilityPath}icon-utility-back.webp';
  static const String more = '${_utilityPath}icon-utility-more.webp';
  static const String bell = '${_utilityPath}icon-utility-bell.webp';

  // Creator & Moderation
  static const String upload = '${_path}upload_video.webp';
  static const String myVideo = '${_path}my_video.webp';
  static const String dashboard = '${_path}dashboard.webp';
  static const String statistics = '${_path}statistics.webp';
  static const String plan = '${_path}plan.webp';
  static const String revenue = '${_path}revenue.webp';
  static const String warningStrike = '${_path}warning_strike.webp';
  static const String appeals = '${_path}appeals.webp';
  static const String censor = '${_path}censor.webp';
  static const String device = '${_path}device.webp';
  static const String setting = '${_path}setting.webp';
  static const String topics = '${_path}topics.webp';

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
