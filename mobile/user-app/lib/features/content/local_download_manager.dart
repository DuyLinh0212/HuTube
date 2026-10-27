import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class LocalDownload {
  const LocalDownload({
    required this.id,
    required this.videoId,
    required this.title,
    required this.quality,
    required this.url,
    required this.totalBytes,
    required this.status,
    required this.progress,
    this.filePath,
    this.error,
    this.thumbnailUrl,
    this.thumbnailPath,
    this.channelName = '',
    this.duration = 0,
  });

  final String id;
  final String videoId;
  final String title;
  final String quality;
  final String url;
  final int totalBytes;
  final String status;
  final double progress;
  final String? filePath;
  final String? error;
  final String? thumbnailUrl;
  final String? thumbnailPath;
  final String channelName;
  final int duration;

  bool get completed => status == 'completed';
  bool get active => status == 'downloading';

  LocalDownload copyWith({
    String? status,
    double? progress,
    String? filePath,
    String? error,
    bool clearError = false,
    String? thumbnailUrl,
    String? thumbnailPath,
    String? channelName,
    int? duration,
  }) => LocalDownload(
    id: id,
    videoId: videoId,
    title: title,
    quality: quality,
    url: url,
    totalBytes: totalBytes,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    filePath: filePath ?? this.filePath,
    error: clearError ? null : error ?? this.error,
    thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    channelName: channelName ?? this.channelName,
    duration: duration ?? this.duration,
  );

  factory LocalDownload.fromJson(Map<String, dynamic> json) => LocalDownload(
    id: '${json['id'] ?? ''}',
    videoId: '${json['videoId'] ?? ''}',
    title: '${json['title'] ?? ''}',
    quality: '${json['quality'] ?? ''}',
    url: '${json['url'] ?? ''}',
    totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
    status: '${json['status'] ?? 'failed'}',
    progress: (json['progress'] as num?)?.toDouble() ?? 0,
    filePath: json['filePath'] as String?,
    error: json['error'] as String?,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    thumbnailPath: json['thumbnailPath'] as String?,
    channelName: '${json['channelName'] ?? ''}',
    duration: (json['duration'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'videoId': videoId,
    'title': title,
    'quality': quality,
    'url': url,
    'totalBytes': totalBytes,
    'status': status,
    'progress': progress,
    'filePath': filePath,
    'error': error,
    'thumbnailUrl': thumbnailUrl,
    'thumbnailPath': thumbnailPath,
    'channelName': channelName,
    'duration': duration,
  };
}

/// Stores completed videos in the app's private documents directory. The
/// transfer is intentionally tied to the foreground isolate: background jobs
/// require OS-specific scheduling and must be added with a dedicated plugin,
/// not faked with an in-memory status.
class LocalDownloadManager extends ChangeNotifier {
  LocalDownloadManager._()
    : _rootDirectory = null,
      _clientFactory = (() => http.Client()),
      _connected = false,
      _wifiOnly = true;
  @visibleForTesting
  LocalDownloadManager.test({
    required Future<Directory> Function() rootDirectory,
    http.Client Function()? clientFactory,
  }) : _rootDirectory = rootDirectory,
       _clientFactory = clientFactory ?? (() => http.Client());
  final Future<Directory> Function()? _rootDirectory;
  final http.Client Function() _clientFactory;
  static final instance = LocalDownloadManager._();
  final List<LocalDownload> _items = [];
  final Map<String, http.Client> _clients = {};
  final Map<String, http.Client> _thumbnailClients = {};
  String? _owner;
  int _generation = 0;
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  Future<String?> Function(String)? _authorize;
  bool _connected = true;
  bool _wifi = false;
  bool _wifiOnly = false;
  static const _waiting = {'waiting_wifi', 'waiting_network'};
  List<LocalDownload> get items => List.unmodifiable(_items);
  String? get ownerId => _owner;

  String? _blocked(LocalDownload item) {
    if (!_connected) return 'waiting_network';
    if (_wifiOnly && !_wifi) return 'waiting_wifi';
    return null;
  }

  Future<void> configurePolicy({
    required bool connected,
    required bool wifi,
    required bool wifiOnly,
  }) async {
    _connected = connected;
    _wifi = wifi;
    _wifiOnly = wifiOnly;
    final generation = _generation;
    await ensureLoaded();
    if (generation != _generation) return;
    for (final item in List<LocalDownload>.of(_items)) {
      if (item.completed ||
          item.status == 'paused' ||
          item.status == 'failed') {
        continue;
      }
      final blocked = _blocked(item);
      if (blocked != null) {
        _clients.remove(item.id)?.close();
        if (item.status != blocked) {
          _replace(item.id, item.copyWith(status: blocked, clearError: true));
        }
      } else if (_waiting.contains(item.status) || item.status == 'queued') {
        unawaited(_start(item.id));
      }
    }
  }

  Future<void> bindUser(
    String? owner, {
    Future<String?> Function(String)? authorize,
  }) {
    _authorize = authorize;
    if (_owner == owner) return _loading ?? Future.value();
    _owner = owner;
    ++_generation;
    for (final client in _clients.values) {
      client.close();
    }
    _clients.clear();
    for (final client in _thumbnailClients.values) {
      client.close();
    }
    _thumbnailClients.clear();
    _items.clear();
    notifyListeners();
    _loading = owner == null ? Future.value() : _load(_generation, owner);
    return _loading!;
  }

  Future<Directory> _directory(String owner) async {
    final root =
        await (_rootDirectory?.call() ?? getApplicationDocumentsDirectory());
    final safeOwner = owner.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}downloads${Platform.pathSeparator}$safeOwner',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> ensureLoaded() => _loading ?? Future.value();
  @visibleForTesting
  Future<void> flush() => _writes;

  Future<void> _load(int generation, String owner) async {
    await _writes;
    final loaded = <LocalDownload>[];
    try {
      final manifest = File(
        '${(await _directory(owner)).path}${Platform.pathSeparator}manifest.json',
      );
      if (await manifest.exists()) {
        final raw = jsonDecode(await manifest.readAsString());
        for (final entry in (raw is List ? raw : const []).whereType<Map>()) {
          var item = LocalDownload.fromJson(Map<String, dynamic>.from(entry));
          if (item.completed &&
              (item.filePath == null || !await File(item.filePath!).exists())) {
            item = item.copyWith(
              status: 'failed',
              error: 'downloads.localMissing',
            );
          } else if (item.active ||
              item.status == 'queued' ||
              entry['smart'] == true ||
              item.status == 'waiting_settings' ||
              item.status == 'waiting_storage') {
            item = item.copyWith(
              status: 'paused',
              error: 'downloads.interrupted',
            );
          }
          loaded.add(item);
        }
      }
    } catch (_) {
      /* Corrupt manifests are isolated to their owner. */
    }
    if (generation != _generation || owner != _owner) return;
    _items.addAll(loaded);
    try {
      await _persist();
    } catch (_) {
      /* Downloads remain unavailable when device storage is unavailable. */
    }
    notifyListeners();
  }

  Future<void> _persist() {
    final owner = _owner;
    if (owner == null) return Future.value();
    final snapshot = jsonEncode(_items.map((item) => item.toJson()).toList());
    final next = _writes.then((_) async {
      final directory = await _directory(owner);
      final file = File(
        '${directory.path}${Platform.pathSeparator}manifest.json',
      );
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(snapshot, flush: true);
      await temporary.rename(file.path);
    });
    _writes = next.catchError((Object _) {});
    return next;
  }

  void _replace(String id, LocalDownload item, {bool persist = true}) {
    final index = _items.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    // A transfer snapshot may predate thumbnail metadata arriving from the API.
    final previous = _items[index];
    _items[index] = item.copyWith(
      thumbnailUrl: item.thumbnailUrl ?? previous.thumbnailUrl,
      thumbnailPath: item.thumbnailPath ?? previous.thumbnailPath,
      channelName: item.channelName.isEmpty ? previous.channelName : null,
      duration: item.duration == 0 ? previous.duration : null,
    );
    if (persist) unawaited(_persist().catchError((Object _) {}));
    notifyListeners();
  }

  Future<void> enqueue({
    required String id,
    required String videoId,
    required String title,
    required String quality,
    required String url,
    required int fileSize,
    String? thumbnailUrl,
    String channelName = '',
    int duration = 0,
  }) async {
    final generation = _generation;
    await ensureLoaded();
    if (_owner == null || generation != _generation) return;
    _clients.remove(id)?.close();
    _items.removeWhere((entry) => entry.id == id);
    _items.insert(
      0,
      LocalDownload(
        id: id,
        videoId: videoId,
        title: title,
        quality: quality,
        url: url,
        totalBytes: fileSize,
        status: 'queued',
        progress: 0,
        thumbnailUrl: thumbnailUrl,
        channelName: channelName,
        duration: duration,
      ),
    );
    await _persist();
    notifyListeners();
    unawaited(_start(id));
  }

  Future<void> updateMetadata(
    String id, {
    String? thumbnailUrl,
    String? channelName,
    int? duration,
  }) async {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final previous = _items[index];
    final next = previous.copyWith(
      thumbnailUrl: thumbnailUrl?.isNotEmpty == true ? thumbnailUrl : null,
      channelName: channelName?.isNotEmpty == true ? channelName : null,
      duration: duration != null && duration > 0 ? duration : null,
    );
    if (next.thumbnailUrl != previous.thumbnailUrl ||
        next.channelName != previous.channelName ||
        next.duration != previous.duration) {
      _replace(id, next);
    }
    await _cacheThumbnail(id);
  }

  Future<void> _cacheThumbnail(String id) async {
    if (!_connected ||
        (_wifiOnly && !_wifi) ||
        _thumbnailClients.containsKey(id)) {
      return;
    }
    final index = _items.indexWhere((item) => item.id == id);
    final owner = _owner, generation = _generation;
    if (index < 0 || owner == null) return;
    final item = _items[index];
    if (item.thumbnailPath != null && File(item.thumbnailPath!).existsSync()) {
      return;
    }
    final uri = Uri.tryParse(item.thumbnailUrl ?? '');
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return;
    }
    final client = _clientFactory();
    _thumbnailClients[id] = client;
    bool current() =>
        generation == _generation &&
        _owner == owner &&
        identical(_thumbnailClients[id], client) &&
        _items.any((item) => item.id == id);
    File? target;
    try {
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 8));
      if (!current() ||
          response.statusCode != 200 ||
          (response.contentLength ?? 0) > 3 * 1024 * 1024) {
        return;
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 8),
      )) {
        if (!current() || bytes.length + chunk.length > 3 * 1024 * 1024) return;
        bytes.addAll(chunk);
      }
      if (!current() || bytes.isEmpty) return;
      final directory = await _directory(owner);
      if (!current()) return;
      final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      target = File(
        '${directory.path}${Platform.pathSeparator}$safeId.thumbnail',
      );
      await target.writeAsBytes(bytes, flush: true);
      if (!current()) {
        await target.delete();
        return;
      }
      final latest = _items.firstWhere((item) => item.id == id);
      _replace(id, latest.copyWith(thumbnailPath: target.path));
    } catch (_) {
      // Cover art is optional; a failed image must never fail the video transfer.
    } finally {
      if (identical(_thumbnailClients[id], client)) {
        _thumbnailClients.remove(id);
      }
      client.close();
    }
  }

  Future<void> retry(String id) async {
    final generation = _generation;
    await ensureLoaded();
    if (generation != _generation) return;
    await _start(id);
  }

  Future<void> pause(String id) async {
    final generation = _generation;
    await ensureLoaded();
    if (generation != _generation) return;
    _clients.remove(id)?.close();
    final index = _items.indexWhere((entry) => entry.id == id);
    if (index < 0 || _items[index].completed) return;
    _replace(id, _items[index].copyWith(status: 'paused', clearError: true));
    await _persist();
  }

  Future<void> _start(String id) async {
    final owner = _owner, generation = _generation;
    if (owner == null || _clients.containsKey(id)) return;
    final index = _items.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    final item = _items[index];
    unawaited(_cacheThumbnail(id));
    final blocked = _blocked(item);
    if (blocked != null) {
      _replace(id, item.copyWith(status: blocked, clearError: true));
      return;
    }
    final client = _clientFactory();
    _clients[id] = client;
    IOSink? sink;
    File? temporary;
    var failed = false;
    bool current() =>
        generation == _generation &&
        _owner == owner &&
        identical(_clients[id], client) &&
        _items.any((entry) => entry.id == id);
    try {
      final url = await _authorize?.call(id);
      if (!current()) return;
      final uri = Uri.tryParse(url ?? '');
      if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
        throw StateError('Download access revoked');
      }
      final directory = await _directory(owner);
      if (!current()) return;
      final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final file = File(
        '${directory.path}${Platform.pathSeparator}$safeId.mp4',
      );
      temporary = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
      );
      _replace(
        id,
        item.copyWith(status: 'downloading', progress: 0, clearError: true),
      );
      final response = await client.send(http.Request('GET', uri));
      if (!current()) return;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Download failed');
      }
      sink = temporary.openWrite();
      var received = 0;
      final expected = response.contentLength ?? item.totalBytes;
      final progressClock = Stopwatch()..start();
      var lastUpdate = 0;
      await for (final chunk in response.stream) {
        if (!current()) return;
        sink.add(chunk);
        received += chunk.length;
        if (progressClock.elapsedMilliseconds - lastUpdate >= 200) {
          lastUpdate = progressClock.elapsedMilliseconds;
          _replace(
            id,
            item.copyWith(
              status: 'downloading',
              progress: expected > 0 ? (received / expected).clamp(0, 1) : 0,
            ),
            persist: false,
          );
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (!current()) return;
      if (expected > 0 && received != expected) {
        throw const FileSystemException('Incomplete download');
      }
      await temporary.rename(file.path);
      temporary = null;
      if (current()) {
        _replace(
          id,
          item.copyWith(
            status: 'completed',
            progress: 1,
            filePath: file.path,
            clearError: true,
          ),
        );
      }
    } catch (_) {
      failed = true;
    } finally {
      try {
        await sink?.close();
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } catch (_) {
        // File cleanup must still release the transfer so retry stays usable.
      }
      final publishFailure = failed && current();
      if (identical(_clients[id], client)) _clients.remove(id);
      client.close();
      if (publishFailure) {
        // Publish failure only after releasing the old client. A listener or
        // immediate tap on Retry can now start the next transfer.
        _replace(
          id,
          item.copyWith(status: 'failed', error: 'downloads.fileError'),
        );
      }
    }
  }

  Future<void> remove(String id) async {
    final generation = _generation;
    await ensureLoaded();
    if (generation != _generation) return;
    _clients.remove(id)?.close();
    _thumbnailClients.remove(id)?.close();
    final index = _items.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    final item = _items.removeAt(index);
    if (item.filePath != null && await File(item.filePath!).exists()) {
      await File(item.filePath!).delete();
    }
    if (item.thumbnailPath != null &&
        await File(item.thumbnailPath!).exists()) {
      await File(item.thumbnailPath!).delete();
    }
    await _persist();
    notifyListeners();
  }
}
