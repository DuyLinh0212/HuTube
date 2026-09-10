class AppConfig {
  const AppConfig({
    this.apiBaseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://hutube.onrender.com/api/v1',
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
