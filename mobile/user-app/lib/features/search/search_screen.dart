import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/storage/app_preferences.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../../channel/models/channel_models.dart';
import '../content/content_models.dart';
import '../content/content_service.dart';
import '../content/video_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.auth,
    this.initialQuery = '',
    this.initialTag,
    this.initialCategoryId,
  });
  final AuthController auth;
  final String initialQuery;
  final String? initialTag, initialCategoryId;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  final _prefs = const AppPreferencesStore();
  late final ContentService _content = ContentService(widget.auth);

  List<VideoCard> _results = const [];
  List<String> _recentSearches = [];
  List<ChannelDetail> _channelResults = const [];
  String _resultType = 'all';
  String _committedType = 'all';
  String _sort = 'relevance';
  String? _duration;
  String? _dateRange;
  String? _categoryId, _tag;
  List<Category> _categories = const [];
  String? _error;
  bool _loading = false;
  bool _searched = false;
  bool _hasMore = false;
  int _page = 1;
  int _generation = 0;
  String _committedQuery = '';
  String _committedSort = 'relevance';
  String? _committedDuration;
  String? _committedDateRange;
  String? _committedCategoryId, _committedTag;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecentSearches());
    unawaited(_loadCategories());
    _categoryId = widget.initialCategoryId;
    _tag = widget.initialTag;
    _query.text = widget.initialQuery.isNotEmpty
        ? widget.initialQuery
        : widget.initialTag ?? '';
    if (_query.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  Future<void> _loadCategories() async {
    try {
      final values = await _content.categories();
      if (mounted) setState(() => _categories = values);
    } catch (_) {
      /* Optional filters do not block keyword search. */
    }
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery ||
        oldWidget.initialTag != widget.initialTag ||
        oldWidget.initialCategoryId != widget.initialCategoryId) {
      _query.text = widget.initialQuery.isNotEmpty
          ? widget.initialQuery
          : widget.initialTag ?? '';
      _categoryId = widget.initialCategoryId;
      _tag = widget.initialTag;
      _resultType = 'all';
      if (_query.text.isNotEmpty) _search();
    }
  }

  Future<void> _loadRecentSearches() async {
    try {
      final list = await _prefs.readRecentSearches();
      if (mounted) setState(() => _recentSearches = list);
    } catch (_) {
      // Device storage is optional; searching must remain available.
    }
  }

  Future<void> _persistRecentSearches(List<String> searches) async {
    try {
      await _prefs.writeRecentSearches(searches);
    } catch (_) {
      // Keep this session's history when device storage is unavailable.
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  int get _activeFilterCount {
    var count = 0;
    if (_sort != 'relevance') count++;
    if (_duration != null) count++;
    if (_dateRange != null) count++;
    if (_categoryId != null) count++;
    if (_tag?.isNotEmpty == true) count++;
    return count;
  }

  Future<void> _saveRecentSearch(String term) async {
    final clean = term.trim();
    if (clean.isEmpty) return;
    final updated = [
      clean,
      ..._recentSearches.where((x) => x != clean),
    ].take(10).toList();
    setState(() => _recentSearches = updated);
    await _persistRecentSearches(updated);
  }

  Future<void> _removeRecentSearch(String term) async {
    HapticFeedback.lightImpact();
    final updated = _recentSearches.where((x) => x != term).toList();
    setState(() => _recentSearches = updated);
    await _persistRecentSearches(updated);
  }

  Future<void> _clearAllRecentSearches() async {
    HapticFeedback.mediumImpact();
    setState(() => _recentSearches = []);
    await _persistRecentSearches([]);
  }

  Future<void> _search({bool more = false}) async {
    final query = more ? _committedQuery : _query.text.trim();
    if (query.isEmpty || (more && _loading)) return;
    if (!more) {
      FocusManager.instance.primaryFocus?.unfocus();
      ++_generation;
      _committedQuery = query;
      _committedSort = _sort;
      _committedDuration = _duration;
      _committedDateRange = _dateRange;
      _committedCategoryId = _categoryId;
      _committedTag = _tag;
      _channelResults = const [];
      _committedType = _resultType;
      _results = const [];
    }
    final generation = _generation;
    final sort = _committedSort;
    final next = more ? _page + 1 : 1;
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });

    if (!more) {
      unawaited(_saveRecentSearch(query));
    }

    try {
      if (_committedType == 'channels') {
        final channels = await _content.searchChannels(
          query: query,
          page: next,
        );
        if (!mounted || generation != _generation) return;
        setState(() {
          final seen = _channelResults.map((c) => c.id).toSet();
          _channelResults = more
              ? [
                  ..._channelResults,
                  ...channels.items.where((c) => seen.add(c.id)),
                ]
              : channels.items;
          _page = channels.page;
          _hasMore = channels.hasMore;
          _loading = false;
        });
        return;
      }
      if (!more && _committedType == 'all') {
        unawaited(_findChannels(query, generation));
      }
      final page = await _content.searchVideos(
        query: query,
        page: next,
        sort: sort,
        duration: _committedDuration,
        dateRange: _committedDateRange,
        categoryId: _committedCategoryId,
        tag: _committedTag,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = more ? [..._results, ...page.items] : page.items;
        _page = page.page;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } on ApiFailure catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = AppStrings.apiError(error, fallback: 'common.error');
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = AppStrings.t('common.networkError');
          _loading = false;
        });
      }
    }
  }

  Future<void> _findChannels(String query, int generation) async {
    try {
      final page = await _content.searchChannels(query: query, pageSize: 3);
      if (mounted && generation == _generation) {
        setState(() => _channelResults = page.items);
      }
    } catch (_) {
      /* Video results remain usable if channel search is unavailable. */
    }
  }

  void _showFilterSheet() {
    var tempSort = _sort;
    var tempDuration = _duration;
    var tempDateRange = _dateRange;
    var tempCategory = _categoryId;
    var tempTag = _tag ?? '';
    var resetVersion = 0;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBackgroundCard : AppColors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 12, 10),
                    child: Row(
                      children: [
                        AppIcons.asset(AppIcons.filter, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            AppStrings.t('search.filterTitle'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              tempSort = 'relevance';
                              tempDuration = null;
                              tempDateRange = null;
                              tempCategory = null;
                              tempTag = '';
                              resetVersion++;
                            });
                          },
                          child: Text(AppStrings.t('search.resetFilter')),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Filter Content
                  Flexible(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                      children: [
                        // Sort by
                        if (_categories.isNotEmpty) ...[
                          DropdownButtonFormField<String>(
                            key: ValueKey(tempCategory),
                            initialValue:
                                _categories.any((c) => c.id == tempCategory)
                                ? tempCategory
                                : null,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: AppStrings.t('upload.category'),
                            ),
                            items: [
                              DropdownMenuItem<String>(
                                value: null,
                                child: Text(AppStrings.t('search.resultAll')),
                              ),
                              ..._categories.map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.displayName),
                                ),
                              ),
                            ],
                            onChanged: (value) =>
                                setModalState(() => tempCategory = value),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          initialValue: tempTag,
                          key: ValueKey('tag-$resetVersion'),
                          decoration: InputDecoration(
                            labelText: AppStrings.t('upload.tags'),
                            prefixText: '#',
                          ),
                          onChanged: (value) => tempTag = value
                              .trim()
                              .replaceFirst(RegExp(r'^#'), ''),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          AppStrings.t('search.sort.title'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final item in const [
                              ('relevance', 'search.sort.relevance'),
                              ('newest', 'search.sort.newest'),
                              ('popular', 'search.sort.popular'),
                            ])
                              ChoiceChip(
                                label: Text(AppStrings.t(item.$2)),
                                selected: tempSort == item.$1,
                                onSelected: (_) {
                                  setModalState(() => tempSort = item.$1);
                                },
                              ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Duration Filter
                        Text(
                          AppStrings.t('search.duration'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final dur in const [
                              (null, 'search.durationAll'),
                              ('short', 'search.durationShort'),
                              ('medium', 'search.durationMedium'),
                              ('long', 'search.durationLong'),
                            ])
                              ChoiceChip(
                                label: Text(AppStrings.t(dur.$2)),
                                selected: tempDuration == dur.$1,
                                showCheckmark: false,
                                shape: const StadiumBorder(),
                                onSelected: (_) {
                                  setModalState(() => tempDuration = dur.$1);
                                },
                              ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Date Range Filter
                        Text(
                          AppStrings.t('search.dateRange'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final date in const [
                              (null, 'search.dateAll'),
                              ('today', 'search.dateToday'),
                              ('this_week', 'search.dateThisWeek'),
                              ('this_month', 'search.dateThisMonth'),
                              ('this_year', 'search.dateThisYear'),
                            ])
                              ChoiceChip(
                                label: Text(AppStrings.t(date.$2)),
                                selected: tempDateRange == date.$1,
                                showCheckmark: false,
                                shape: const StadiumBorder(),
                                onSelected: (_) {
                                  setModalState(() => tempDateRange = date.$1);
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Apply button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _sort = tempSort;
                            _duration = tempDuration;
                            _dateRange = tempDateRange;
                            _categoryId = tempCategory;
                            _tag = tempTag.isEmpty ? null : tempTag;
                          });
                          Navigator.pop(ctx);
                          if (_searched) _search();
                        },
                        child: Text(AppStrings.t('search.applyFilter')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeFilters = _activeFilterCount;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AppStrings.t('search.title'),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Wrap(
                      spacing: 8,
                      children: [
                        for (final type in ['all', 'videos', 'channels'])
                          ChoiceChip(
                            label: Text(
                              AppStrings.t(
                                'search.result${type == 'all'
                                    ? 'All'
                                    : type == 'videos'
                                    ? 'Videos'
                                    : 'Channels'}',
                              ),
                            ),
                            selected: _resultType == type,
                            onSelected: (_) {
                              if (_resultType == type) return;
                              setState(() => _resultType = type);
                              if (_query.text.trim().isNotEmpty) _search();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _query,
                      autofocus: false,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        hintText: AppStrings.t('search.queryHint'),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: .4),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide(color: theme.dividerColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 22),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_query.text.isNotEmpty)
                              IconButton(
                                tooltip: AppStrings.t('search.clear'),
                                onPressed: () => setState(() {
                                  ++_generation;
                                  _loading = false;
                                  _hasMore = false;
                                  _page = 1;
                                  _error = null;
                                  _committedQuery = '';
                                  _channelResults = const [];
                                  _query.clear();
                                  _results = const [];
                                  _searched = false;
                                }),
                                icon: const Icon(Icons.close_rounded, size: 20),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: IconButton.filled(
                                tooltip: AppStrings.t('search.submit'),
                                onPressed:
                                    _loading || _query.text.trim().isEmpty
                                    ? null
                                    : () => _search(),
                                icon: _loading
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 22,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),

                    // Recent searches section
                    if (!_searched && _recentSearches.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      HuTubeSectionHeader(
                        title: AppStrings.t('search.recent'),
                        action: AppStrings.t('search.clearAllRecent'),
                        onAction: _clearAllRecentSearches,
                        compact: true,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final term in _recentSearches)
                            InputChip(
                              avatar: const Icon(
                                Icons.history_rounded,
                                size: 14,
                              ),
                              label: Text(
                                term,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              shape: const StadiumBorder(),
                              onDeleted: () => _removeRecentSearch(term),
                              onPressed: () {
                                _query.text = term;
                                _search();
                              },
                            ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Horizontal Filters Bar
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: IconButton.outlined(
                              tooltip: AppStrings.t('search.filterTitle'),
                              onPressed: _showFilterSheet,
                              icon: Badge(
                                isLabelVisible: activeFilters > 0,
                                label: Text('$activeFilters'),
                                child: const Icon(Icons.tune_rounded, size: 20),
                              ),
                            ),
                          ),
                          for (final item in const [
                            ('relevance', 'search.sort.relevance'),
                            ('newest', 'search.sort.newest'),
                            ('popular', 'search.sort.popular'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                labelPadding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                labelStyle: theme.textTheme.labelMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                label: Text(AppStrings.t(item.$2)),
                                selected: _sort == item.$1,
                                showCheckmark: false,
                                shape: const StadiumBorder(),
                                onSelected: (_) {
                                  setState(() => _sort = item.$1);
                                  if (_searched) _search();
                                },
                              ),
                            ),
                          if (_duration != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InputChip(
                                avatar: const Icon(
                                  Icons.timer_outlined,
                                  size: 14,
                                ),
                                shape: const StadiumBorder(),
                                label: Text(
                                  _duration == 'short'
                                      ? AppStrings.t('search.durationShort')
                                      : (_duration == 'medium'
                                            ? AppStrings.t(
                                                'search.durationMedium',
                                              )
                                            : AppStrings.t(
                                                'search.durationLong',
                                              )),
                                ),
                                onDeleted: () {
                                  setState(() => _duration = null);
                                  if (_searched) _search();
                                },
                              ),
                            ),
                          if (_dateRange != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InputChip(
                                avatar: const Icon(
                                  Icons.date_range_outlined,
                                  size: 14,
                                ),
                                shape: const StadiumBorder(),
                                label: Text(_dateRange!),
                                onDeleted: () {
                                  setState(() => _dateRange = null);
                                  if (_searched) _search();
                                },
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

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
                    else if (_loading &&
                        _results.isEmpty &&
                        _channelResults.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(36),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_results.isEmpty && _channelResults.isEmpty)
                      HuTubeStateView(
                        icon: Icons.manage_search_rounded,
                        title: AppStrings.t(
                          _searched ? 'search.noResults' : 'search.startTitle',
                        ),
                        message: _searched
                            ? AppStrings.t('search.tryAnother')
                            : AppStrings.t('search.enterKeyword'),
                        compact: true,
                        accent: AppColors.violet,
                      )
                    else ...[
                      const SizedBox(height: 8),
                    ],
                    if (_error == null)
                      for (final channel in _channelResults) ...[
                        _SearchChannelCard(channel: channel, auth: widget.auth),
                        const SizedBox(height: 8),
                      ],
                  ],
                ),
              ),
              if (_error == null && _results.isNotEmpty)
                SliverList.builder(
                  itemCount: _results.length,
                  itemBuilder: (_, index) => Padding(
                    key: ValueKey(_results[index].id),
                    padding: const EdgeInsets.only(bottom: 14),
                    child: VideoCardTile(
                      video: _results[index],
                      auth: widget.auth,
                    ),
                  ),
                ),
              if (_error == null &&
                  (_results.isNotEmpty || _channelResults.isNotEmpty) &&
                  _hasMore)
                SliverToBoxAdapter(
                  child: OutlinedButton(
                    onPressed: _loading ? null : () => _search(more: true),
                    child: Text(
                      AppStrings.t(
                        _loading ? 'search.loading' : 'search.loadMore',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SearchChannelCard extends StatelessWidget {
  const _SearchChannelCard({required this.channel, required this.auth});
  final ChannelDetail channel;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/channels/${channel.handle}'),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.primaryPink.withValues(alpha: 0.15),
              backgroundImage: channel.avatarUrl != null
                  ? NetworkImage(channel.avatarUrl!)
                  : null,
              child: channel.avatarUrl == null
                  ? Text(
                      channel.name.isNotEmpty
                          ? channel.name[0].toUpperCase()
                          : 'C',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryPink,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${channel.handle} • ${AppStrings.number(channel.subscriberCount)} người đăng ký',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : AppColors.textMuted,
                    ),
                  ),
                  if (channel.description != null &&
                      channel.description!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      channel.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => context.push('/channels/${channel.handle}'),
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text(
                'Xem kênh',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
