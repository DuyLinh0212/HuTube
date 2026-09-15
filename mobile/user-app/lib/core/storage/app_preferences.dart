import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists device-level UI preferences that should be available before the
/// first authenticated API request. Account data remains owned by the API;
/// this store only keeps presentation choices local to the installation.
class AppPreferencesStore {
  const AppPreferencesStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const languageKey = 'hutube.language';
  static const themeKey = 'hutube.theme';

  Future<String?> readLanguage() => _storage.read(key: languageKey);

  Future<void> writeLanguage(String language) =>
      _storage.write(key: languageKey, value: language);

  Future<String?> readTheme() => _storage.read(key: themeKey);

  Future<void> writeTheme(String theme) =>
      _storage.write(key: themeKey, value: theme);
}
