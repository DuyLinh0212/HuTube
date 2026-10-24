import 'package:flutter/services.dart';

/// Uses the existing Flutter surface; entering PiP never opens another player.
class AppPictureInPicture {
  static const channel = MethodChannel('hutube/picture_in_picture');
  static Object? _owner;
  static void bind(Object owner, Future<bool> Function() prepare) {
    _owner = owner;
    channel.setMethodCallHandler(
      (call) async => call.method == 'prepare' ? await prepare() : false,
    );
  }

  static void unbind(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    channel.setMethodCallHandler(null);
  }

  static Future<bool> available() async {
    try {
      return await channel.invokeMethod<bool>('available') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> enter() async {
    try {
      return await channel.invokeMethod<bool>('enter') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> configure({required bool automatic}) async {
    try {
      await channel.invokeMethod<void>('configure', {'automatic': automatic});
    } catch (_) {
      /* Unsupported platforms leave playback in the app. */
    }
  }
}
