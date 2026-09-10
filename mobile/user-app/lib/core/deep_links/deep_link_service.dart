class AuthLink {
  const AuthLink(this.path, this.token);
  final String path;
  final String? token;

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
