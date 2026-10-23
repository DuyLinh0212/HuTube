import 'dart:convert';

/// Short-lived JSON snapshots only. Shared by API clients created by screens;
/// never written to disk, and never used for authentication or paid entitlements.
class ReadCache {
  static void invalidateNotifications() =>
      _invalidate('/notifications/changed');
  static final Map<String, (DateTime, String)> _values = {};
  static final Map<String, Future<dynamic>> _flights = {};
  static int _generation = 0;

  static void clear() {
    _generation++;
    _values.clear();
    _flights.clear();
  }

  static void _invalidate(String path) {
    if (path.endsWith('/player-preferences')) return;
    if (path.endsWith('/progress') || path.contains('/notifications/')) {
      _generation++;
      _flights.clear();
      _values.removeWhere(
        (key, _) => path.endsWith('/progress')
            ? RegExp(r'/(library|videos)/').hasMatch(key)
            : key.contains('/notifications'),
      );
      return;
    }
    clear();
  }

  static int _ttl(Uri uri) {
    final path = uri.path;
    if (uri.queryParameters.containsKey('_refresh') ||
        RegExp(
          r'/(auth/|playback|download-options|payments/|jobs/|upload|feedback-survey|my-plan|session-player|evidence|export)',
        ).hasMatch(path)) {
      return 0;
    }
    if (RegExp(r'/(categories|violation-types|roles)$').hasMatch(path)) {
      return 60;
    }
    if (path.endsWith('/policies')) return 30;
    if (RegExp(
      r'/(feed|videos|channels|playlists|subscriptions|library|account|studio|notifications|downloads|plans)(/|$)',
    ).hasMatch(path)) {
      return 20;
    }
    return 0;
  }

  static String? _scope(String? token) {
    if (token == null) return 'guest';
    try {
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
      );
      return '${claims['sub']}:${claims['sid']}';
    } catch (_) {
      return null;
    }
  }

  static Future<dynamic> read(
    String method,
    Uri uri,
    String? token,
    Map<String, dynamic>? body,
    Future<dynamic> Function() source,
  ) async {
    final readPost =
        method.toUpperCase() == 'POST' && uri.path.endsWith('/feed/resolve');
    if (method.toUpperCase() != 'GET' && !readPost) {
      _invalidate(uri.path);
      try {
        return await source();
      } finally {
        _invalidate(uri.path);
      }
    }
    final ttl = _ttl(uri);
    final scope = _scope(token);
    if (ttl == 0 || scope == null) return source();
    final keys = uri.queryParametersAll.keys.toList()..sort();
    final canonical = uri.replace(
      queryParameters: {
        for (final key in keys) key: uri.queryParametersAll[key]!,
      },
    );
    final key = '$scope|$method|$canonical|${readPost ? jsonEncode(body) : ''}';
    final entry = _values[key];
    if (entry != null && entry.$1.isAfter(DateTime.now())) {
      return jsonDecode(entry.$2);
    }
    _values.remove(key);
    final pending = _flights[key];
    if (pending != null) return jsonDecode(jsonEncode(await pending));
    final generation = _generation;
    final flight = source();
    _flights[key] = flight;
    try {
      final data = await flight;
      final serialized = jsonEncode(data);
      if (generation == _generation && serialized.length <= 256 * 1024) {
        if (_values.length >= 160) _values.remove(_values.keys.first);
        _values[key] = (DateTime.now().add(Duration(seconds: ttl)), serialized);
      }
      return jsonDecode(serialized);
    } finally {
      if (identical(_flights[key], flight)) _flights.remove(key);
    }
  }
}
