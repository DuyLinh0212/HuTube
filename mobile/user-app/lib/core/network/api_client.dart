import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/app_config.dart';
import '../errors/app_error.dart';
import 'network_status.dart';

class UploadPayload {
  const UploadPayload({
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });

  final List<int> bytes;
  final String fileName;
  final String contentType;
}

/// A file part for APIs that accept a form with metadata and more than one
/// attachment (for example a video and its thumbnail).
class MultipartFilePayload {
  const MultipartFilePayload({
    required this.field,
    required this.path,
    required this.fileName,
    required this.contentType,
  });

  final String field;
  final String path;
  final String fileName;
  final String contentType;
}

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : client = client ?? http.Client(),
      baseUrl = baseUrl ?? AppConfig.standard.apiBaseUrl,
      _currentBaseUrl = baseUrl ?? AppConfig.standard.apiBaseUrl;

  final http.Client client;
  final String baseUrl;
  String _currentBaseUrl;
  Future<bool>? _connectionCheck;

  String _buildUrl(String path) {
    final base = _currentBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$base$cleanPath';
  }

  Future<Map<String, dynamic>> upload(
    String path,
    UploadPayload payload, {
    String? accessToken,
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_buildUrl(path)));
      request.headers.addAll({
        'Accept': 'application/json',
        'X-HuTube-Client': AppConfig.standard.clientHeader,
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      });
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          payload.bytes,
          filename: payload.fileName,
          contentType: MediaType.parse(payload.contentType),
        ),
      );
      final response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 40)),
      ).timeout(const Duration(seconds: 40));
      NetworkStatus.instance.markAvailable();
      final data = _decodeResponse(response);
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } on AppError {
      rethrow;
    } on TimeoutException {
      unawaited(checkConnection());
      throw ApiFailure.timeoutError;
    } on SocketException {
      unawaited(checkConnection());
      throw ApiFailure.network;
    } on http.ClientException {
      unawaited(checkConnection());
      throw ApiFailure.network;
    }
  }

  Future<Map<String, dynamic>> uploadMultipart(
    String path, {
    required Map<String, String> fields,
    required List<MultipartFilePayload> files,
    String method = 'POST',
    String? accessToken,
    Map<String, String>? headers,
  }) async {
    try {
      final request = http.MultipartRequest(method, Uri.parse(_buildUrl(path)));
      request.headers.addAll({
        'Accept': 'application/json',
        'X-HuTube-Client': AppConfig.standard.clientHeader,
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        ...?headers,
      });
      request.fields.addAll(fields);
      for (final file in files) {
        request.files.add(
          await http.MultipartFile.fromPath(
            file.field,
            file.path,
            filename: file.fileName,
            contentType: MediaType.parse(file.contentType),
          ),
        );
      }
      final response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(minutes: 5)),
      ).timeout(const Duration(minutes: 5));
      NetworkStatus.instance.markAvailable();
      final data = _decodeResponse(response);
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } on AppError {
      rethrow;
    } on TimeoutException {
      unawaited(checkConnection());
      throw ApiFailure.timeoutError;
    } on SocketException {
      unawaited(checkConnection());
      throw ApiFailure.network;
    } on http.ClientException {
      unawaited(checkConnection());
      throw ApiFailure.network;
    }
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) async {
    final data = await _requestJson(
      method,
      path,
      body: body,
      accessToken: accessToken,
    );
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<List<dynamic>> requestList(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) async {
    final data = await _requestJson(
      method,
      path,
      body: body,
      accessToken: accessToken,
    );
    return data is List<dynamic> ? data : <dynamic>[];
  }

  Future<dynamic> _requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) async {
    try {
      final request = http.Request(method, Uri.parse(_buildUrl(path)));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-HuTube-Client': AppConfig.standard.clientHeader,
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      });
      if (body != null) request.body = jsonEncode(body);

      final response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 20)),
      ).timeout(const Duration(seconds: 20));
      NetworkStatus.instance.markAvailable();

      return _decodeResponse(response);
    } on AppError {
      rethrow;
    } on TimeoutException {
      unawaited(checkConnection());
      throw ApiFailure.timeoutError;
    } on SocketException {
      if (Platform.isAndroid && _currentBaseUrl.contains('127.0.0.1')) {
        final fallback = _currentBaseUrl.replaceFirst('127.0.0.1', '10.0.2.2');
        try {
          final fallbackBase = fallback.replaceAll(RegExp(r'/+$'), '');
          final cleanPath = path.startsWith('/') ? path : '/$path';
          final fallbackRequest = http.Request(method, Uri.parse('$fallbackBase$cleanPath'));
          fallbackRequest.headers.addAll({
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-HuTube-Client': AppConfig.standard.clientHeader,
            if (accessToken != null) 'Authorization': 'Bearer $accessToken',
          });
          if (body != null) fallbackRequest.body = jsonEncode(body);
          final streamed = await client.send(fallbackRequest).timeout(const Duration(seconds: 15));
          final response = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 15));
          _currentBaseUrl = fallback;
          NetworkStatus.instance.markAvailable();
          return _decodeResponse(response);
        } catch (_) {}
      }
      unawaited(checkConnection());
      throw ApiFailure.network;
    } on http.ClientException {
      unawaited(checkConnection());
      throw ApiFailure.network;
    }
  }

  Future<bool> checkConnection() async {
    final inFlight = _connectionCheck;
    if (inFlight != null) return inFlight;
    final flight = _performConnectionCheck();
    _connectionCheck = flight.whenComplete(() => _connectionCheck = null);
    return _connectionCheck!;
  }

  Future<bool> _performConnectionCheck() async {
    final status = NetworkStatus.instance;
    status.beginCheck();
    try {
      await client
          .get(
            Uri.parse(_buildUrl('/system/config')),
            headers: {'X-HuTube-Client': AppConfig.standard.clientHeader},
          )
          .timeout(const Duration(seconds: 8));
      status.markAvailable();
      return true;
    } on TimeoutException {
      status.markUnavailable();
      return false;
    } on SocketException {
      status.markUnavailable();
      return false;
    } on http.ClientException {
      status.markUnavailable();
      return false;
    } catch (_) {
      status.markUnavailable();
      return false;
    }
  }

  dynamic _decodeResponse(http.Response response) {
    dynamic data = <String, dynamic>{};
    try {
      if (response.body.isNotEmpty) {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      }
    } on FormatException {
      // Proxies may return HTML errors.
    }

    if (response.statusCode >= 400) {
      final errorData = data is Map<String, dynamic>
          ? data
          : <String, dynamic>{};
      throw AppError.fromResponse(response.statusCode, errorData);
    }
    return data;
  }
}
