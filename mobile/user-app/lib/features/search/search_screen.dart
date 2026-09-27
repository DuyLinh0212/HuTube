import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../content/content_models.dart';
import '../content/content_service.dart';
import '../content/video_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  late final ContentService _content = ContentService(widget.auth);
  List<VideoCard> _results = const [];
  String _sort = 'relevance';
  String? _error;
  bool _loading = false;
  bool _searched = false;
  bool _hasMore = false;
  int _page = 1;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search({bool more = false}) async {
    final query = _query.text.trim();
    if (query.isEmpty || _loading) return;
    final next = more ? _page + 1 : 1;
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    try {
      final page = await _content.searchVideos(
        query: query,
        page: next,
        sort: _sort,
      );
      if (!mounted) return;
      setState(() {
        _results = more ? [..._results, ...page.items] : page.items;
        _page = page.page;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = AppStrings.apiError(error, fallback: 'common.error');
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppStrings.t('common.networkError');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
    children: [
      HuTubeSectionHeader(
        title: AppStrings.t('search.title'),
        subtitle: AppStrings.t('search.subtitle'),
      ),
      const SizedBox(height: 18),
      TextField(
        controller: _query,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(
          hintText: AppStrings.t('search.queryHint'),
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _query.text.isEmpty
              ? null
              : IconButton(
                  tooltip: AppStrings.t('search.clear'),
                  onPressed: () => setState(() {
                    _query.clear();
                    _results = const [];
                    _searched = false;
                  }),
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 48,
        child: FilledButton.icon(
          onPressed: _loading ? null : () => _search(),
          icon: _loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search_rounded),
          label: Text(AppStrings.t('search.submit')),
        ),
      ),
      const SizedBox(height: 16),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final item in const [
              ('relevance', 'search.sort.relevance'),
              ('newest', 'search.sort.newest'),
              ('popular', 'search.sort.popular'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(AppStrings.t(item.$2)),
                  selected: _sort == item.$1,
                  onSelected: (_) {
                    setState(() => _sort = item.$1);
                    if (_searched) _search();
                  },
                ),
              ),
          ],
        ),
      ),
      if (_error != null)
        HuTubeStateView(
          icon: Icons.wifi_off_rounded,
          title: _error!,
          message: AppStrings.t('common.networkError'),
          actionLabel: AppStrings.t('common.retry'),
          onAction: _search,
          compact: true,
          accent: AppColors.violet,
        )
      else if (_loading && _results.isEmpty)
        const Padding(
          padding: EdgeInsets.all(36),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_results.isEmpty)
        HuTubeStateView(
          icon: Icons.manage_search_rounded,
          title: AppStrings.t(_searched ? 'search.noResults' : 'search.startTitle'),
          message: _searched
              ? AppStrings.t('search.tryAnother')
              : AppStrings.t('search.enterKeyword'),
          compact: true,
          accent: AppColors.violet,
        )
      else ...[
        const SizedBox(height: 8),
        for (final video in _results)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: VideoCardTile(video: video),
          ),
        if (_hasMore)
          OutlinedButton(
            onPressed: _loading ? null : () => _search(more: true),
            child: Text(AppStrings.t(_loading ? 'search.loading' : 'search.loadMore')),
          ),
      ],
    ],
  );
}
