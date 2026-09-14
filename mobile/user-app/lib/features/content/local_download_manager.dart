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
  LocalDownloadManager._();
  static final instance = LocalDownloadManager._();

  final List<LocalDownload> _items = [];
  bool _loaded = false;
  Future<void>? _loading;
  final Map<String, http.Client> _clients = {};

  List<LocalDownload> get items => List.unmodifiable(_items);

  Future<Directory> _directory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}downloads',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> _manifest() async => File(
    '${(await _directory()).path}${Platform.pathSeparator}manifest.json',
  );

  Future<void> ensureLoaded() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final manifest = await _manifest();
      if (await manifest.exists()) {
        final raw = jsonDecode(await manifest.readAsString());
        final entries = raw is List ? raw : const [];
        _items
          ..clear()
          ..addAll(
            entries.whereType<Map>().map(
              (value) =>
                  LocalDownload.fromJson(Map<String, dynamic>.from(value)),
            ),
          );
        for (var index = 0; index < _items.length; index++) {
          final item = _items[index];
          if (item.completed &&
              (item.filePath == null || !await File(item.filePath!).exists())) {
            _items[index] = item.copyWith(
              status: 'failed',
              error: 'Không còn file trên thiết bị.',
            );
          } else if (item.active) {
            _items[index] = item.copyWith(
              status: 'paused',
              error: 'Tải xuống bị gián đoạn khi ứng dụng đóng.',
            );
          }
        }
      }
    } catch (_) {
      _items.clear();
    } finally {
      _loaded = true;
      await _persist();
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    if (!_loaded) return;
    final manifest = await _manifest();
    await manifest.writeAsString(
      jsonEncode(_items.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> enqueue({
    required String id,
    required String videoId,
    required String title,
    required String quality,
    required String url,
    required int fileSize,
  }) async {
    await ensureLoaded();
    final index = _items.indexWhere((item) => item.id == id);
    final initial = LocalDownload(
      id: id,
      videoId: videoId,
      title: title,
      quality: quality,
      url: url,
      totalBytes: fileSize,
      status: 'queued',
      progress: 0,
    );
    if (index >= 0)
      _items[index] = initial;
    else
      _items.insert(0, initial);
    await _persist();
    notifyListeners();
    unawaited(_start(id));
  }

  Future<void> retry(String id) async {
    await ensureLoaded();
    unawaited(_start(id));
  }

  Future<void> _start(String id) async {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    var item = _items[index];
    final uri = Uri.tryParse(item.url);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      _replace(
        index,
        item.copyWith(
          status: 'failed',
          error: 'Máy chủ không trả về URL tải xuống HTTP hợp lệ.',
        ),
      );
      return;
    }
    final safe = item.title.replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '_').trim();
    final file = File(
      '${(await _directory()).path}${Platform.pathSeparator}${id}_${safe.isEmpty ? 'video' : safe}_${item.quality}.mp4',
    );
    final temporary = File('${file.path}.part');
    final client = http.Client();
    _clients[id]?.close();
    _clients[id] = client;
    _replace(
      index,
      item.copyWith(status: 'downloading', progress: 0, clearError: true),
    );
    try {
      final response = await client.send(http.Request('GET', uri));
      if (response.statusCode < 200 || response.statusCode >= 300)
        throw HttpException('Máy chủ trả về ${response.statusCode}.');
      final sink = temporary.openWrite();
      var received = 0;
      final expected = response.contentLength ?? item.totalBytes;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        final current = _items.indexWhere((entry) => entry.id == id);
        if (current < 0 || _clients[id] != client) {
          await sink.close();
          return;
        }
        _replace(
          current,
          _items[current].copyWith(
            progress: expected > 0 ? received / expected : 0,
          ),
        );
      }
      await sink.close();
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
      final current = _items.indexWhere((entry) => entry.id == id);
      if (current >= 0)
        _replace(
          current,
          _items[current].copyWith(
            status: 'completed',
            progress: 1,
            filePath: file.path,
            clearError: true,
          ),
        );
    } catch (_) {
      final current = _items.indexWhere((entry) => entry.id == id);
      if (current >= 0)
        _replace(
          current,
          _items[current].copyWith(
            status: 'failed',
            error: 'Không thể tải file. Kiểm tra kết nối hoặc thử lại.',
          ),
        );
    } finally {
      _clients.remove(id)?.close();
    }
  }

  Future<void> remove(String id) async {
    await ensureLoaded();
    _clients.remove(id)?.close();
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final item = _items.removeAt(index);
    if (item.filePath != null) {
      final file = File(item.filePath!);
      if (await file.exists()) await file.delete();
    }
    await _persist();
    notifyListeners();
  }

  void _replace(int index, LocalDownload item) {
    _items[index] = item;
    unawaited(_persist());
    notifyListeners();
  }
}
