import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../account/screens/profile_screen.dart';
import '../../plans_screen.dart';
import '../../auth.dart';
import '../../features/notifications/notification_center.dart';
import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import '../theme/theme_notifier.dart';
import 'app_logo.dart';
import 'google_logo_icon.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.auth,
    required this.notifications,
    this.links,
    this.initialPage,
    this.initialToken,
  });
  final AuthController auth;
  final NotificationCenter notifications;
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
  late String _page;
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
    final initialPage = widget.initialPage ?? '/login';
    _page = initialPage == '/account' && !auth.authenticated
        ? '/login'
        : initialPage;
    if (initialPage == '/account' && !auth.authenticated) {
      _message = AppStrings.t('auth.accountMessage');
    }
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
          _message = (error.message.isNotEmpty && error.message != error.code)
              ? error.message
              : AppStrings.apiError(error);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).height < 700;
    final canGoBack = _page != '/login' || Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (canGoBack)
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                      ),
                      tooltip: AppStrings.t('common.back'),
                      onPressed: () {
                        if (_page != '/login') {
                          _navigate('/login');
                        } else if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                    )
                  else
                    const SizedBox(width: 48, height: 48),
                  const HuTubeLogo(size: 26, showWordmark: true),
                  IconButton(
                    icon: Icon(
                      isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      size: 22,
                      color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                    ),
                    tooltip: isDark ? 'Chuyển sang giao diện sáng' : 'Chuyển sang giao diện tối',
                    onPressed: () {
                      ThemeNotifier.setTheme(isDark ? 'light' : 'dark');
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    compact ? 8 : 16,
                    16,
                    compact ? 16 : 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurface : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isDark ? AppColors.darkBorder : AppColors.borderSubtle,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: EdgeInsets.all(compact ? 20 : 28),
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageBanner(String message, ColorScheme scheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isError = _error || (auth.notice != null && _message == null);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isError
              ? (isDark ? const Color(0xFF33151D) : const Color(0xFFFFF0F2))
              : (isDark ? const Color(0xFF132B20) : AppColors.primaryLight),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isError
                ? (isDark ? const Color(0xFF5C202E) : const Color(0xFFFFCCD3))
                : (isDark ? const Color(0xFF1E4632) : AppColors.primary.withValues(alpha: 0.3)),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              size: 20,
              color: isError
                  ? (isDark ? const Color(0xFFFF6B81) : const Color(0xFFDC2626))
                  : (isDark ? const Color(0xFF34D399) : AppColors.primaryDark),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isError
                      ? (isDark ? const Color(0xFFFFD1D8) : const Color(0xFF991B1B))
                      : (isDark ? const Color(0xFFD1FAE5) : AppColors.primaryDark),
                  height: 1.4,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _authForm() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final register = _page == '/register';
    final login = _page == '/login';
    final reset = _page == '/reset-password';
    final verify = _page == '/verify-email';
    final missingToken =
        (reset || verify) && (_token == null || _token!.isEmpty);
    final title = switch (_page) {
      '/login' => AppStrings.t('auth.loginTitle'),
      '/register' => AppStrings.t('auth.createAccount'),
      '/forgot-password' => AppStrings.t('auth.forgotTitle'),
      '/reset-password' => AppStrings.t('auth.resetTitle'),
      '/verify-email' => AppStrings.t('auth.verifyTitle'),
      '/resend-verification' => AppStrings.t('auth.resendTitle'),
      _ => AppStrings.t('auth.welcome'),
    };
    final subtitle = switch (_page) {
      '/login' => AppStrings.t('auth.welcomeBack'),
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
    };

    return [
      Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Image.asset(
            'assets/logo-mark.png',
            width: 88,
            height: 88,
            fit: BoxFit.contain,
          ),
        ),
      ),
      Text(
        title,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
          letterSpacing: -0.5,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
          fontSize: 14,
          height: 1.45,
        ),
      ),
      const SizedBox(height: 24),
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
                  icon: Icons.person_outline_rounded,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty || v!.trim().length > 120
                      ? AppStrings.t('auth.displayNameInvalid')
                      : null,
                ),
                _field(
                  _username,
                  AppStrings.t('auth.usernameField'),
                  icon: Icons.alternate_email_rounded,
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
                  icon: Icons.mail_outline_rounded,
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
                  icon: Icons.lock_outline_rounded,
                  secret: true,
                  validator: login
                      ? (v) => (v ?? '').isEmpty
                            ? AppStrings.t('auth.passwordRequired')
                            : null
                      : validatePassword,
                ),
                if (!login) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      AppStrings.t('auth.passwordRequirement'),
                      style: TextStyle(
                        color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  _field(
                    _confirm,
                    AppStrings.t('auth.confirmPasswordField'),
                    icon: Icons.lock_outline_rounded,
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
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _navigate('/forgot-password'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        AppStrings.t('auth.forgotLink'),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              if (!missingToken)
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 1,
                  ),
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
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              if (login || register) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Divider(
                          color: isDark ? AppColors.darkBorder : AppColors.border,
                          thickness: 1,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          AppStrings.t('auth.or'),
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                          color: isDark ? AppColors.darkBorder : AppColors.border,
                          thickness: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(auth.loginWithGoogle),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: isDark
                        ? AppColors.darkBackgroundCard
                        : Colors.white,
                    foregroundColor: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                    side: BorderSide(
                      color: isDark ? AppColors.darkBorder : AppColors.border,
                      width: 1.2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const GoogleLogoIcon(size: 20),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          register
                              ? AppStrings.t('auth.googleRegister')
                              : AppStrings.t('auth.googleLogin'),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      if (login) ...[
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Center(
            child: InkWell(
              onTap: _busy ? null : () => _navigate('/register'),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 13.5,
                      fontFamily: 'Plus Jakarta Sans',
                      color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                    ),
                    children: [
                      TextSpan(text: AppStrings.t('auth.noAccountPrefix')),
                      TextSpan(
                        text: AppStrings.t('auth.registerNow'),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_verificationSuggested)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: TextButton(
                onPressed: _busy ? null : () => _navigate('/resend-verification'),
                child: Text(
                  AppStrings.t('auth.resendVerification'),
                  style: TextStyle(
                    color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        if (auth.notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: TextButton(
                onPressed: _busy ? null : auth.restore,
                child: Text(
                  AppStrings.t('auth.restoreAgain'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ),
      ] else ...[
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Center(
            child: InkWell(
              onTap: _busy ? null : () => _navigate('/login'),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 13.5,
                      fontFamily: 'Plus Jakarta Sans',
                      color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                    ),
                    children: [
                      TextSpan(
                        text: register
                            ? AppStrings.t('auth.hasAccountPrefix')
                            : '',
                      ),
                      TextSpan(
                        text: register
                            ? AppStrings.t('auth.loginNow')
                            : AppStrings.t('auth.backToLogin'),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (missingToken)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: TextButton(
                onPressed: () =>
                    _navigate(reset ? '/forgot-password' : '/resend-verification'),
                child: Text(AppStrings.t('auth.requestNewLink')),
              ),
            ),
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
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
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
        style: TextStyle(
          color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
          fontSize: 14.5,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
            fontSize: 14,
          ),
          errorMaxLines: 3,
          filled: true,
          fillColor: isDark
              ? AppColors.darkBackgroundCard
              : AppColors.surfaceAlt,
          prefixIcon: Icon(
            icon ?? (secret ? Icons.lock_outline_rounded : Icons.mail_outline_rounded),
            size: 20,
            color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
          ),
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
                    size: 20,
                    color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                  ),
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.border,
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: AppColors.primary,
              width: 1.5,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.error,
              width: 1,
            ),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.error,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _account() => [
    ProfileScreen(
      auth: auth,
      notifications: widget.notifications,
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
