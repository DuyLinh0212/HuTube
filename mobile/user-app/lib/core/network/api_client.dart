import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/app_config.dart';
import '../errors/app_error.dart';

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

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : client = client ?? http.Client(),
      baseUrl = baseUrl ?? AppConfig.standard.apiBaseUrl;

  final http.Client client;
  final String baseUrl;

  String _buildUrl(String path) {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$base$cleanPath';
  }

  Future<Map<String, dynamic>> upload(
    String path,
    UploadPayload payload, {
    String? accessToken,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(_buildUrl(path)),
      );
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
      final data = _decodeResponse(response);
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } on AppError {
      rethrow;
    } on TimeoutException {
      throw const ApiFailure(
        0,
        'NETWORK_ERROR',
        'Tải ảnh quá thời gian. Vui lòng kiểm tra mạng và thử lại.',
      );
    } on SocketException {
      throw const ApiFailure(
        0,
        'NETWORK_ERROR',
        'Không thể kết nối. Kiểm tra mạng rồi thử lại.',
      );
    } on http.ClientException {
      throw const ApiFailure(
        0,
        'NETWORK_ERROR',
        'Không thể kết nối. Kiểm tra mạng rồi thử lại.',
      );
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
      final request = http.Request(
        method,
        Uri.parse(_buildUrl(path)),
      );
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

      return _decodeResponse(response);
    } on AppError {
      rethrow;
    } on TimeoutException {
      throw const ApiFailure(
        0,
        'NETWORK_ERROR',
        'Kết nối quá thời gian. Vui lòng thử lại.',
      );
    } on SocketException {
      throw const ApiFailure(
        0,
        'NETWORK_ERROR',
        'Không thể kết nối. Kiểm tra mạng rồi thử lại.',
      );
    } on http.ClientException {
      throw const ApiFailure(
        0,
        'NETWORK_ERROR',
        'Không thể kết nối. Kiểm tra mạng rồi thử lại.',
      );
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
