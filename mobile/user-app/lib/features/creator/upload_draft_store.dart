import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class UploadDraftStore {
  const UploadDraftStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;
  final FlutterSecureStorage _storage;
  static Future<void> _operations = Future<void>.value();
  static Future<T> _serialized<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _operations = _operations.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  String _key(String userId, String channelId) =>
      'hutube.upload.draft.$userId.$channelId';
  Future<void> save(
    String userId,
    String channelId,
    Map<String, dynamic> data,
  ) {
    final value = jsonEncode({'version': 1, 'data': data});
    return _serialized(
      () => _storage.write(key: _key(userId, channelId), value: value),
    );
  }

  Future<Map<String, dynamic>?> read(String userId, String channelId) async {
    final raw = await revision(userId, channelId);
    if (raw == null) return null;
    return decode(raw);
  }

  static Map<String, dynamic>? decode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['version'] != 1 || json['data'] is! Map) {
        return null;
      }
      final data = Map<String, dynamic>.from(json['data'] as Map);
      for (final key in [
        'title',
        'description',
        'tags',
        'languageCode',
        'visibility',
      ]) {
        if (data[key] is! String) return null;
      }
      if (![
            'vi',
            'en',
            'ja',
            'ko',
            'zh',
            'other',
          ].contains(data['languageCode']) ||
          !['private', 'unlisted', 'public'].contains(data['visibility'])) {
        return null;
      }
      for (final key in ['chapters', 'videoCards']) {
        final list = data[key];
        if (list is! List ||
            list.any(
              (item) =>
                  item is! Map ||
                  item['startSeconds'] is! int ||
                  (item['startSeconds'] as int) < 0,
            )) {
          return null;
        }
      }
      if ((data['chapters'] as List).any((c) => c['title'] is! String) ||
          (data['videoCards'] as List).any((c) => c['videoId'] is! String)) {
        return null;
      }
      if (data['playlistIds'] is! List ||
          (data['playlistIds'] as List).any((id) => id is! String)) {
        return null;
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<String?> revision(String userId, String channelId) =>
      _serialized(() => _storage.read(key: _key(userId, channelId)));

  Future<void> removeIfUnchanged(
    String userId,
    String channelId,
    String? revision,
  ) => _serialized(() async {
    if (revision != null &&
        await _storage.read(key: _key(userId, channelId)) == revision) {
      await _storage.delete(key: _key(userId, channelId));
    }
  });

  Future<void> remove(String userId, String channelId) =>
      _serialized(() => _storage.delete(key: _key(userId, channelId)));
}
