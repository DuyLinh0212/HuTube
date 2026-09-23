import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:signalr_netcore/signalr_client.dart';

import '../../auth.dart';

class NotificationCenter extends ChangeNotifier with WidgetsBindingObserver {
  NotificationCenter(this.auth);

  final AuthController auth;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, dynamic>> _newNotifications =
      StreamController<Map<String, dynamic>>.broadcast();
  HubConnection? _hub;
  void Function(Map<String, dynamic>)? _openNotification;
  String? _activeUserId;
  Timer? _hubRetryTimer;
  int _unreadCount = 0;
  bool _localReady = false;
  bool _localAlertsEnabled = false;
  bool _foreground = true;
  bool _disposed = false;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  int get unreadCount => _unreadCount;
  bool get localAlertsEnabled => _localAlertsEnabled;
  Stream<Map<String, dynamic>> get newNotifications => _newNotifications.stream;

  Future<void> initialize({
    required void Function(Map<String, dynamic>) onOpenNotification,
  }) async {
    _openNotification = onOpenNotification;
    auth.beforeSessionCleared = _beforeSessionCleared;
    auth.addListener(_authChanged);
    WidgetsBinding.instance.addObserver(this);
    await _initializeLocalNotifications();
    await refreshLocalPermission();
    await _syncAuthSession();
    if (_localReady) {
      try {
        final launch = await _local.getNotificationAppLaunchDetails();
        final payload = launch?.notificationResponse?.payload;
        if (launch?.didNotificationLaunchApp == true && payload != null) {
          _handleLocalPayload(payload);
        }
      } catch (_) {}
    }
  }

