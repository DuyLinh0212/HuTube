import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../account/screens/profile_screen.dart';
import '../../auth.dart';
import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import 'app_logo.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.auth, this.links});
  final AuthController auth;
  final Stream<Uri>? links;

  @override
  State<AppShell> createState() => _AppShellState();
}

/// Backward compatibility alias for AuthScreen
typedef AuthScreen = AppShell;

class _AppShellState extends State<AppShell> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  StreamSubscription<Uri>? _subscription;
  String _page = '/login';
  String? _token;
  String? _message;
  bool _error = false;
  bool _verificationSuggested = false;
  bool _busy = false;
  bool _hidden = true;
  bool _sessionsLoading = false;
  bool _sessionsLoaded = false;
  int _selectedDestination = 4;
  List<Map<String, dynamic>> _sessions = [];
  int _operation = 0;
  AuthController get auth => widget.auth;

  @override
  void initState() {
    super.initState();
    auth.addListener(_authChanged);
    _subscription = widget.links?.listen(
      _link,
      onError: (Object _) {
        if (mounted) {
          setState(() {
            _message = 'Không thể mở liên kết. Vui lòng thử lại.';
            _error = true;
          });
        }
      },
    );
    unawaited(auth.restore());
  }

  void _authChanged() {
    if (!mounted) return;
    setState(() {
      if (!auth.authenticated) {
        _sessions = [];
        _sessionsLoaded = false;
        if (_page == '/account') _page = '/login';
      } else if (_page == '/login' || _page == '/register') {
        _page = '/account';
        _message = null;
        _password.clear();
        _confirm.clear();
      }
    });
    if (_page == '/account' && !_sessionsLoaded && !_sessionsLoading) {
      unawaited(_loadSessions());
    }
  }

  void _link(Uri uri) {
    final link = AuthLink.parse(uri);
    if (link == null) return;
    _navigate(link.path, token: link.token);
  }

  void _navigate(String page, {String? token}) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      ++_operation;
      _busy = false;
      _page = page == '/account' && !auth.authenticated ? '/login' : page;
      _token = token;
      _message = page == '/account' && !auth.authenticated
          ? 'Đăng nhập để tiếp tục đến tài khoản của bạn.'
          : null;
      _error = false;
      _verificationSuggested = false;
      _password.clear();
      _confirm.clear();
      _hidden = true;
    });
    if (_page == '/account') {
      unawaited(_loadSessions());
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _message = null;
      _error = false;
      _verificationSuggested = false;
    });
    try {
      await action();
    } on ApiFailure catch (error) {
      if (mounted && operation == _operation) {
        setState(() {
          _message = error.message;
          _error = true;
          _verificationSuggested =
              error.code == 'EMAIL_NOT_VERIFIED' ||
              error.code == 'EMAIL_UNVERIFIED';
        });
      }
    } catch (_) {
      if (mounted && operation == _operation) {
        setState(() {
          _message = 'Có lỗi xảy ra. Vui lòng thử lại.';
          _error = true;
          _verificationSuggested = false;
        });
      }
    } finally {
      if (mounted && operation == _operation) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final page = _page;
    final token = _token;
    await _run(() async {
      if (page == '/login') {
        await auth.login(_email.text, _password.text);
        TextInput.finishAutofillContext();
        return;
      }
      if (page == '/register') {
        await auth.register(
          username: _username.text,
          email: _email.text,
          displayName: _displayName.text,
          password: _password.text,
        );
      } else if (page == '/reset-password') {
        await auth.resetPassword(token: token ?? '', password: _password.text);
      } else if (page == '/verify-email') {
        await auth.verifyEmail(token ?? '');
      } else if (page == '/forgot-password') {
        await auth.forgotPassword(_email.text);
      } else if (page == '/resend-verification') {
        await auth.resendVerification(_email.text);
      }

      if (!mounted || _page != page || _token != token) return;
      setState(() {
        _message = switch (page) {
          '/register' =>
            'Tài khoản đã được tạo. Mở email để xác minh, sau đó đăng nhập.',
          '/verify-email' =>
            'Email đã được xác minh. Bạn có thể đăng nhập ngay.',
          '/reset-password' =>
            'Mật khẩu đã được đổi. Hãy đăng nhập bằng mật khẩu mới.',
          '/forgot-password' =>
            'Nếu email thuộc tài khoản HuTube, bạn sẽ nhận được liên kết đặt lại mật khẩu.',
          _ =>
            'Nếu tài khoản cần xác minh, chúng tôi đã gửi lại email. Kiểm tra cả thư rác.',
        };
        if (page == '/verify-email' ||
            page == '/reset-password' ||
            page == '/register') {
          _page = '/login';
          _token = null;
          _password.clear();
          _confirm.clear();
        }
      });
    });
  }

  Future<void> _loadSessions() async {
    if (!auth.authenticated || _sessionsLoading) return;
    setState(() => _sessionsLoading = true);
    final generation = auth.sessionGeneration;
    try {
      final result = await auth.protected('GET', '/auth/sessions');
      if (mounted &&
          generation == auth.sessionGeneration &&
          auth.authenticated) {
        setState(() {
          _sessions = (result['items'] as List).cast<Map<String, dynamic>>();
          _sessionsLoaded = true;
        });
      }
    } on ApiFailure catch (error) {
      if (mounted && auth.authenticated) {
        setState(() {
          _message = error.message;
          _error = true;
        });
      }
    } finally {
      if (mounted) setState(() => _sessionsLoading = false);
    }
  }

  Future<void> _diagnostic() async {
    await _run(() async {
      final info = await auth.api.request('GET', '/system/info');
      if (!mounted) return;
      setState(() {
        _message =
            'Đã kết nối HuTube · ${info['environment'] ?? 'API đang hoạt động'}';
      });
    });
  }

  void _onDestinationSelected(int index) {
    if (index == 4) {
      setState(() => _selectedDestination = 4);
      return;
    }
    const labels = ['Trang chủ', 'Khám phá', 'Đăng video', 'Kênh đăng ký'];
    _showNavigationNotice(labels[index]);
  }

  void _showNavigationNotice(String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$label sẽ được kết nối khi module tương ứng hoàn tất.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  void dispose() {
    auth.removeListener(_authChanged);
    _subscription?.cancel();
    for (final c in [_email, _password, _confirm, _username, _displayName]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = _message ?? auth.notice;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const HuTubeLogo(size: 28),
        actions: [
          if (auth.authenticated && _page == '/account')
            IconButton(
              onPressed: () => _showNavigationNotice('Tìm kiếm'),
              tooltip: 'Tìm kiếm',
              icon: const Icon(Icons.search_rounded),
            ),
          if (auth.authenticated && _page == '/account')
            IconButton(
              onPressed: () => _showNavigationNotice('Thông báo'),
              tooltip: 'Thông báo',
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          IconButton(
            onPressed: _busy ? null : _diagnostic,
            tooltip: 'Kiểm tra kết nối',
            icon: const Icon(Icons.wifi_tethering),
          ),
        ],
      ),
      bottomNavigationBar: auth.authenticated && _page == '/account'
          ? NavigationBar(
              selectedIndex: _selectedDestination,
              onDestinationSelected: _onDestinationSelected,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home_rounded),
                  label: AppStrings.t('nav.home'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.explore_outlined),
                  selectedIcon: const Icon(Icons.explore_rounded),
                  label: AppStrings.t('nav.explore'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  selectedIcon: const Icon(Icons.add_circle_rounded),
                  label: AppStrings.t('nav.upload'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.subscriptions_outlined),
                  selectedIcon: const Icon(Icons.subscriptions_rounded),
                  label: AppStrings.t('nav.subscriptions'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.person_outline_rounded),
                  selectedIcon: const Icon(Icons.person_rounded),
                  label: AppStrings.t('nav.profile'),
                ),
              ],
            )
          : null,
      body: SafeArea(
        child: auth.restoring
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primaryPink),
                    SizedBox(height: 20),
                    Text('Đang khôi phục phiên đăng nhập…'),
                  ],
                ),
              )
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (message != null) ...[
                          Semantics(
                            liveRegion: true,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: _error
                                    ? AppColors.dangerBg
                                    : AppColors.primaryPink.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _error
                                      ? AppColors.dangerBorder
                                      : AppColors.primaryPink.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                message,
                                style: TextStyle(
                                  color: _error
                                      ? AppColors.danger
                                      : AppColors.primaryPink,
                                  height: 1.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (_page == '/account' && auth.authenticated)
                          ..._account()
                        else
                          ..._authForm(),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  List<Widget> _authForm() {
    final register = _page == '/register';
    final login = _page == '/login';
    final reset = _page == '/reset-password';
    final verify = _page == '/verify-email';
    final title = switch (_page) {
      '/register' => 'Tạo tài khoản',
      '/forgot-password' => 'Quên mật khẩu?',
      '/reset-password' => 'Đặt mật khẩu mới',
      '/verify-email' => 'Xác minh email',
      '/resend-verification' => 'Gửi lại email xác minh',
      _ => 'Chào mừng trở lại',
    };
    final missingToken =
        (reset || verify) && (_token == null || _token!.isEmpty);
    return [
      Text(
        title,
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      const SizedBox(height: 10),
      Text(switch (_page) {
        '/register' =>
          'Bắt đầu với HuTube. Xác minh email để bảo vệ tài khoản của bạn.',
        '/forgot-password' ||
        '/resend-verification' => 'Nhập email bạn đã dùng để đăng ký HuTube.',
        '/verify-email' =>
          missingToken
              ? 'Liên kết thiếu mã xác minh. Hãy yêu cầu một email mới.'
              : 'Xác nhận địa chỉ email để hoàn tất đăng ký.',
        '/reset-password' =>
          missingToken
              ? 'Liên kết thiếu mã đặt lại. Hãy yêu cầu một email mới.'
              : 'Chọn mật khẩu mới, khác mật khẩu bạn dùng ở nơi khác.',
        _ => 'Đăng nhập để tiếp tục với tài khoản của bạn.',
      }, style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color ?? const Color(0xff526179), height: 1.6)),
      const SizedBox(height: 28),
      Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (register) ...[
                _field(
                  _displayName,
                  'Tên hiển thị',
                  icon: Icons.person_outline,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty || v!.trim().length > 120
                      ? 'Nhập tên hiển thị từ 1 đến 120 ký tự.'
                      : null,
                ),
                _field(
                  _username,
                  'Tên người dùng',
                  icon: Icons.alternate_email,
                  validator: (v) =>
                      RegExp(r'^[A-Za-z0-9_.-]{3,50}$').hasMatch(v ?? '')
                      ? null
                      : '3–50 ký tự: chữ, số, dấu chấm, gạch dưới hoặc gạch ngang.',
                ),
              ],
              if (!reset && !verify)
                _field(
                  _email,
                  'Email',
                  icon: Icons.mail_outline,
                  email: true,
                  validator: (v) =>
                      RegExp(
                        r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                      ).hasMatch((v ?? '').trim())
                      ? null
                      : 'Nhập địa chỉ email hợp lệ.',
                ),
              if ((login || register || reset) && !missingToken) ...[
                _field(
                  _password,
                  reset ? 'Mật khẩu mới' : 'Mật khẩu',
                  secret: true,
                  validator: login
                      ? (v) =>
                            (v ?? '').isEmpty ? 'Nhập mật khẩu của bạn.' : null
                      : validatePassword,
                ),
                if (!login) ...[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      '10–128 ký tự, gồm chữ hoa, chữ thường và số.',
                      style: TextStyle(color: Color(0xff526179), fontSize: 13),
                    ),
                  ),
                  _field(
                    _confirm,
                    'Nhập lại mật khẩu',
                    secret: true,
                    validator: (v) => v != _password.text
                        ? 'Mật khẩu nhập lại chưa khớp.'
                        : null,
                  ),
                ],
              ],
              if (login)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => _navigate('/forgot-password'),
                    child: const Text('Quên mật khẩu?'),
                  ),
                ),
              if (!missingToken)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryPink,
                    foregroundColor: Colors.white,
                    elevation: 3,
                    shadowColor: AppColors.primaryPink.withValues(alpha: 0.5),
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          login
                              ? 'Đăng nhập'
                              : register
                              ? 'Tạo tài khoản'
                              : verify
                              ? 'Xác minh email'
                              : reset
                              ? 'Lưu mật khẩu mới'
                              : 'Gửi email',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              if (login) ...[
                const SizedBox(height: 14),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _busy ? null : () => _run(auth.loginWithGoogle),
                  child: const Text('Tiếp tục với Google'),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      if (login) ...[
        TextButton(
          onPressed: _busy ? null : () => _navigate('/register'),
          child: const Text('Chưa có tài khoản? Đăng ký'),
        ),
        if (_verificationSuggested)
          TextButton(
            onPressed: _busy ? null : () => _navigate('/resend-verification'),
            child: const Text('Gửi lại email xác minh'),
          ),
        if (auth.notice != null)
          TextButton(
            onPressed: _busy ? null : auth.restore,
            child: const Text('Thử khôi phục phiên lần nữa'),
          ),
      ] else ...[
        if (missingToken)
          TextButton(
            onPressed: () =>
                _navigate(reset ? '/forgot-password' : '/resend-verification'),
            child: const Text('Yêu cầu liên kết mới'),
          ),
        TextButton(
          onPressed: _busy ? null : () => _navigate('/login'),
          child: const Text('Quay lại đăng nhập'),
        ),
      ],
    ];
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    IconData? icon,
    bool email = false,
    bool secret = false,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      key: ValueKey(label),
      controller: controller,
      enabled: !_busy,
      validator: validator,
      obscureText: secret && _hidden,
      autocorrect: !secret && !email,
      enableSuggestions: !secret,
      keyboardType: email ? TextInputType.emailAddress : TextInputType.text,
      autofillHints: email
          ? [AutofillHints.email]
          : secret
          ? [
              _page == '/login'
                  ? AutofillHints.password
                  : AutofillHints.newPassword,
            ]
          : null,
      textInputAction: secret ? TextInputAction.done : TextInputAction.next,
      onFieldSubmitted: secret ? (_) => _submit() : null,
      decoration: InputDecoration(
        labelText: label,
        errorMaxLines: 3,
        prefixIcon: Icon(icon ?? Icons.lock_outline),
        suffixIcon: secret
            ? IconButton(
                tooltip: _hidden ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                onPressed: () => setState(() => _hidden = !_hidden),
                icon: Icon(
                  _hidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              )
            : null,
      ),
    ),
  );

  List<Widget> _account() => [
    ProfileScreen(
      auth: auth,
      sessions: _sessions,
      sessionsLoading: _sessionsLoading,
      onRefreshSessions: _loadSessions,
      onRevokeSession: (sessionId) => _run(() async {
        await auth.protected(
          'DELETE',
          '/auth/sessions/${Uri.encodeComponent(sessionId)}',
        );
        await _loadSessions();
      }),
      onLogoutOthers: () => _run(() async {
        await auth.protected('POST', '/auth/logout-others');
        await _loadSessions();
        if (mounted) {
          setState(() => _message = 'Đã đăng xuất tất cả thiết bị khác.');
        }
      }),
      onLogout: () => _run(auth.logout),
    ),
  ];
}
