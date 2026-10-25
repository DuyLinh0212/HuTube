import 'dart:convert';
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

/// A cached identity only unlocks this account's local files while offline.
/// It is bound to the stored refresh token, never used as an API credential.
abstract interface class OfflineIdentityStore {
  Future<Map<String, dynamic>?> readOfflineUser(String refreshToken);
  Future<void> writeOfflineUser(String refreshToken, Map<String, dynamic> user);
}

class SecureTokenStore
    implements TokenStore, DeviceIdStore, OfflineIdentityStore {
  const SecureTokenStore([
    this._storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(
        // Never wipe the refresh token just because a new app build changed
        // the Android crypto implementation. Let the plugin migrate it or
        // surface the storage error so the user can recover explicitly.
        resetOnError: false,
        migrateOnAlgorithmChange: true,
      ),
      iOptions: IOSOptions(
        // The token must remain readable after an app update/restart before
        // the device has been unlocked again.
        accessibility: KeychainAccessibility.first_unlock,
      ),
    ),
  ]);
  final FlutterSecureStorage _storage;
  static const _key = 'hutube.refreshToken';
  static const _deviceIdKey = 'hutube.deviceId';
  static const _offlineUserKey = 'hutube.offlineUser';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _key),
      _storage.delete(key: _offlineUserKey),
    ]);
  }

  @override
  Future<Map<String, dynamic>?> readOfflineUser(String refreshToken) async {
    final value = await _storage.read(key: _offlineUserKey);
    if (value == null) return null;
    try {
      final cached = jsonDecode(value);
      if (cached is! Map ||
          cached['session'] != refreshToken ||
          cached['user'] is! Map) {
        return null;
      }
      final user = Map<String, dynamic>.from(cached['user'] as Map);
      return user['userId'] is String && (user['userId'] as String).isNotEmpty
          ? user
          : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> writeOfflineUser(
    String refreshToken,
    Map<String, dynamic> user,
  ) => _storage.write(
    key: _offlineUserKey,
    value: jsonEncode({'session': refreshToken, 'user': user}),
  );

  @override
  Future<String?> readDeviceId() => _storage.read(key: _deviceIdKey);

  @override
  Future<void> writeDeviceId(String id) =>
      _storage.write(key: _deviceIdKey, value: id);
}
