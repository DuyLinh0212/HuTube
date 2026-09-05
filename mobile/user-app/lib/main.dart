import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final links = AppLinks();
  runApp(
    HuTubeApp(
      auth: AuthController(ApiClient(), SecureTokenStore()),
      links: links.uriLinkStream,
    ),
  );
}

class HuTubeApp extends StatelessWidget {
  const HuTubeApp({super.key, required this.auth, this.links});
  final AuthController auth;
  final Stream<Uri>? links;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HuTube',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFFF2B66),
        primary: const Color(0xFFFF2B66),
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFFAF8F7),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFAF8F7),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Color(0xFFFFE6EE),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFF2B66), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFF2B66),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFFF2B66),
          minimumSize: const Size(48, 48),
        ),
      ),
    ),
    home: AuthScreen(auth: auth, links: links),
  );
}

class HuTubeLogo extends StatelessWidget {
  const HuTubeLogo({super.key, this.size = 32, this.showWordmark = true});
  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          'assets/logo-mark.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
        if (showWordmark) ...[
          const SizedBox(width: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Hu',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.68,
                    color: const Color(0xFF111827),
                    letterSpacing: -0.5,
                  ),
                ),
                TextSpan(
                  text: 'Tube',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.68,
                    color: const Color(0xFFFF2B66),
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.auth, this.links});
  final AuthController auth;
  final Stream<Uri>? links;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
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
    if (_page == '/account') unawaited(_loadSessions());
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
      final body = switch (page) {
        '/register' => {
          'username': _username.text.trim(),
          'email': _email.text.trim(),
          'displayName': _displayName.text.trim(),
          'password': _password.text,
        },
        '/reset-password' => {'token': token, 'password': _password.text},
        '/verify-email' => {'token': token},
        _ => {'email': _email.text.trim()},
      };
      await auth.api.request(
        'POST',
        '/auth${page == '/resend-verification' ? '/resend-verification' : page}',
        body: body,
      );
      if (!mounted || _page != page || _token != token) return;
      if (page == '/reset-password') await auth.clearSession();
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
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Trang chủ',
                ),
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore_rounded),
                  label: 'Khám phá',
                ),
                NavigationDestination(
                  icon: Icon(Icons.add_circle_outline_rounded),
                  selectedIcon: Icon(Icons.add_circle_rounded),
                  label: 'Đăng video',
                ),
                NavigationDestination(
                  icon: Icon(Icons.subscriptions_outlined),
                  selectedIcon: Icon(Icons.subscriptions_rounded),
                  label: 'Đăng ký',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Hồ sơ',
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
                    CircularProgressIndicator(),
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
                                    ? const Color(0xffffeae8)
                                    : const Color(0xfffff0f4),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _error
                                      ? const Color(0xffffc8c4)
                                      : const Color(0xffffccd8),
                                ),
                              ),
                              child: Text(
                                message,
                                style: TextStyle(
                                  color: _error
                                      ? const Color(0xff962c26)
                                      : const Color(0xffc2185b),
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
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: Color(0xff14223b),
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
      }, style: const TextStyle(color: Color(0xff526179), height: 1.6)),
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
                    backgroundColor: const Color(0xFFFF2B66),
                    foregroundColor: Colors.white,
                    elevation: 3,
                    shadowColor: const Color(0xFFFF2B66).withValues(alpha: 0.5),
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
    const Text(
      'Tài khoản của bạn',
      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 24),
    Row(
      children: [
        const CircleAvatar(
          radius: 28,
          backgroundColor: Color(0xffe1eaff),
          child: Icon(Icons.person_outline, size: 30, color: Color(0xffff2b66)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                auth.user!['displayName'] as String,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                auth.user!['email'] as String,
                style: const TextStyle(color: Color(0xff526179)),
              ),
            ],
          ),
        ),
      ],
    ),
    const SizedBox(height: 16),
    const Row(
      children: [
        Icon(Icons.verified_outlined, size: 18, color: Color(0xffff2b66)),
        SizedBox(width: 8),
        Text('Email đã xác minh'),
      ],
    ),
    const SizedBox(height: 32),
    const Divider(),
    Row(
      children: [
        const Expanded(
          child: Text(
            'Thiết bị đăng nhập',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: 'Tải lại thiết bị',
          onPressed: _sessionsLoading || _busy ? null : _loadSessions,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    const Text(
      'Thu hồi phiên trên thiết bị bạn không còn sử dụng.',
      style: TextStyle(color: Color(0xff526179), height: 1.5),
    ),
    const SizedBox(height: 16),
    if (_sessionsLoading) const LinearProgressIndicator(),
    if (!_sessionsLoading && _sessions.isEmpty)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text('Chưa tải được danh sách thiết bị. Chọn tải lại để thử.'),
      ),
    for (final session in _sessions)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          session['platform'] == 'mobile'
              ? Icons.phone_android
              : Icons.computer,
        ),
        title: Text(session['deviceName'] as String),
        subtitle: Text(
          session['isCurrent'] == true
              ? 'Thiết bị này'
              : 'Hoạt động: ${_date(session['lastActiveAt'] as String)}',
        ),
        trailing: session['isCurrent'] == true
            ? const Icon(Icons.check_circle_outline, color: Color(0xffff2b66))
            : TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await auth.protected(
                          'DELETE',
                          '/auth/sessions/${Uri.encodeComponent(session['sessionId'] as String)}',
                        );
                        await _loadSessions();
                      }),
                child: const Text('Thu hồi'),
              ),
      ),
    const SizedBox(height: 16),
    OutlinedButton(
      onPressed: _busy
          ? null
          : () => _run(() async {
              await auth.protected('POST', '/auth/logout-others');
              await _loadSessions();
              if (mounted) {
                setState(() => _message = 'Đã đăng xuất tất cả thiết bị khác.');
              }
            }),
      child: const Text('Đăng xuất thiết bị khác'),
    ),
    const SizedBox(height: 12),
    FilledButton(
      onPressed: _busy ? null : () => _run(auth.logout),
      child: const Text('Đăng xuất'),
    ),
  ];

  String _date(String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return 'Không rõ';
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
