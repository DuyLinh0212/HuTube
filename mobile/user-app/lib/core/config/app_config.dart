class AppConfig {
  const AppConfig({
    String recommendationBaseUrl = const String.fromEnvironment(
      'RECOMMENDATION_BASE_URL',
    ),
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
  }) : _recommendationBaseUrl = recommendationBaseUrl;

  final String apiBaseUrl;
  final String _recommendationBaseUrl;
  String get recommendationBaseUrl {
    if (_recommendationBaseUrl.isNotEmpty) return _recommendationBaseUrl;
    final api = Uri.parse(apiBaseUrl);
    if (['localhost', '127.0.0.1', '10.0.2.2', '::1'].contains(api.host)) {
      return api
          .replace(port: 8000, path: '/api/v1', query: null, fragment: null)
          .toString();
    }
    return 'https://hutube-recommendation-services.onrender.com/api/v1';
  }

  final String googleWebClientId;
  final String googleIosClientId;
  final String clientHeader;

  static const AppConfig standard = AppConfig();
}
