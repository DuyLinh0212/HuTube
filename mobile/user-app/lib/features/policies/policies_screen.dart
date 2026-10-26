import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/content_filters.dart';
import 'policy_catalog.dart';
import 'policy_document.dart';

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
  bool _loadError = false;
  bool _exporting = false;
  String _group = 'all';
  String _query = '';
  final _search = TextEditingController();
  int _request = 0;
  @override
  void initState() {
    super.initState();
    if (policyGroups.contains(widget.initialGroup)) {
      _group = widget.initialGroup!;
    }
    _load();
  }

  @override
  void dispose() {
    _request++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    ApiClient.invalidateReadCache();
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final list = await widget.auth.api.requestList('GET', '/policies');
      if (!mounted || request != _request) return;
      setState(() {
        _policies = list
            .whereType<Map>()
            .map((p) => Map<String, dynamic>.from(p))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _loadError = true;
        });
      }
    }
  }

  Future<void> _export(bool print) async {
    if (_exporting || _loading || _loadError) return;
    setState(() => _exporting = true);
    try {
      // Like user-web, export the complete catalog regardless of search/tab.
      final title = 'Dalitu — ${policyLabel('policies.tab.all.title')}';
      final path = await exportPolicyDocument(
        title,
        policyDocumentText(policyCatalog(_policies), fallback: ''),
        print: print,
      );
      if (!print && mounted) {
        await Share.shareXFiles([XFile(path)], subject: title);
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
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: AppStrings.currentLang,
    builder: (context, _, _) {
      final catalog = policyCatalog(_policies);
      final query = normalizeContentText(_query.trim());
      final visible = catalog
          .where(
            (p) =>
                (_group == 'all' || p['group'] == _group) &&
                (query.isEmpty || policySearchText(p).contains(query)),
          )
          .toList();
      final colors = Theme.of(context).colorScheme;
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    policyLabel('policies.compactTitle'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                PopupMenuButton<bool>(
                  tooltip: AppStrings.t('parity.pdf'),
                  enabled: !_loading && !_loadError && !_exporting,
                  onSelected: _export,
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: false,
                      child: Text(AppStrings.t('parity.pdf')),
                    ),
                    PopupMenuItem(
                      value: true,
                      child: Text(AppStrings.t('parity.print')),
                    ),
                  ],
                  icon: const Icon(Icons.file_download_outlined),
                ),
              ],
            ),
            Text(
              policyLabel('policies.compactDescription'),
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 18),
            TextField(
              key: const ValueKey('policy-search'),
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: AppStrings.t('parity.search'),
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: AppStrings.t('parity.reset'),
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('policy-group-$_group'),
              initialValue: _group,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: policyLabel('policies.directory'),
              ),
              items: [
                for (final g in ['all', ...policyGroups])
                  DropdownMenuItem(
                    value: g,
                    child: Text(
                      '${g == 'all' ? policyLabel('policies.all') : policyLabel('policies.$g')} (${g == 'all' ? catalog.length : catalog.where((p) => p['group'] == g).length})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _group = v);
              },
            ),
            const SizedBox(height: 12),
            Text(
              policyLabel('policies.exportHint'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (_loading || _exporting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(),
              ),
            if (_loadError)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(policyLabel('policies.loadError')),
                      TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: Text(AppStrings.t('common.retry')),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(AppStrings.t('search.noResults')),
              ),
            for (final g in policyGroups)
              if (visible.any((p) => p['group'] == g)) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    policyLabel('policies.$g'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (final p in visible.where((p) => p['group'] == g))
                  _PolicyCard(policy: p),
              ],
            if (_group == 'enforcement') const _EnforcementSteps(),
          ],
        ),
      );
    },
  );
}

class _EnforcementSteps extends StatelessWidget {
  const _EnforcementSteps();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            policyLabel('policies.strikes.systemTitle'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(policyLabel('policies.strikes.systemDesc')),
          const SizedBox(height: 12),
          for (final step in ['warning', 's1', 's2', 's3'])
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(policyLabel('policies.strikes.$step.title')),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SelectableText(
                    policyLabel('policies.strikes.$step.desc'),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.policy});
  final Map<String, dynamic> policy;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rules = policy['rules'] as List? ?? [];
    final exceptions = policy['exceptions'] as List? ?? [];
    final effective = DateTime.tryParse('${policy['effectiveAt'] ?? ''}');
    final severity = '${policy['severity'] ?? 'info'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  '${policy['code'] ?? ''}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                Text(
                  policyLabel(
                    'policies.sev.${['critical', 'high', 'medium'].contains(severity) ? severity : 'info'}',
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${policy['name'] ?? ''}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              '${policy['content'] ?? ''}',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
            if (policy['version'] != null || effective != null) ...[
              const SizedBox(height: 10),
              Text(
                [
                  if (policy['version'] != null)
                    AppStrings.format('policies.version', {
                      'version': policy['version'],
                    }),
                  if (effective != null)
                    AppStrings.format('policies.effectiveDate', {
                      'date': AppStrings.date(effective.toLocal()),
                    }),
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            if (rules.isNotEmpty || exceptions.isNotEmpty)
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text(
                    policyLabel('policies.mandatoryRules'),
                    style: theme.textTheme.labelLarge,
                  ),
                  children: [
                    for (final rule in rules) _bullet(context, '$rule'),
                    if (exceptions.isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            policyLabel('policies.exceptionsEdsa'),
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                      ),
                      for (final exception in exceptions)
                        _bullet(context, '$exception'),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bullet(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•  '),
        Expanded(
          child: SelectableText(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ),
      ],
    ),
  );
}