  Future<void> _initializeLocalNotifications() async {
    if (!_isAndroid && !_isIOS) return;
    try {
      _localReady =
          await _local.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              iOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
                defaultPresentAlert: false,
                defaultPresentBadge: false,
                defaultPresentSound: false,
              ),
            ),
            onDidReceiveNotificationResponse: (response) {
              final payload = response.payload;
              if (payload != null) _handleLocalPayload(payload);
            },
          ) ??
          false;
      if (_localReady && _isAndroid) {
        await _local
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(
              const AndroidNotificationChannel(
                'hutube_notifications',
                'Thông báo HuTube',
                description: 'Thông báo về kênh, video và tài khoản HuTube.',
                importance: Importance.high,
              ),
            );
      }
    } catch (_) {
      _localReady = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      unawaited(refreshLocalPermission());
      if (auth.authenticated) {
        unawaited(_connectHub());
        unawaited(refreshUnreadCount());
      }
    } else if (state == AppLifecycleState.paused) {
      _foreground = false;
      unawaited(_disconnectHub());
    }
  }

  void _authChanged() => unawaited(_syncAuthSession());

  Future<void> _syncAuthSession() async {
    if (_disposed) return;
    if (!auth.authenticated) {
      if (_activeUserId != null) {
        _activeUserId = null;
        setUnreadCount(0);
        await _disconnectHub();
      }
      return;
    }

    final identity =
        '${auth.user?['userId'] ?? auth.user?['id'] ?? 'signed-in'}';
    if (_activeUserId == identity) return;
    if (_activeUserId != null) await _disconnectHub();
    _activeUserId = identity;
    setUnreadCount(0);
    await _connectHub();
    await refreshUnreadCount();
  }

  Future<void> _connectHub() async {
    if (_disposed || !_foreground || !auth.authenticated || _hub != null)
      return;
    final hubUrl =
        '${auth.api.baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '')}/hubs/notifications';
    final connection = HubConnectionBuilder()
        .withUrl(
          hubUrl,
          options: HttpConnectionOptions(
            accessTokenFactory: () async => auth.accessToken ?? '',
          ),
        )
        .withAutomaticReconnect()
        .build();
    connection.on('NotificationReceived', (arguments) {
      if (arguments == null || arguments.isEmpty || arguments.first is! Map) {
        return;
      }
      final item = Map<String, dynamic>.from(arguments.first as Map);
      _newNotifications.add(item);
      if (_localAlertsEnabled) unawaited(_showLocalNotification(item));
    });
    connection.on('UnreadCountChanged', (arguments) {
      if (arguments == null || arguments.isEmpty) return;
      final value = arguments.first;
      if (value is num) setUnreadCount(value.toInt());
      if (value is String) setUnreadCount(int.tryParse(value) ?? 0);
    });
    connection.onreconnected(({String? connectionId}) {
      unawaited(refreshUnreadCount());
    });
    connection.onclose(({Exception? error}) {
      if (identical(_hub, connection)) {
        _hub = null;
        _scheduleHubRetry();
      }
    });
    _hub = connection;
    try {
      await connection.start();
      _hubRetryTimer?.cancel();
      _hubRetryTimer = null;
    } catch (_) {
      await _disconnectHub();
      _scheduleHubRetry();
    }
  }

  void _scheduleHubRetry() {
    if (_disposed ||
        !_foreground ||
        !auth.authenticated ||
        _hubRetryTimer != null) {
      return;
    }
    _hubRetryTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_foreground || !auth.authenticated || _disposed) {
        _hubRetryTimer?.cancel();
        _hubRetryTimer = null;
      } else if (_hub == null) {
        unawaited(_connectHub());
      }
    });
  }

  Future<void> _disconnectHub() async {
    _hubRetryTimer?.cancel();
    _hubRetryTimer = null;
    final connection = _hub;
    _hub = null;
    if (connection != null) {
      try {
        await connection.stop();
      } catch (_) {}
    }
  }

  Future<void> refreshUnreadCount() async {
    if (!auth.authenticated) return;
    try {
      final result = await auth.protected(
        'GET',
        '/notifications?page=1&pageSize=1',
      );
      final count = result['unreadCount'];
      if (count is num) setUnreadCount(count.toInt());
    } catch (_) {}
  }

  Future<void> refreshLocalPermission() async {
    if (!_localReady) return;
    try {
      if (_isAndroid) {
        _localAlertsEnabled =
            await _local
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.areNotificationsEnabled() ??
            false;
      } else if (_isIOS) {
        _localAlertsEnabled =
            await _local
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.checkPermissions()
                .then((value) => value?.isEnabled) ??
            false;
      }
    } catch (_) {
      _localAlertsEnabled = false;
    }
    _notify();
  }

  Future<bool> requestLocalNotificationsPermission() async {
    if (!_localReady) return false;
    try {
      if (_isAndroid) {
        _localAlertsEnabled =
            await _local
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            false;
      } else if (_isIOS) {
        _localAlertsEnabled =
            await _local
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
    } catch (_) {
      _localAlertsEnabled = false;
    }
    _notify();
    return _localAlertsEnabled;
  }

  void setUnreadCount(int value) {
    final count = value < 0 ? 0 : value;
    if (count == _unreadCount || _disposed) return;
    _unreadCount = count;
    _notify();
  }

  Future<bool> markRead(String id) async {
    if (id.isEmpty || !auth.authenticated) return false;
    try {
      await auth.protected('PATCH', '/notifications/$id/read', body: const {});
      await refreshUnreadCount();
      return true;
    } catch (_) {}
    return false;
  }

  Future<void> markAllRead() async {
    if (!auth.authenticated) return;
    await auth.protected('POST', '/notifications/read-all', body: const {});
    setUnreadCount(0);
  }

  void openNotification(Map<String, dynamic> item) {
    final id = '${item['notificationId'] ?? ''}';
    if (id.isNotEmpty && item['isRead'] != true) unawaited(markRead(id));
    _openNotification?.call(item);
  }

  Future<void> _showLocalNotification(Map<String, dynamic> item) async {
    final title = '${item['title'] ?? 'HuTube'}'.trim();
    final body = '${item['content'] ?? item['body'] ?? ''}'.trim();
    if (body.isEmpty) return;
    final id = '${item['notificationId'] ?? ''}';
    final notificationId = id.isEmpty
        ? DateTime.now().millisecondsSinceEpoch & 0x7fffffff
        : id.hashCode & 0x7fffffff;
    try {
      await _local.show(
        id: notificationId,
        title: title.isEmpty ? 'HuTube' : title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'hutube_notifications',
            'Thông báo HuTube',
            channelDescription: 'Thông báo về kênh, video và tài khoản HuTube.',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(item),
      );
    } catch (_) {}
  }

  void _handleLocalPayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) openNotification(Map<String, dynamic>.from(decoded));
    } catch (_) {}
  }

  Future<void> _beforeSessionCleared() => _disconnectHub();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _hubRetryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    auth.removeListener(_authChanged);
    auth.beforeSessionCleared = null;
    unawaited(_disconnectHub());
    unawaited(_newNotifications.close());
    super.dispose();
  }
}
