/// Canonical destinations for content links shared by the mobile app.
String? contentLinkTarget(Uri uri) {
  if (uri.scheme != 'hutube' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.fragment.isNotEmpty) {
    return null;
  }
  final parts = uri.pathSegments;
  if (parts.length > 1 ||
      parts.any(
        (p) =>
            p.isEmpty ||
            p == '.' ||
            p == '..' ||
            p.contains('/') ||
            p.contains('\\'),
      )) {
    return null;
  }
  final id = parts.firstOrNull;
  switch (uri.host) {
    case 'watch':
      return id == null ? null : '/watch/${Uri.encodeComponent(id)}';
    case 'channel':
    case 'channels':
      return id == null ? null : '/channels/${Uri.encodeComponent(id)}';
    case 'playlists':
      return id == null
          ? '/playlists'
          : '/playlists/${Uri.encodeComponent(id)}';
    case 'plans':
      if (id != null && uri.queryParameters['token']?.isNotEmpty == true) {
        return Uri(
          path: '/plans',
          queryParameters: {
            'invitationId': id,
            'invitationToken': uri.queryParameters['token']!,
          },
        ).toString();
      }
      return Uri(
        path: '/plans',
        queryParameters: id == null ? null : {'planId': id},
      ).toString();
    case 'search':
      return Uri(
        path: '/search',
        queryParameters: {
          for (final key in ['q', 'tag', 'categoryId'])
            if (uri.queryParameters[key]?.isNotEmpty == true)
              key: uri.queryParameters[key]!,
        },
      ).toString();
    case 'policies':
      final group = uri.queryParameters['group'] ?? uri.queryParameters['tab'];
      return Uri(
        path: '/policies',
        queryParameters: ['guidelines', 'privacy', 'terms'].contains(group)
            ? {'group': group!}
            : null,
      ).toString();
    case 'notifications':
      return '/notifications';
  }
  return null;
}
