import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Network and external audio routes reported by the operating system.
/// An unknown network never counts as Wi-Fi.
class DeviceConditions extends ChangeNotifier {
  DeviceConditions();
  static final instance = DeviceConditions();
  static const _channel = MethodChannel('hutube/device_conditions');
  static const _events = EventChannel('hutube/device_conditions/events');
  bool connected = false;
  bool wifi = false;
  bool externalAudio = false;
  StreamSubscription<dynamic>? _subscription;
  Future<void>? _initialization;
  bool _disposed = false;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>('snapshot');
      _apply(value);
    } catch (_) {
      _apply(const <String, bool>{});
      return;
    }
    _subscription = _events.receiveBroadcastStream().listen(
      _apply,
      onError: (Object _) => _apply(const <String, bool>{}),
    );
    await refresh();
  }

  Future<void> refresh() async {
    try {
      _apply(await _channel.invokeMapMethod<String, dynamic>('snapshot'));
    } catch (_) {
      _apply(const <String, bool>{});
    }
  }

  void _apply(dynamic value) {
    if (_disposed) return;
    final data = value is Map ? value : const {};
    final nextConnected = data['connected'] == true;
    final nextWifi = nextConnected && data['wifi'] == true;
    final nextAudio = data['externalAudio'] == true;
    if (connected == nextConnected &&
        wifi == nextWifi &&
        externalAudio == nextAudio) {
      return;
    }
    connected = nextConnected;
    wifi = nextWifi;
    externalAudio = nextAudio;
    notifyListeners();
  }

  @visibleForTesting
  void setState({
    required bool connected,
    required bool wifi,
    bool externalAudio = false,
  }) => _apply({
    'connected': connected,
    'wifi': wifi,
    'externalAudio': externalAudio,
  });

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
