import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'core/errors/app_error.dart';
import 'core/localization/app_strings.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_store.dart';

export 'core/config/app_config.dart';
export 'core/errors/app_error.dart';
export 'core/network/api_client.dart';
export 'core/storage/token_store.dart';
export 'core/deep_links/deep_link_service.dart';

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
  Future<void>? _googleInitialization;
  static const _googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '968220896298-or85f9g8ibu45tdbf0svsbiqt54g7iml.apps.googleusercontent.com',
  );
  static const _googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );
  bool get authenticated => user != null;
  String? get accessToken => _accessToken;
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
          ? AppStrings.t('auth.sessionExpired')
          : AppStrings.apiError(error);
    } catch (_) {
      notice = AppStrings.t('auth.storageError');
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

  Future<String> _deviceId() async {
    final DeviceIdStore? deviceStore = store is DeviceIdStore
        ? store as DeviceIdStore
        : null;
    final existing = await deviceStore?.readDeviceId();
    if (existing != null && existing.trim().isNotEmpty) return existing;
    final random = math.Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    final generated = 'mobile-${base64UrlEncode(bytes).replaceAll('=', '')}';
    if (deviceStore != null) {
      try {
        await _storage(() => deviceStore.writeDeviceId(generated));
      } catch (_) {
        // A transient secure-storage failure must not prevent a valid login.
      }
    }
    return generated;
  }

  Future<void> login(String email, String password) async {
    final generation = ++_generation;
    final deviceId = await _deviceId();
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
        'deviceId': deviceId,
      },
    );
    await _accept(result, generation);
  }

  Future<void> loginWithGoogleCredential(String credential) async {
    if (credential.trim().isEmpty) {
      throw const ApiFailure(
        401,
        'INVALID_GOOGLE_TOKEN',
        'Google không trả về mã xác thực hợp lệ.',
      );
    }
    final generation = ++_generation;
    final deviceId = await _deviceId();
    final result = await api.request(
      'POST',
      '/auth/google',
      body: {
        'credential': credential,
        'platform': 'mobile',
        'deviceName': Platform.isIOS
            ? 'HuTube · iPhone / iPad'
            : 'HuTube · Android',
        'deviceId': deviceId,
      },
    );
    await _accept(result, generation);
  }

  Future<void> loginWithGoogle() async {
    if (_googleWebClientId.isEmpty) {
      throw const ApiFailure(
        503,
        'GOOGLE_LOGIN_NOT_CONFIGURED',
        'Đăng nhập Google chưa được cấu hình cho ứng dụng.',
      );
    }
    await (_googleInitialization ??= GoogleSignIn.instance.initialize(
      clientId: Platform.isIOS && _googleIosClientId.isNotEmpty
          ? _googleIosClientId
          : null,
      serverClientId: _googleWebClientId,
    ));
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const ApiFailure(
        503,
        'GOOGLE_LOGIN_NOT_CONFIGURED',
        'Thiết bị này chưa hỗ trợ đăng nhập Google.',
      );
    }
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final credential = account.authentication.idToken;
      if (credential == null || credential.isEmpty) {
        throw const ApiFailure(
          401,
          'INVALID_GOOGLE_TOKEN',
          'Google không trả về mã xác thực hợp lệ.',
        );
      }
      await loginWithGoogleCredential(credential);
    } on ApiFailure {
      rethrow;
    } on GoogleSignInException catch (error) {
      throw switch (error.code) {
        GoogleSignInExceptionCode.canceled => const ApiFailure(
          400,
          'GOOGLE_LOGIN_CANCELLED',
          'Bạn đã hủy đăng nhập Google.',
        ),
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          const ApiFailure(
            503,
            'GOOGLE_LOGIN_NOT_CONFIGURED',
            'Google Sign-In của ứng dụng chưa được cấu hình đúng. '
                'Kiểm tra Web client ID, package Android và SHA chứng chỉ ký.',
          ),
        GoogleSignInExceptionCode.uiUnavailable => const ApiFailure(
          503,
          'GOOGLE_LOGIN_NOT_CONFIGURED',
          'Thiết bị hiện không thể mở màn hình đăng nhập Google.',
        ),
        _ => const ApiFailure(
          401,
          'INVALID_GOOGLE_TOKEN',
          'Không thể hoàn tất đăng nhập Google. Vui lòng thử lại.',
        ),
      };
    } catch (_) {
      throw const ApiFailure(
        401,
        'INVALID_GOOGLE_TOKEN',
        'Không thể hoàn tất đăng nhập Google. Vui lòng thử lại.',
      );
    }
  }

  Future<void> register({
    required String username,
    required String email,
    required String displayName,
    required String password,
  }) async {
    await api.request(
      'POST',
      '/auth/register',
      body: {
        'username': username.trim(),
        'email': email.trim(),
        'displayName': displayName.trim(),
        'password': password,
      },
    );
  }

  Future<void> verifyEmail(String token) async {
    await api.request('POST', '/auth/verify-email', body: {'token': token});
  }

  Future<void> forgotPassword(String email) async {
    await api.request(
      'POST',
      '/auth/forgot-password',
      body: {'email': email.trim()},
    );
  }

  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    await api.request(
      'POST',
      '/auth/reset-password',
      body: {'token': token, 'password': password},
    );
    await clearSession();
  }

  Future<void> resendVerification(String email) async {
    await api.request(
      'POST',
      '/auth/resend-verification',
      body: {'email': email.trim()},
    );
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
              ? AppStrings.apiError(error)
              : AppStrings.t('auth.sessionExpired'),
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
        await clearSession(AppStrings.apiError(error));
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
          await clearSession(AppStrings.t('auth.sessionExpired'));
        }
        rethrow;
      }
    }
  }

  Future<List<dynamic>> protectedList(String path) async {
    final generation = _generation;
    final sentToken = _accessToken;
    try {
      return await api.requestList('GET', path, accessToken: _accessToken);
    } on ApiFailure catch (error) {
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
        return await api.requestList('GET', path, accessToken: _accessToken);
      } on ApiFailure catch (retryError) {
        if (retryError.status == 401) {
          await clearSession(AppStrings.t('auth.sessionExpired'));
        }
        rethrow;
      }
    }
  }

  Future<Map<String, dynamic>> protectedUpload(
    String path,
    UploadPayload payload,
  ) async {
    final generation = _generation;
    final sentToken = _accessToken;
    try {
      return await api.upload(path, payload, accessToken: _accessToken);
    } on ApiFailure catch (error) {
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
        return await api.upload(path, payload, accessToken: _accessToken);
      } on ApiFailure catch (retryError) {
        if (retryError.status == 401) {
          await clearSession(AppStrings.t('auth.sessionExpired'));
        }
        rethrow;
      }
    }
  }

  Future<Map<String, dynamic>> protectedMultipart(
    String path, {
    required Map<String, String> fields,
    required List<MultipartFilePayload> files,
    Map<String, String>? headers,
  }) async {
    final generation = _generation;
    final sentToken = _accessToken;
    try {
      return await api.uploadMultipart(
        path,
        fields: fields,
        files: files,
        accessToken: _accessToken,
        headers: headers,
      );
    } on ApiFailure catch (error) {
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
        return await api.uploadMultipart(
          path,
          fields: fields,
          files: files,
          accessToken: _accessToken,
          headers: headers,
        );
      } on ApiFailure catch (retryError) {
        if (retryError.status == 401) {
          await clearSession(AppStrings.t('auth.sessionExpired'));
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
        notice = AppStrings.t('auth.logoutOffline');
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

String? validatePassword(String? value) {
  final text = value ?? '';
  if (text.length < 10 ||
      text.length > 128 ||
      !RegExp(r'[A-Z]').hasMatch(text) ||
      !RegExp(r'[a-z]').hasMatch(text) ||
      !RegExp(r'[0-9]').hasMatch(text)) {
    return AppStrings.t('auth.passwordRequirement');
  }
  return null;
}
