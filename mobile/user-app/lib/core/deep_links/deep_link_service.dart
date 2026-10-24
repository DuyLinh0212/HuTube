class AuthLink {
  const AuthLink(this.path, this.token);
  final String path;
  final String? token;

  /// Accept only the app link or the configured web origin from a verification
  /// email. The token is sent to this app's API, never to the pasted URL.
  static AuthLink? parseVerificationInput(
    String input, {
    String webBaseUrl = const String.fromEnvironment(
      'AUTH_WEB_BASE_URL',
      defaultValue: 'http://localhost:4200',
    ),
  }) {
    final value = input.trim();
    if (value.isEmpty || value.length > 8192) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.path != '/verify-email') {
      return null;
    }
    final appLink = parse(uri);
    final web = Uri.tryParse(webBaseUrl);
    final sameOrigin =
        web != null &&
        const ['http', 'https'].contains(uri.scheme) &&
        uri.scheme == web.scheme &&
        uri.host == web.host &&
        uri.port == web.port;
    if (appLink == null && !sameOrigin) return null;
    final tokens = uri.queryParametersAll['token'];
    if (tokens == null || tokens.length != 1 || tokens.single.trim().isEmpty) {
      return null;
    }
    return AuthLink('/verify-email', tokens.single);
  }

  static AuthLink? parse(Uri uri) {
    if (uri.scheme != 'hutube' ||
        uri.host != 'auth' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort) {
      return null;
    }
    if (!{
      '/login',
      '/account',
      '/verify-email',
      '/reset-password',
    }.contains(uri.path)) {
      return null;
    }
    return AuthLink(uri.path, uri.queryParameters['token']);
  }
}
