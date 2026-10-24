class AppConfig {
  const AppConfig({
    String recommendationBaseUrl = const String.fromEnvironment(
      'RECOMMENDATION_BASE_URL',
    ),
    this.apiBaseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      // Local APK builds use the deployed API unless explicitly overridden.
      // USB/emulator development supplies API_BASE_URL through --dart-define.
      defaultValue: 'https://api.dalitu.app/api/v1',
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
    if (api.host == 'hutube.onrender.com') {
      return 'https://hutube-recommendation-services.onrender.com/api/v1';
    }
    return 'https://recommendation.dalitu.app/api/v1';
  }

  final String googleWebClientId;
  final String googleIosClientId;
  final String clientHeader;

  static const AppConfig standard = AppConfig();
}
