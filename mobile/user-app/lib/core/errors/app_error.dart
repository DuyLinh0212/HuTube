import '../localization/app_strings.dart';

enum AppErrorKind {
  networkUnavailable,
  timeout,
  cancelled,
  unauthorized,
  forbidden,
  notFound,
  validation,
  conflict,
  server,
  unknown,
}

class ApiFailure implements Exception, LocalizedApiFailure {
  const ApiFailure(
    this.status,
    this.code,
    this.message, {
    this.kind = AppErrorKind.unknown,
    this.traceId,
    this.detail,
  });

  final int status;
  @override
  final String code;
  final String message;
  final AppErrorKind kind;
  final String? traceId;
  final String? detail;

  @override
  String toString() => message;

  factory ApiFailure.fromResponse(int status, Map<String, dynamic> data) {
    final code = data['code'] as String? ?? 'REQUEST_FAILED';
    final traceId = data['traceId'] as String?;
    final detail = data['detail'] as String?;

    AppErrorKind kind;
    if (status == 401) {
      kind = AppErrorKind.unauthorized;
    } else if (status == 403) {
      kind = AppErrorKind.forbidden;
    } else if (status == 404) {
      kind = AppErrorKind.notFound;
    } else if (status == 409) {
      kind = AppErrorKind.conflict;
    } else if (status == 400 || status == 422) {
      kind = AppErrorKind.validation;
    } else if (status >= 500) {
      kind = AppErrorKind.server;
    } else {
      kind = AppErrorKind.unknown;
    }

    final messageKey = switch (code) {
      'INVALID_CREDENTIALS' => 'auth.invalidCredentials',
      'EMAIL_NOT_VERIFIED' || 'EMAIL_UNVERIFIED' => 'auth.emailNotVerified',
      'ACCOUNT_SUSPENDED' || 'USER_SUSPENDED' || 'ACCOUNT_BLOCKED' =>
        'auth.accountSuspended',
      'ACCOUNT_BANNED' || 'USER_BANNED' => 'auth.accountBanned',
      'RATE_LIMITED' || 'RATE_LIMIT_EXCEEDED' => 'common.rateLimited',
      'STORAGE_UPLOAD_FAILED' => 'common.imageUploadError',
      'ONE_CHANNEL_LIMIT_EXCEEDED' => 'common.oneChannelLimit',
      'CHANNEL_HANDLE_ALREADY_EXISTS' => 'common.handleTaken',
      _ => 'common.requestError',
    };
    final message = AppStrings.t(messageKey);

    return ApiFailure(
      status,
      code,
      message,
      kind: kind,
      traceId: traceId,
      detail: detail,
    );
  }

  static ApiFailure get network => ApiFailure(
    0,
    'NETWORK_ERROR',
    AppStrings.t('common.networkError'),
    kind: AppErrorKind.networkUnavailable,
  );

  static ApiFailure get timeoutError => ApiFailure(
    0,
    'NETWORK_TIMEOUT',
    AppStrings.t('common.timeoutError'),
    kind: AppErrorKind.timeout,
  );
}

/// Standard AppError type alias per Mobile Architecture doc
typedef AppError = ApiFailure;
