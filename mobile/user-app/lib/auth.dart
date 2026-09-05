import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiFailure implements Exception {
  const ApiFailure(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : client = client ?? http.Client(),
      baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'http://10.0.2.2:5080/api/v1',
          );
  final http.Client client;
  final String baseUrl;

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) async {
    try {
      final request = http.Request(
        method,
        Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path'),
      );
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      });
      if (body != null) request.body = jsonEncode(body);
      final response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 20)),
      ).timeout(const Duration(seconds: 20));
      Map<String, dynamic> data = {};
      try {
        if (response.body.isNotEmpty) {
          data =
              jsonDecode(utf8.decode(response.bodyBytes))
                  as Map<String, dynamic>;
        }
      } on FormatException {
        /* Proxies may return HTML errors. */
      }
      if (response.statusCode >= 400) {
        final code = data['code'] as String? ?? 'REQUEST_FAILED';
        throw ApiFailure(response.statusCode, code, switch (code) {
          'INVALID_CREDENTIALS' => 'Email hoặc mật khẩu chưa đúng.',
          'EMAIL_NOT_VERIFIED' => 'Bạn cần xác minh email trước khi đăng nhập.',
          'ACCOUNT_SUSPENDED' || 'USER_SUSPENDED' =>
            'Tài khoản đang bị tạm khóa. Vui lòng liên hệ hỗ trợ.',
          'ACCOUNT_BANNED' ||
          'USER_BANNED' => 'Tài khoản đã bị khóa. Vui lòng liên hệ hỗ trợ.',
          'RATE_LIMITED' =>
            'Bạn đã thử quá nhiều lần. Vui lòng đợi một lúc rồi thử lại.',
          _ =>
            data['detail'] as String? ??
                'Không thể thực hiện yêu cầu. Vui lòng thử lại.',
        });
      }
      return data;
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
}

abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _key = 'hutube.refreshToken';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class AuthController extends ChangeNotifier {
  AuthController(this.api, this.store);
  final ApiClient api;
  final TokenStore store;
  Map<String, dynamic>? user;
  String? _accessToken;
  String? _refreshToken;
  bool restoring = true;
  String? notice;
  int _generation = 0;
  Future<void>? _refreshing;
  Future<void> _storageWork = Future.value();
  bool _disposed = false;
  bool get authenticated => user != null;
  int get sessionGeneration => _generation;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _storage(Future<void> Function() work) {
    final next = _storageWork.then((_) => work());
    _storageWork = next.catchError((Object _) {});
    return next;
  }

  Future<void> restore() async {
    final generation = _generation;
    restoring = true;
    _changed();
    try {
      final token = await store.read();
      if (generation != _generation) return;
      _refreshToken = token;
      if (token != null) await refresh();
    } on ApiFailure catch (error) {
      notice = error.status == 401
          ? 'Phiên đã hết hạn. Vui lòng đăng nhập lại.'
          : error.message;
    } catch (_) {
      notice = 'Không thể mở bộ nhớ bảo mật. Vui lòng thử lại.';
    } finally {
      restoring = false;
      _changed();
    }
  }

  Future<void> _accept(Map<String, dynamic> response, int generation) async {
    final refreshToken = response['refreshToken'] as String;
    if (generation != _generation) {
      await api.request(
        'POST',
        '/auth/logout',
        body: {'refreshToken': refreshToken},
      );
      return;
    }
    try {
      await _storage(() => store.write(refreshToken));
    } catch (_) {
      await api.request(
        'POST',
        '/auth/logout',
        body: {'refreshToken': refreshToken},
      );
      rethrow;
    }
    if (generation != _generation) {
      await api.request(
        'POST',
        '/auth/logout',
        body: {'refreshToken': refreshToken},
      );
      return;
    }
    _refreshToken = refreshToken;
    _accessToken = response['accessToken'] as String;
    user = response['user'] as Map<String, dynamic>;
    notice = null;
    _changed();
  }

  Future<void> login(String email, String password) async {
    final generation = ++_generation;
    final result = await api.request(
      'POST',
      '/auth/login',
      body: {
        'email': email.trim(),
        'password': password,
        'platform': 'mobile',
        'deviceName': Platform.isIOS
            ? 'HuTube · iPhone / iPad'
            : 'HuTube · Android',
      },
    );
    await _accept(result, generation);
  }

  Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  Future<void> _refresh() async {
    final generation = _generation;
    if (_refreshToken == null) {
      throw const ApiFailure(401, 'SESSION_EXPIRED', 'Vui lòng đăng nhập lại.');
    }
    try {
      final response = await api.request(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': _refreshToken},
      );
      await _accept(response, generation);
    } on ApiFailure catch (error) {
      if (generation == _generation &&
          (error.status == 401 || error.status == 403)) {
        await clearSession(
          error.status == 403
              ? error.message
              : 'Phiên đã hết hạn. Vui lòng đăng nhập lại.',
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> protected(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final generation = _generation;
    final sentToken = _accessToken;
    try {
      return await api.request(
        method,
        path,
        body: body,
        accessToken: _accessToken,
      );
    } on ApiFailure catch (error) {
      if (error.status == 403 &&
          (error.code.contains('SUSPENDED') ||
              error.code.contains('BANNED') ||
              error.code == 'ACCOUNT_BLOCKED')) {
        await clearSession(error.message);
        rethrow;
      }
      if (error.status != 401 || generation != _generation) rethrow;
      if (sentToken == _accessToken) await refresh();
      if (generation != _generation) {
        throw const ApiFailure(
          401,
          'SESSION_EXPIRED',
          'Vui lòng đăng nhập lại.',
        );
      }
      try {
        return await api.request(
          method,
          path,
          body: body,
          accessToken: _accessToken,
        );
      } on ApiFailure catch (retryError) {
        if (retryError.status == 401) {
          await clearSession('Phiên đã hết hạn. Vui lòng đăng nhập lại.');
        }
        rethrow;
      }
    }
  }

  Future<void> clearSession([String? message]) async {
    ++_generation;
    _accessToken = null;
    _refreshToken = null;
    user = null;
    notice = message;
    _changed();
    await _storage(store.clear);
  }

  Future<void> logout() async {
    final token = _refreshToken;
    // Invalidate in-flight responses before awaiting the server or storage.
    await clearSession();
    if (token != null) {
      try {
        await api.request(
          'POST',
          '/auth/logout',
          body: {'refreshToken': token},
        );
      } on ApiFailure {
        notice =
            'Đã thoát trên thiết bị. Chưa xác nhận thu hồi phiên trên máy chủ; hãy thu hồi từ thiết bị khác khi có mạng.';
        _changed();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    api.client.close();
    super.dispose();
  }
}

class AuthLink {
  const AuthLink(this.path, this.token);
  final String path;
  final String? token;
  static AuthLink? parse(Uri uri) {
    if (uri.scheme != 'hutube' ||
        uri.host != 'auth' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort) {
      return null;
    }
    if (!{
      '/login',
      '/account',
      '/verify-email',
      '/reset-password',
    }.contains(uri.path)) {
      return null;
    }
    return AuthLink(uri.path, uri.queryParameters['token']);
  }
}

String? validatePassword(String? value) {
  final text = value ?? '';
  if (text.length < 10 ||
      text.length > 128 ||
      !RegExp(r'[A-Z]').hasMatch(text) ||
      !RegExp(r'[a-z]').hasMatch(text) ||
      !RegExp(r'[0-9]').hasMatch(text)) {
    return '10–128 ký tự, gồm chữ hoa, chữ thường và số.';
  }
  return null;
}
