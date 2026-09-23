import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth.dart';
import '../core/localization/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_notifier.dart';
import '../core/widgets/app_shell.dart';
import '../features/account/account_hub_screen.dart';
import '../features/ai/hu_ai_screen.dart';
import '../features/content/feed_screen.dart';
import '../features/content/downloads_screen.dart';
import '../features/content/library_screen.dart';
import '../features/content/playback_session.dart';
import '../features/content/watch_screen.dart';
import '../features/moderation/moderation_screen.dart';
import '../channel/screens/channel_invitations_screen.dart';
import '../channel/screens/channel_screen.dart';
import '../features/creator/creator_hub_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/notifications/notification_center.dart';
import '../features/playlists/playlists_screen.dart';
import '../features/policies/policies_screen.dart';
import '../features/plans/mobile_plans_screen.dart';
import '../features/search/search_screen.dart';
import '../features/subscriptions/subscriptions_screen.dart';
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
  final PlaybackSession _playback = PlaybackSession();
  late final NotificationCenter _notifications;
  StreamSubscription<Uri>? _linkSubscription;
  String? _pendingNotificationPath;

  @override
  void initState() {
    super.initState();
    _notifications = NotificationCenter(widget.auth);
    _router = _buildRouter(widget.auth, _playback, _notifications);
    unawaited(_notifications.initialize(onOpenNotification: _openNotification));
    _linkSubscription = widget.links?.listen(_openDeepLink);
    unawaited(widget.auth.restore());
  }

  GoRouter _buildRouter(
    AuthController auth,
    PlaybackSession playback,
    NotificationCenter notifications,
  ) => GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) {
      final path = state.uri.path;
      if (auth.restoring) return path == '/splash' ? null : '/splash';
      // Preserve the existing first-run authentication flow. Public pages can
      // still be opened through a deep link, but a cold start does not issue
      // unauthenticated feed requests before the user has chosen a session.
      if (path == '/splash') {
        if (auth.authenticated && _pendingNotificationPath != null) {
          final target = _pendingNotificationPath!;
          _pendingNotificationPath = null;
          return target;
        }
        return auth.authenticated ? '/home' : '/auth';
      }
      // Keep legacy account deep links on the auth shell long enough for its
      // session-management view to complete. Ordinary successful sign-in
      // still enters the new mobile home route.
      if (auth.authenticated && path == '/auth') {
        if (_pendingNotificationPath != null) {
          final target = _pendingNotificationPath!;
          _pendingNotificationPath = null;
          return target;
        }
        return state.uri.queryParameters['step'] == '/account' ? null : '/home';
      }
      const protected = <String>{
        '/library',
        '/account',
        '/notifications',
        '/creator',
        '/downloads',
        '/subscriptions',
        '/moderation',
        '/channel-invitations',
      };
      final needsAuth =
          path == '/playlists' ||
          protected.any((item) => path == item || path.startsWith('$item/'));
      return !auth.authenticated && needsAuth ? '/auth' : null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _SplashScreen()),
      GoRoute(
        path: '/auth',
        builder: (_, state) => AppShell(
          auth: auth,
          notifications: notifications,
          initialPage: state.uri.queryParameters['step'],
          initialToken: state.uri.queryParameters['token'],
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => MobileScaffold(
          auth: auth,
          playback: playback,
          notifications: notifications,
          location: state.uri.path,
          child: child,
        ),
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
            path: '/subscriptions',
            builder: (_, _) => SubscriptionsScreen(auth: auth),
          ),
          GoRoute(
            path: '/huai',
            builder: (_, _) => HuAiScreen(auth: auth),
          ),
          GoRoute(
            path: '/search',
            builder: (_, _) => SearchScreen(auth: auth),
          ),
          GoRoute(
            path: '/playlists',
            builder: (_, _) => PlaylistsScreen(auth: auth),
          ),
          GoRoute(
            path: '/playlists/:playlistId',
            builder: (_, state) => PlaylistsScreen(
              auth: auth,
              playlistId: state.pathParameters['playlistId'],
            ),
          ),
          GoRoute(
            path: '/channels/:handle',
            builder: (_, state) => ChannelScreen(
              auth: auth,
              channelOrHandle: state.pathParameters['handle']!,
            ),
          ),
          GoRoute(
            path: '/moderation',
            builder: (_, _) => ModerationScreen(auth: auth),
          ),
          GoRoute(
            path: '/channel-invitations',
            builder: (_, _) => ChannelInvitationsScreen(auth: auth),
          ),
          GoRoute(
            path: '/watch/:videoId',
            builder: (_, state) => WatchScreen(
              auth: auth,
              playback: playback,
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
            builder: (_, _) =>
                AccountHubScreen(auth: auth, notifications: notifications),
          ),
          GoRoute(
            path: '/creator',
            builder: (_, _) => CreatorHubScreen(auth: auth),
          ),
          GoRoute(
            path: '/notifications',
            builder: (_, _) =>
                NotificationsScreen(auth: auth, notifications: notifications),
          ),
          GoRoute(
            path: '/plans',
            builder: (_, state) => MobilePlansScreen(
              auth: auth,
              invitationId: state.uri.queryParameters['invitationId'],
              invitationToken: state.uri.queryParameters['invitationToken'],
            ),
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

  void _openNotification(Map<String, dynamic> data) {
    final target =
        _safeNotificationTarget(data['actionUrl'] as String?) ??
        _fallbackNotificationTarget(data);
    const protected = [
      '/account',
      '/creator',
      '/downloads',
      '/library',
      '/moderation',
      '/notifications',
      '/playlists',
      '/subscriptions',
      '/channel-invitations',
    ];
    if (!widget.auth.authenticated &&
        protected.any(
          (path) => target == path || target.startsWith('$path/'),
        )) {
      _pendingNotificationPath = target;
      _router.go('/auth');
      return;
    }
    _router.go(target);
  }

  String? _safeNotificationTarget(String? actionUrl) {
    if (actionUrl == null ||
        !actionUrl.startsWith('/') ||
        actionUrl.startsWith('//')) {
      return null;
    }
    final uri = Uri.tryParse(actionUrl);
    if (uri == null || uri.hasAuthority || uri.pathSegments.contains('..')) {
      return null;
    }
    const supported = {
      '/home',
      '/explore',
      '/subscriptions',
      '/huai',
      '/search',
      '/playlists',
      '/moderation',
      '/channel-invitations',
      '/account',
      '/creator',
      '/downloads',
      '/library',
      '/notifications',
      '/plans',
      '/policies',
    };
    final pathSegments = uri.pathSegments;
    final isSupportedDynamicRoute =
        pathSegments.length == 2 &&
        const {'watch', 'channels', 'playlists'}.contains(pathSegments.first);
    if (!supported.contains(uri.path) && !isSupportedDynamicRoute) {
      return null;
    }
    return uri.toString();
  }

  String _fallbackNotificationTarget(Map<String, dynamic> data) {
    final resourceType = '${data['resourceType'] ?? ''}';
    final resourceId = '${data['resourceId'] ?? ''}';
    if (resourceType == 'video' && resourceId.isNotEmpty) {
      return '/watch/${Uri.encodeComponent(resourceId)}';
    }
    return '/notifications';
  }

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
      ('plans', final memberId?) when uri.queryParameters['token'] != null =>
        '/plans?invitationId=${Uri.encodeQueryComponent(memberId)}&invitationToken=${Uri.encodeQueryComponent(uri.queryParameters['token']!)}',
      ('plans', _) => '/plans',
      ('notifications', _) => '/notifications',
      ('huai', _) => '/huai',
      ('search', _) => '/search',
      ('playlists', _) => '/playlists',
      ('policies', _) => '/policies',
      _ => null,
    };
    if (target != null) _router.go(target);
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _router.dispose();
    _playback.dispose();
    _notifications.dispose();
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
