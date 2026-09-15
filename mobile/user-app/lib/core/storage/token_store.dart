import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// Optional capability for stores that can persist the installation identifier.
/// Keeping this separate preserves compatibility with lightweight test stores.
abstract interface class DeviceIdStore {
  Future<String?> readDeviceId();
  Future<void> writeDeviceId(String id);
}

class SecureTokenStore implements TokenStore, DeviceIdStore {
  const SecureTokenStore([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;
  static const _key = 'hutube.refreshToken';
  static const _deviceIdKey = 'hutube.deviceId';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);

  @override
  Future<String?> readDeviceId() => _storage.read(key: _deviceIdKey);

  @override
  Future<void> writeDeviceId(String id) =>
      _storage.write(key: _deviceIdKey, value: id);
}
