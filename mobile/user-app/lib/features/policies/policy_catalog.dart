import '../../core/localization/app_strings.dart';
import '../../core/widgets/content_filters.dart';
import 'policy_reference.dart';

const policyGroups = ['guidelines', 'privacy', 'terms', 'enforcement'];
String policyLabel(String key) =>
    '${policyTranslations[AppStrings.currentLang.value]?[key] ?? AppStrings.t(key)}';

/// Mirrors user-web: published rules win; missing reference codes remain visible.
List<Map<String, dynamic>> policyCatalog(List<Map<String, dynamic>> published) {
  const retired = {
    'PARTNER_ELIGIBILITY',
    'AD_SUITABILITY_GUIDE',
    'REVENUE_PAYOUTS',
  };
  final active = published
      .where(
        (p) =>
            '${p['group']}'.toLowerCase() != 'monetization' &&
            !retired.contains('${p['code']}'.toUpperCase()),
      )
      .toList();
  String groupFor(Map<String, dynamic> p) {
    final group = '${p['group']}';
    if (policyGroups.contains(group)) return group;
    for (final g in policyGroups.skip(1)) {
      if ((policyReference[g] as List).any((r) => r['code'] == p['code'])) {
        return g;
      }
    }
    return group == 'legal' ? 'terms' : 'guidelines';
  }

  return [
    for (final group in policyGroups) ...[
      for (final p in active.where((p) => groupFor(p) == group))
        {
          ...p,
          'group': group,
          'content': p['content'] ?? p['description'] ?? '',
          'published': true,
        },
      for (final r in policyReference[group] as List)
        if (!active.any((p) => p['code'] == r['code']))
          {
            ...Map<String, dynamic>.from(r),
            'group': group,
            'name': policyLabel('policy.${r['code']}.name'),
            'content': policyLabel('policy.${r['code']}.content'),
            'rules': AppStrings.currentLang.value == 'en'
                ? r['rulesEn'] ?? r['rules']
                : r['rules'],
            'exceptions': AppStrings.currentLang.value == 'en'
                ? r['exceptionsEn'] ?? r['exceptions']
                : r['exceptions'],
          },
    ],
  ];
}

String policySearchText(Map<String, dynamic> p) => normalizeContentText(
  [
    p['code'],
    p['name'],
    p['content'],
    ...(p['rules'] as List? ?? []),
    ...(p['exceptions'] as List? ?? []),
  ].join(' '),
);
