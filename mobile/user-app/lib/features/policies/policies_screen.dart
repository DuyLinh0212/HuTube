import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'policy_document.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';

class PoliciesScreen extends StatefulWidget {
  const PoliciesScreen({super.key, required this.auth, this.initialGroup});
  final AuthController auth;
  final String? initialGroup;
  @override
  State<PoliciesScreen> createState() => _PoliciesScreenState();
}

class _PoliciesScreenState extends State<PoliciesScreen> {
  List<Map<String, dynamic>> _policies = [];
  bool _loading = true;
  String _group = 'guidelines';
  bool _exporting = false;

  List<Map<String, dynamic>> get _current => _policies.where((item) {
    final group = '${item['group'] ?? ''}'.toLowerCase();
    return group == _group || (_group == 'guidelines' && group == 'content');
  }).toList();

  Future<void> _export(bool print) async {
    if (_exporting) return;
    final title = 'Dalitu — ${AppStrings.t('policies.$_group')}';
    final body = policyDocumentText(
      _current,
      fallback:
          '${AppStrings.t('policies.fallbackTitle')}\n${AppStrings.t('policies.fallbackText')}',
    );
    setState(() => _exporting = true);
    try {
      final path = await exportPolicyDocument(title, body, print: print);
      if (!print && mounted) {
        await Share.shareXFiles([XFile(path)], subject: title);
      }
    } on UnsupportedError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.t('parity.exportUnavailable'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.t('parity.exportError'))),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _group = widget.initialGroup ?? _group;
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.auth.api.requestList('GET', '/policies');
      if (mounted) {
        setState(() {
          _policies = list
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
      children: [
        Text(
          AppStrings.t('policies.title'),
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          AppStrings.t('policies.description'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _loading || _exporting ? null : () => _export(false),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(AppStrings.t('parity.pdf')),
            ),
            TextButton.icon(
              onPressed: _loading || _exporting ? null : () => _export(true),
              icon: const Icon(Icons.print_outlined),
              label: Text(AppStrings.t('parity.print')),
            ),
          ],
        ),
        if (_exporting) const LinearProgressIndicator(),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final item in [
                ('guidelines', AppStrings.t('policies.guidelines')),
                ('privacy', AppStrings.t('policies.privacy')),
                ('terms', AppStrings.t('policies.terms')),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(item.$2),
                    selected: _group == item.$1,
                    onSelected: (_) => setState(() => _group = item.$1),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primaryPink),
            ),
          )
        else if (current.isEmpty)
          const _PolicyFallback()
        else
          ...current.map((policy) => _PolicyCard(policy: policy)),
      ],
    );
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.policy});
  final Map<String, dynamic> policy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveAt = DateTime.tryParse('${policy['effectiveAt'] ?? ''}');
    final version = '${policy['version'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${policy['name'] ?? policy['title'] ?? AppStrings.t('policies.title')}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${policy['description'] ?? policy['content'] ?? ''}',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              ),
              if (effectiveAt != null || version.isNotEmpty) ...[
                const SizedBox(height: 14),
                Divider(height: 1, color: colors.outlineVariant),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (effectiveAt != null)
                      Text(
                        AppStrings.format('policies.effectiveDate', {
                          'date': AppStrings.date(effectiveAt.toLocal()),
                        }),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    if (version.isNotEmpty)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            AppStrings.format('policies.version', {
                              'version': version,
                            }),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PolicyFallback extends StatelessWidget {
  const _PolicyFallback();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.t('policies.fallbackTitle'),
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 8),
          Text(AppStrings.t('policies.fallbackText')),
        ],
      ),
    ),
  );
}
