class AppConfig {
  const AppConfig({
    this.apiBaseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      // Android Emulator reaches the host machine through 10.0.2.2.
      // Release/CI builds override this with --dart-define=API_BASE_URL=...
      defaultValue: 'http://10.0.2.2:5080/api/v1',
    ),
    this.googleWebClientId = const String.fromEnvironment(
      'GOOGLE_WEB_CLIENT_ID',
      defaultValue: '',
    ),
    this.googleIosClientId = const String.fromEnvironment(
      'GOOGLE_IOS_CLIENT_ID',
      defaultValue: '',
    ),
    this.clientHeader = 'mobile',
  });

  final String apiBaseUrl;
  final String googleWebClientId;
  final String googleIosClientId;
  final String clientHeader;

  static const AppConfig standard = AppConfig();
}
