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

  bool get completed => status == 'completed';
  bool get active => status == 'downloading';

  LocalDownload copyWith({
    String? status,
    double? progress,
    String? filePath,
    String? error,
    bool clearError = false,
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
  };
}

/// Stores completed videos in the app's private documents directory. The
/// transfer is intentionally tied to the foreground isolate: background jobs
/// require OS-specific scheduling and must be added with a dedicated plugin,
/// not faked with an in-memory status.
class LocalDownloadManager extends ChangeNotifier {
  LocalDownloadManager._()
    : _rootDirectory = null,
      _clientFactory = (() => http.Client());
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
  String? _owner;
  int _generation = 0;
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  Future<String?> Function(String)? _authorize;
  List<LocalDownload> get items => List.unmodifiable(_items);
  String? get ownerId => _owner;

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
          } else if (item.active || item.status == 'queued') {
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

  void _replace(String id, LocalDownload item) {
    final index = _items.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    _items[index] = item;
    unawaited(_persist().catchError((Object _) {}));
    notifyListeners();
  }

  Future<void> enqueue({
    required String id,
    required String videoId,
    required String title,
    required String quality,
    required String url,
    required int fileSize,
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
      ),
    );
    await _persist();
    notifyListeners();
    unawaited(_start(id));
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
    final client = _clientFactory();
    _clients[id] = client;
    IOSink? sink;
    File? temporary;
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
      await for (final chunk in response.stream) {
        if (!current()) return;
        sink.add(chunk);
        received += chunk.length;
        _replace(
          id,
          item.copyWith(
            status: 'downloading',
            progress: expected > 0 ? received / expected : 0,
          ),
        );
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
      if (current()) {
        _replace(
          id,
          item.copyWith(status: 'failed', error: 'downloads.fileError'),
        );
      }
    } finally {
      await sink?.close();
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      if (identical(_clients[id], client)) _clients.remove(id);
      client.close();
    }
  }

  Future<void> remove(String id) async {
    final generation = _generation;
    await ensureLoaded();
    if (generation != _generation) return;
    _clients.remove(id)?.close();
    final index = _items.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    final item = _items.removeAt(index);
    if (item.filePath != null && await File(item.filePath!).exists()) {
      await File(item.filePath!).delete();
    }
    await _persist();
    notifyListeners();
  }
}
