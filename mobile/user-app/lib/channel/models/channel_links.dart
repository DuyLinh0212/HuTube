import 'dart:convert';

bool isPublicWebLink(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

List<Map<String, String>> channelLinks(
  String? settings, {
  bool validOnly = true,
}) {
  try {
    final decoded = jsonDecode(settings ?? '{}');
    final raw = decoded is Map ? decoded['links'] : decoded;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (link) => {
            'platform': '${link['platform'] ?? 'other'}',
            'title': '${link['title'] ?? link['label'] ?? ''}',
            'url': '${link['url'] ?? ''}',
          },
        )
        .where((link) => !validOnly || isPublicWebLink(link['url']!))
        .toList();
  } catch (_) {
    return const [];
  }
}
