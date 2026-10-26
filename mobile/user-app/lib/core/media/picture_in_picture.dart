import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Uses the existing Flutter surface; entering PiP never opens another player.
class AppPictureInPicture {
  static const channel = MethodChannel('hutube/picture_in_picture');
  static final _bindings =
      <({Object owner, Future<bool> Function() prepare})>[];
  static Object? get _owner => _bindings.lastOrNull?.owner;
  // True while preparing too: overlays must disappear before Android captures.
  static final active = ValueNotifier<bool>(false);
  static void bind(Object owner, Future<bool> Function() prepare) {
    _bindings.removeWhere((binding) => identical(binding.owner, owner));
    _bindings.add((owner: owner, prepare: prepare));
    _installHandler();
  }

  static void bindFallback(Object owner, Future<bool> Function() prepare) {
    _bindings.removeWhere((binding) => identical(binding.owner, owner));
    _bindings.insert(0, (owner: owner, prepare: prepare));
    _installHandler();
  }

  static void _installHandler() {
    if (_bindings.isEmpty) {
      channel.setMethodCallHandler(null);
      return;
    }
    channel.setMethodCallHandler((call) async {
      if (call.method == 'modeChanged') {
        active.value = call.arguments == true;
        return null;
      }
      if (call.method == 'prepare') {
        final binding = _bindings.lastOrNull;
        if (binding == null) return false;
        active.value = true;
        try {
          final ready = await binding.prepare();
          if (!identical(_owner, binding.owner)) return false;
          if (!ready) active.value = false;
          return ready;
        } catch (_) {
          if (identical(_owner, binding.owner)) active.value = false;
          return false;
        }
      }
      return false;
    });
  }

  static void unbind(Object owner) {
    final wasCurrent = identical(_owner, owner);
    _bindings.removeWhere((binding) => identical(binding.owner, owner));
    if (wasCurrent) active.value = false;
    _installHandler();
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
      final entered = await channel.invokeMethod<bool>('enter') ?? false;
      if (!entered) active.value = false;
      return entered;
    } catch (_) {
      active.value = false;
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
