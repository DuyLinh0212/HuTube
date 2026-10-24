import 'package:user_app/account/screens/profile_screen.dart';
import 'package:user_app/account/screens/edit_profile_screen.dart';
import 'package:user_app/account/screens/active_sessions_screen.dart';
import 'package:user_app/account/screens/login_history_screen.dart';
import 'package:user_app/account/services/account_service.dart';
import 'package:user_app/account/state/account_controller.dart';
import 'package:user_app/account/models/account_models.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/channel/models/channel_models.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/features/notifications/notification_center.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse, session;
import 'package:user_app/account/screens/change_password_screen.dart';
import 'package:user_app/account/screens/preferences_screen.dart';
import 'package:user_app/account/screens/notification_settings_screen.dart';
import 'package:user_app/channel/screens/create_channel_screen.dart';
import 'package:user_app/channel/screens/channel_settings_screen.dart';
import 'package:user_app/channel/screens/channel_screen.dart';
import 'package:user_app/channel/screens/channel_invitations_screen.dart';
import 'package:user_app/features/account/account_hub_screen.dart';
import 'package:user_app/features/account/account_settings_screen.dart';
import 'package:user_app/features/account/playback_settings_screen.dart';
import 'package:user_app/features/account/background_download_settings_screen.dart';
import 'package:user_app/features/content/home_screen.dart';
import 'package:user_app/features/content/explore_screen.dart';
import 'package:user_app/features/content/library_screen.dart';
import 'package:user_app/features/content/downloads_screen.dart';
import 'package:user_app/features/creator/creator_hub_screen.dart';
import 'package:user_app/features/creator/creator_content_screen.dart';
import 'package:user_app/features/creator/creator_comments_screen.dart';
import 'package:user_app/features/creator/creator_subtitles_screen.dart';
import 'package:user_app/features/creator/creator_analytics_screen.dart';
import 'package:user_app/features/creator/video_upload_screen.dart';
import 'package:user_app/features/moderation/moderation_screen.dart';
import 'package:user_app/features/notifications/notifications_screen.dart';
import 'package:user_app/features/playlists/playlists_screen.dart';
import 'package:user_app/features/policies/policies_screen.dart';
import 'package:user_app/features/search/search_screen.dart';
import 'package:user_app/features/subscriptions/subscriptions_screen.dart';
import 'package:user_app/plans_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final viewport in [
    const Size(320, 568),
    const Size(640, 360),
    const Size(800, 1024),
  ]) {
    for (final textScale in [1.0, 2.0]) {
      for (final populated in [false, true]) {
        testWidgets(
          'screen audit ${viewport.width}x${viewport.height} text $textScale populated $populated',
          (tester) async {
            FlutterSecureStorage.setMockInitialValues({});
            tester.view.physicalSize = viewport;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final auth = AuthController(
              ApiClient(
                client: MockClient((request) async {
                  if (request.url.path.endsWith('/auth/refresh')) {
                    return jsonResponse(session());
                  }
                  if (populated) {
                    final path = request.url.path;
                    final channel = {
                      'channelId': 'channel-1',
                      'name':
                          'Kênh thử nghiệm có tên rất dài để kiểm tra bố cục',
                      'handle': 'linh',
                      'isOwner': true,
                      'videoCount': 999,
                      'viewCount': 99999999,
                      'subscriberCount': 123456,
                    };
                    final video = {
                      'videoId': 'video-1',
                      'title':
                          'Tiêu đề video rất dài để kiểm tra bố cục và cỡ chữ lớn trên điện thoại',
                      'channelId': 'channel-1',
                      'channelName': channel['name'],
                      'channelHandle': 'linh',
                      'duration': 320,
                      'visibility': 'public',
                      'moderationStatus': 'approved',
                      'processingStatus': 'ready',
                      'publishedAt': '2026-10-01T00:00:00Z',
                      'stats': {
                        'views': 9999999,
                        'likes': 12345,
                        'comments': 678,
                        'ratingCount': 2,
                        'averageRating': 4.5,
                      },
                      'progressPercent': 75,
                    };
                    if (path.endsWith('/channels/accessible')) {
                      return http.Response(jsonEncode([channel]), 200);
                    }
                    if (path.endsWith('/channels/me') ||
                        path.endsWith('/channels/handle/linh') ||
                        path.endsWith('/channels/channel-1')) {
                      return jsonResponse(channel);
                    }
                    if (path.endsWith('/plans')) {
                      return http.Response(
                        jsonEncode([
                          {
                            'planId': 'plan-1',
                            'name': 'Premium dành cho gia đình',
                            'description':
                                'Xem video và tải xuống với chất lượng cao',
                            'price': 99000,
                            'storageLimit': 10737418240,
                            'maxMembers': 6,
                            'features': {
                              'download': true,
                              'pip': true,
                              'background_play': true,
                            },
                          },
                        ]),
                        200,
                      );
                    }
                    if (path.endsWith('/videos/manage') ||
                        path.contains('/feed/') ||
                        path.endsWith('/videos/search') ||
                        path.endsWith('/history') ||
                        path.endsWith('/liked') ||
                        path.endsWith('/channels/channel-1/videos')) {
                      return jsonResponse({
                        'items': [video],
                        'page': 1,
                        'pageSize': 20,
                        'total': 1,
                      });
                    }
                    if (path.endsWith('/comments/manage')) {
                      return jsonResponse({
                        'items': [
                          {
                            'commentId': 'comment-1',
                            'videoId': 'video-1',
                            'videoTitle': video['title'],
                            'displayName':
                                'Tên người bình luận rất dài cần xuống dòng',
                            'content': 'Nội dung bình luận thử nghiệm',
                            'status': 'visible',
                            'createdAt': '2026-10-01T00:00:00Z',
                            'likes': 123,
                          },
                        ],
                        'page': 1,
                        'pageSize': 20,
                        'total': 1,
                      });
                    }
                  }
                  return jsonResponse({
                    'items': [],
                    'page': 1,
                    'pageSize': 20,
                    'total': 0,
                  });
                }),
              ),
              MemoryStore('refresh'),
            );
            await auth.restore();
            final notifications = NotificationCenter(auth);
            final account = AccountController(AccountService(auth));

            final channel = ChannelDetail.fromJson({
              'channelId': 'channel-1',
              'name': 'Kênh thử nghiệm tên dài',
              'handle': 'linh',
              'isOwner': true,
            });
            final screens = <String, Widget Function()>{
              'account/screens/edit_profile_screen.dart': () =>
                  EditProfileScreen(
                    auth: auth,
                    profile: UserProfile.fromJson(
                      session()['user'] as Map<String, dynamic>,
                    ),
                  ),
              'account/screens/active_sessions_screen.dart': () =>
                  ActiveSessionsScreen(
                    controller: account,
                    onLogoutAll: () async {},
                    onLogout: () async {},
                  ),
              'account/screens/login_history_screen.dart': () =>
                  LoginHistoryScreen(service: AccountService(auth)),
              'account/screens/profile_screen.dart': () => ProfileScreen(
                auth: auth,
                notifications: notifications,
                sessions: const [],
                sessionsLoading: false,
                onRefreshSessions: () async {},
                onRevokeSession: (_) async {},
                onLogoutOthers: () async {},
                onLogoutAll: () async {},
                onLogout: () async {},
              ),
              'account/screens/change_password_screen.dart': () =>
                  ChangePasswordScreen(auth: auth),
              'account/screens/preferences_screen.dart': () =>
                  PreferencesScreen(auth: auth),
              'account/screens/notification_settings_screen.dart': () =>
                  NotificationSettingsScreen(
                    auth: auth,
                    notifications: notifications,
                  ),
              'channel/screens/create_channel_screen.dart': () =>
                  CreateChannelScreen(auth: auth),
              'channel/screens/channel_settings_screen.dart': () =>
                  ChannelSettingsScreen(auth: auth, channel: channel),
              'channel/screens/channel_screen.dart': () =>
                  ChannelScreen(auth: auth, channelOrHandle: 'linh'),
              'channel/screens/channel_invitations_screen.dart': () =>
                  ChannelInvitationsScreen(auth: auth),
              'features/account/account_hub_screen.dart': () =>
                  AccountHubScreen(auth: auth, notifications: notifications),
              'features/account/account_settings_screen.dart': () =>
                  AccountSettingsScreen(
                    auth: auth,
                    notifications: notifications,
                  ),
              'features/account/playback_settings_screen.dart': () =>
                  const PlaybackSettingsScreen(),
              'features/account/background_download_settings_screen.dart': () =>
                  const BackgroundDownloadSettingsScreen(),
              'features/content/home_screen.dart': () => HomeScreen(auth: auth),
              'features/content/explore_screen.dart': () =>
                  ExploreScreen(auth: auth),
              'features/content/library_screen.dart': () =>
                  LibraryScreen(auth: auth),
              'features/content/downloads_screen.dart': () =>
                  DownloadsScreen(auth: auth),
              'features/creator/creator_hub_screen.dart': () =>
                  CreatorHubScreen(auth: auth),
              'features/creator/creator_content_screen.dart': () =>
                  CreatorContentScreen(auth: auth, channel: channel),
              'features/creator/creator_comments_screen.dart': () =>
                  CreatorCommentsScreen(auth: auth, channel: channel),
              'features/creator/creator_subtitles_screen.dart': () =>
                  CreatorSubtitlesScreen(auth: auth, channel: channel),
              'features/creator/creator_analytics_screen.dart': () =>
                  CreatorAnalyticsScreen(auth: auth, channel: channel),
              'features/creator/video_upload_screen.dart': () =>
                  VideoUploadScreen(auth: auth, channel: channel),
              'features/moderation/moderation_screen.dart': () =>
                  ModerationScreen(auth: auth),
              'features/notifications/notifications_screen.dart': () =>
                  NotificationsScreen(auth: auth, notifications: notifications),
              'features/playlists/playlists_screen.dart': () =>
                  PlaylistsScreen(auth: auth),
              'features/policies/policies_screen.dart': () =>
                  PoliciesScreen(auth: auth),
              'features/search/search_screen.dart': () =>
                  SearchScreen(auth: auth),
              'features/subscriptions/subscriptions_screen.dart': () =>
                  SubscriptionsScreen(auth: auth),
              'plans_screen.dart': () => PlansScreen(auth: auth),
            };
            final failures = <String>[];
            final originalHandler = FlutterError.onError;
            for (final entry in screens.entries) {
              FlutterError.onError = (details) {
                failures.add('${entry.key}: ${details.toString()}');
              };
              await tester.pumpWidget(
                MaterialApp(
                  theme: populated ? AppTheme.darkTheme : AppTheme.lightTheme,
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: viewport,
                      textScaler: TextScaler.linear(textScale),
                    ),
                    child: Scaffold(body: entry.value()),
                  ),
                ),
              );
              await tester.pump(const Duration(seconds: 1));
              await tester.pump(const Duration(seconds: 1));
              Object? error;
              while ((error = tester.takeException()) != null) {
                failures.add('${entry.key}: $error');
              }
              final scrollables = find.byType(Scrollable);
              if (scrollables.evaluate().isNotEmpty) {
                for (var step = 0; step < 6; step++) {
                  await tester.drag(
                    scrollables.first,
                    Offset(0, -viewport.height * .65),
                  );
                  await tester.pump(const Duration(milliseconds: 300));
                  while ((error = tester.takeException()) != null) {
                    failures.add('${entry.key} scrolled: $error');
                  }
                }
              }
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
            }
            FlutterError.onError = originalHandler;
            account.dispose();
            notifications.dispose();
            auth.dispose();
            expect(failures, isEmpty, reason: failures.join('\n'));
          },
        );
      }
    }
  }
}
