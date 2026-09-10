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

class ApiFailure implements Exception {
  const ApiFailure(
    this.status,
    this.code,
    this.message, {
    this.kind = AppErrorKind.unknown,
    this.traceId,
    this.detail,
  });

  final int status;
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

    final message = switch (code) {
      'INVALID_CREDENTIALS' => 'Email hoặc mật khẩu chưa đúng.',
      'EMAIL_NOT_VERIFIED' => 'Bạn cần xác minh email trước khi đăng nhập.',
      'ACCOUNT_SUSPENDED' || 'USER_SUSPENDED' =>
        'Tài khoản đang bị tạm khóa. Vui lòng liên hệ hỗ trợ.',
      'ACCOUNT_BANNED' ||
      'USER_BANNED' => 'Tài khoản đã bị khóa. Vui lòng liên hệ hỗ trợ.',
      'RATE_LIMITED' || 'RATE_LIMIT_EXCEEDED' =>
        'Bạn đã thử quá nhiều lần. Vui lòng đợi một lúc rồi thử lại.',
      'STORAGE_UPLOAD_FAILED' =>
        'Không thể tải ảnh lên kho lưu trữ. Vui lòng thử lại.',
      'ONE_CHANNEL_LIMIT_EXCEEDED' =>
        'Mỗi tài khoản chỉ được phép sở hữu tối đa một kênh.',
      'CHANNEL_HANDLE_ALREADY_EXISTS' =>
        'Định danh kênh này đã có người sử dụng. Vui lòng chọn tên khác.',
      _ => detail ?? 'Không thể thực hiện yêu cầu. Vui lòng thử lại.',
    };

    return ApiFailure(
      status,
      code,
      message,
      kind: kind,
      traceId: traceId,
      detail: detail,
    );
  }

  static const network = ApiFailure(
    0,
    'NETWORK_ERROR',
    'Không thể kết nối. Kiểm tra mạng rồi thử lại.',
    kind: AppErrorKind.networkUnavailable,
  );

  static const timeoutError = ApiFailure(
    0,
    'NETWORK_ERROR',
    'Kết nối quá thời gian. Vui lòng thử lại.',
    kind: AppErrorKind.timeout,
  );
}

/// Standard AppError type alias per Mobile Architecture doc
typedef AppError = ApiFailure;
