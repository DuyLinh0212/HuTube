import 'package:signalr_netcore/signalr_client.dart';

import '../../auth.dart';

class NotificationHubClient {
  NotificationHubClient(this.auth);
  final AuthController auth;
  HubConnection? _connection;

  String get _hubUrl =>
      '${auth.api.baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '')}/hubs/notifications';

  Future<void> connect({
    required void Function(Map<String, dynamic>) onNotification,
  }) async {
    if (!auth.authenticated || _connection != null) return;
    final connection = HubConnectionBuilder()
        .withUrl(
          _hubUrl,
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
      onNotification(Map<String, dynamic>.from(arguments.first as Map));
    });
    _connection = connection;
    try {
      await connection.start();
    } catch (_) {
      // The notification list remains functional via REST if the foreground
      // connection cannot be negotiated (for example while offline).
      await disconnect();
    }
  }

  Future<void> disconnect() async {
    final connection = _connection;
    _connection = null;
    if (connection != null) await connection.stop();
  }
}
