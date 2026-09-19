import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../account/screens/profile_screen.dart';
import '../../plans_screen.dart';
import '../../auth.dart';
import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import 'app_logo.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.auth,
    this.links,
    this.initialPage,
    this.initialToken,
  });
  final AuthController auth;
  final Stream<Uri>? links;
  final String? initialPage;
  final String? initialToken;

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
    _page = widget.initialPage ?? _page;
    _token = widget.initialToken;
    auth.addListener(_authChanged);
    _subscription = widget.links?.listen(
      _link,
      onError: (Object _) {
        if (mounted) {
          setState(() {
            _message = AppStrings.t('auth.linkError');
            _error = true;
          });
        }
      },
    );
    // Session restoration is owned by HuTubeApp before the router selects the
    // authentication route. Calling it here a second time can notify GoRouter
    // while this widget is mounting.
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPage != oldWidget.initialPage ||
        widget.initialToken != oldWidget.initialToken) {
      _navigate(widget.initialPage ?? '/login', token: widget.initialToken);
    }
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
          ? AppStrings.t('auth.accountMessage')
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
          _message = AppStrings.apiError(error);
          _error = true;
          _verificationSuggested =
              error.code == 'EMAIL_NOT_VERIFIED' ||
              error.code == 'EMAIL_UNVERIFIED';
        });
      }
    } catch (_) {
      if (mounted && operation == _operation) {
        setState(() {
          _message = AppStrings.t('common.error');
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
          '/register' => AppStrings.t('auth.registerSuccess'),
          '/verify-email' => AppStrings.t('auth.verifySuccess'),
          '/reset-password' => AppStrings.t('auth.resetSuccess'),
          '/forgot-password' => AppStrings.t('auth.forgotSuccess'),
          _ => AppStrings.t('auth.resendSuccess'),
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
          _message = AppStrings.apiError(error, fallback: 'common.error');
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
        _message = AppStrings.format('app.connected', {
          'environment': info['environment'] ?? AppStrings.t('app.apiActive'),
        });
      });
    });
  }

  void _onDestinationSelected(int index) {
    if (index == 4) {
      setState(() => _selectedDestination = 4);
      return;
    }
    if (index == 3) {
      setState(() => _selectedDestination = 3);
      _navigate('/plans');
      return;
    }
    final labels = [
      AppStrings.t('nav.home'),
      AppStrings.t('nav.explore'),
      AppStrings.t('nav.upload'),
    ];
    _showNavigationNotice(labels[index]);
  }

  void _showNavigationNotice(String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.format('app.modulePending', {'label': label}),
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
    final scheme = Theme.of(context).colorScheme;
    final authPage = !auth.authenticated && _page != '/plans';
    if (authPage) return _buildAuthLayout(message, scheme);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const HuTubeLogo(size: 28),
        actions: [
          if (auth.authenticated && _page == '/account')
            IconButton(
              onPressed: () =>
                  _showNavigationNotice(AppStrings.t('common.search')),
              tooltip: AppStrings.t('common.search'),
              icon: const Icon(Icons.search_rounded),
            ),
          if (auth.authenticated && _page == '/account')
            IconButton(
              onPressed: () =>
                  _showNavigationNotice(AppStrings.t('common.notifications')),
              tooltip: AppStrings.t('common.notifications'),
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          IconButton(
            onPressed: _busy ? null : _diagnostic,
            tooltip: AppStrings.t('app.connection'),
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
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primaryPink),
                    SizedBox(height: 20),
                    Text(AppStrings.t('app.restoreSession')),
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
                                    ? scheme.errorContainer
                                    : AppColors.primaryPink.withValues(
                                        alpha: 0.1,
                                      ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _error
                                      ? scheme.error.withValues(alpha: 0.35)
                                      : AppColors.primaryPink.withValues(
                                          alpha: 0.3,
                                        ),
                                ),
                              ),
                              child: Text(
                                message,
                                style: TextStyle(
                                  color: _error
                                      ? scheme.onErrorContainer
                                      : AppColors.primaryPink,
                                  height: 1.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (_page == '/plans')
                          PlansScreen(auth: auth)
                        else if (_page == '/account' && auth.authenticated)
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

  Widget _buildAuthLayout(String? message, ColorScheme scheme) {
    final compact = MediaQuery.sizeOf(context).height < 700;
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  compact ? 16 : 28,
                  24,
                  compact ? 20 : 42,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          'assets/logo-mark.png',
                          width: 30,
                          height: 30,
                        ),
                        const SizedBox(width: 9),
                        RichText(
                          text: const TextSpan(
                            style: TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.6,
                            ),
                            children: [
                              TextSpan(
                                text: 'Hu',
                                style: TextStyle(color: Colors.white),
                              ),
                              TextSpan(
                                text: 'Tube',
                                style: TextStyle(color: AppColors.primary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 18 : 38),
                    Text(
                      'XEM ĐIỀU BẠN YÊU',
                      style: TextStyle(
                        color: AppColors.primaryHover,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      compact
                          ? 'Một nơi cho\nmọi câu chuyện.'
                          : 'Một không gian\ncho mọi câu chuyện.',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: compact ? 25 : 30,
                        height: 1.12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.8,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Khám phá video mới, lưu lại khoảnh khắc yêu thích và chia sẻ điều bạn tạo ra.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .68),
                          height: 1.45,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: EdgeInsets.fromLTRB(24, compact ? 20 : 28, 24, 34),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (message != null) ...[
                        _messageBanner(message, scheme),
                        const SizedBox(height: 18),
                      ],
                      ..._authForm(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageBanner(String message, ColorScheme scheme) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _error ? scheme.errorContainer : AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _error
              ? scheme.error.withValues(alpha: .35)
              : AppColors.primary.withValues(alpha: .22),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: _error ? scheme.onErrorContainer : AppColors.primaryDark,
          height: 1.45,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );

  List<Widget> _authForm() {
    final register = _page == '/register';
    final login = _page == '/login';
    final reset = _page == '/reset-password';
    final verify = _page == '/verify-email';
    final title = switch (_page) {
      '/register' => AppStrings.t('auth.createAccount'),
      '/forgot-password' => AppStrings.t('auth.forgotTitle'),
      '/reset-password' => AppStrings.t('auth.resetTitle'),
      '/verify-email' => AppStrings.t('auth.verifyTitle'),
      '/resend-verification' => AppStrings.t('auth.resendTitle'),
      _ => AppStrings.t('auth.welcome'),
    };
    final missingToken =
        (reset || verify) && (_token == null || _token!.isEmpty);
    return [
      Text(
        title,
        style: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w900,
          color: Theme.of(context).colorScheme.onSurface,
          letterSpacing: -.5,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        switch (_page) {
          '/register' => AppStrings.t('auth.registerDescription'),
          '/forgot-password' ||
          '/resend-verification' => AppStrings.t('auth.forgotDescription'),
          '/verify-email' =>
            missingToken
                ? AppStrings.t('auth.verifyMissing')
                : AppStrings.t('auth.verifyDescription'),
          '/reset-password' =>
            missingToken
                ? AppStrings.t('auth.resetMissing')
                : AppStrings.t('auth.resetDescription'),
          _ => AppStrings.t('auth.loginDescription'),
        },
        style: TextStyle(
          color:
              Theme.of(context).textTheme.bodyMedium?.color ??
              Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.6,
        ),
      ),
      const SizedBox(height: 22),
      Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (register) ...[
                _field(
                  _displayName,
                  AppStrings.t('auth.displayNameField'),
                  icon: Icons.person_outline,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty || v!.trim().length > 120
                      ? AppStrings.t('auth.displayNameInvalid')
                      : null,
                ),
                _field(
                  _username,
                  AppStrings.t('auth.usernameField'),
                  icon: Icons.alternate_email,
                  validator: (v) =>
                      RegExp(r'^[A-Za-z0-9_.-]{3,50}$').hasMatch(v ?? '')
                      ? null
                      : AppStrings.t('auth.usernameInvalid'),
                ),
              ],
              if (!reset && !verify)
                _field(
                  _email,
                  AppStrings.t('auth.emailField'),
                  icon: Icons.mail_outline,
                  email: true,
                  validator: (v) =>
                      RegExp(
                        r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                      ).hasMatch((v ?? '').trim())
                      ? null
                      : AppStrings.t('auth.emailInvalid'),
                ),
              if ((login || register || reset) && !missingToken) ...[
                _field(
                  _password,
                  reset
                      ? AppStrings.t('auth.newPasswordField')
                      : AppStrings.t('auth.passwordField'),
                  secret: true,
                  validator: login
                      ? (v) => (v ?? '').isEmpty
                            ? AppStrings.t('auth.passwordRequired')
                            : null
                      : validatePassword,
                ),
                if (!login) ...[
                  Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      AppStrings.t('auth.passwordRequirement'),
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  _field(
                    _confirm,
                    AppStrings.t('auth.confirmPasswordField'),
                    secret: true,
                    validator: (v) => v != _password.text
                        ? AppStrings.t('auth.passwordMismatch')
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
                    child: Text(AppStrings.t('auth.forgotLink')),
                  ),
                ),
              if (!missingToken)
                FilledButton(
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
                              ? AppStrings.t('auth.loginBtn')
                              : register
                              ? AppStrings.t('auth.createAccount')
                              : verify
                              ? AppStrings.t('auth.verifyTitle')
                              : reset
                              ? AppStrings.t('auth.saveNewPassword')
                              : AppStrings.t('auth.sendEmail'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              if (login) ...[
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(auth.loginWithGoogle),
                  child: Text(AppStrings.t('auth.continueGoogle')),
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
          child: Text(AppStrings.t('auth.noAccount')),
        ),
        if (_verificationSuggested)
          TextButton(
            onPressed: _busy ? null : () => _navigate('/resend-verification'),
            child: Text(AppStrings.t('auth.resendVerification')),
          ),
        if (auth.notice != null)
          TextButton(
            onPressed: _busy ? null : auth.restore,
            child: Text(AppStrings.t('auth.restoreAgain')),
          ),
      ] else ...[
        if (missingToken)
          TextButton(
            onPressed: () =>
                _navigate(reset ? '/forgot-password' : '/resend-verification'),
            child: Text(AppStrings.t('auth.requestNewLink')),
          ),
        TextButton(
          onPressed: _busy ? null : () => _navigate('/login'),
          child: Text(AppStrings.t('auth.backToLogin')),
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
                tooltip: _hidden
                    ? AppStrings.t('auth.showPassword')
                    : AppStrings.t('auth.hidePassword'),
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
          setState(() => _message = AppStrings.t('auth.otherDevicesLoggedOut'));
        }
      }),
      onLogoutAll: () => _run(() async {
        await auth.protected('POST', '/auth/logout-all');
        await auth.clearSession(AppStrings.t('auth.allDevicesLoggedOut'));
      }),
      onLogout: () => _run(auth.logout),
    ),
  ];
}
