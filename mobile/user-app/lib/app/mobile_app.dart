import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth.dart';
import '../core/localization/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_notifier.dart';
import '../core/widgets/app_shell.dart';
import '../features/account/account_hub_screen.dart';
import '../features/content/feed_screen.dart';
import '../features/content/downloads_screen.dart';
import '../features/content/library_screen.dart';
import '../features/content/watch_screen.dart';
import '../features/creator/creator_hub_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/policies/policies_screen.dart';
import '../features/plans/mobile_plans_screen.dart';
import 'mobile_scaffold.dart';

class HuTubeApp extends StatefulWidget {
  const HuTubeApp({super.key, required this.auth, this.links});

  final AuthController auth;
  final Stream<Uri>? links;

  @override
  State<HuTubeApp> createState() => _HuTubeAppState();
}

class _HuTubeAppState extends State<HuTubeApp> {
  late final GoRouter _router;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _router = _buildRouter(widget.auth);
    _linkSubscription = widget.links?.listen(_openDeepLink);
    unawaited(widget.auth.restore());
  }

  GoRouter _buildRouter(AuthController auth) => GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) {
      final path = state.uri.path;
      if (auth.restoring) return path == '/splash' ? null : '/splash';
      // Preserve the existing first-run authentication flow. Public pages can
      // still be opened through a deep link, but a cold start does not issue
      // unauthenticated feed requests before the user has chosen a session.
      if (path == '/splash') return auth.authenticated ? '/home' : '/auth';
      // Keep legacy account deep links on the auth shell long enough for its
      // session-management view to complete. Ordinary successful sign-in
      // still enters the new mobile home route.
      if (auth.authenticated && path == '/auth') {
        return state.uri.queryParameters['step'] == '/account' ? null : '/home';
      }
      const protected = <String>{
        '/library',
        '/account',
        '/notifications',
        '/creator',
        '/downloads',
      };
      final needsAuth = protected.any(
        (item) => path == item || path.startsWith('$item/'),
      );
      return !auth.authenticated && needsAuth ? '/auth' : null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _SplashScreen()),
      GoRoute(
        path: '/auth',
        builder: (_, state) => AppShell(
          auth: auth,
          initialPage: state.uri.queryParameters['step'],
          initialToken: state.uri.queryParameters['token'],
        ),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            MobileScaffold(auth: auth, location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => FeedScreen(auth: auth),
          ),
          GoRoute(
            path: '/explore',
            builder: (_, _) => FeedScreen(auth: auth, explore: true),
          ),
          GoRoute(
            path: '/watch/:videoId',
            builder: (_, state) => WatchScreen(
              auth: auth,
              videoId: state.pathParameters['videoId']!,
            ),
          ),
          GoRoute(
            path: '/library',
            builder: (_, _) => LibraryScreen(auth: auth),
          ),
          GoRoute(
            path: '/downloads',
            builder: (_, _) => DownloadsScreen(auth: auth),
          ),
          GoRoute(
            path: '/account',
            builder: (_, _) => AccountHubScreen(auth: auth),
          ),
          GoRoute(
            path: '/creator',
            builder: (_, _) => CreatorHubScreen(auth: auth),
          ),
          GoRoute(
            path: '/notifications',
            builder: (_, _) => NotificationsScreen(auth: auth),
          ),
          GoRoute(
            path: '/plans',
            builder: (_, _) => MobilePlansScreen(auth: auth),
          ),
          GoRoute(
            path: '/policies',
            builder: (_, state) => PoliciesScreen(
              auth: auth,
              initialGroup: state.uri.queryParameters['group'],
            ),
          ),
        ],
      ),
    ],
  );

  void _openDeepLink(Uri uri) {
    final authLink = AuthLink.parse(uri);
    if (authLink != null) {
      _router.go(
        '/auth?step=${Uri.encodeQueryComponent(authLink.path)}'
        '${authLink.token == null ? '' : '&token=${Uri.encodeQueryComponent(authLink.token!)}'}',
      );
      return;
    }
    if (uri.scheme != 'hutube' || uri.userInfo.isNotEmpty || uri.hasPort) {
      return;
    }
    final segment = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    final target = switch ((uri.host, segment)) {
      ('watch', final id?) => '/watch/${Uri.encodeComponent(id)}',
      ('plans', _) => '/plans',
      ('notifications', _) => '/notifications',
      ('policies', _) => '/policies',
      _ => null,
    };
    if (target != null) _router.go(target);
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: ThemeNotifier.themeMode,
    builder: (context, themeMode, _) => ValueListenableBuilder<String>(
      valueListenable: AppStrings.currentLang,
      builder: (context, _, _) => MaterialApp.router(
        title: 'HuTube',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        routerConfig: _router,
      ),
    ),
  );
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.play_circle_fill_rounded,
            size: 56,
            color: AppColors.primaryPink,
          ),
          SizedBox(height: 16),
          Text(AppStrings.t('app.opening')),
          const SizedBox(height: 16),
          const CircularProgressIndicator(color: AppColors.primaryPink),
        ],
      ),
    ),
  );
}
