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
import '../../channel/services/channel_service.dart';
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
  final _prefs = const AppPreferencesStore();
  late final ContentService _content = ContentService(widget.auth);
  late final ChannelService _channels = ChannelService(widget.auth);

  List<VideoCard> _results = const [];
  List<String> _recentSearches = [];
  ChannelDetail? _matchedChannel;
  String _sort = 'relevance';
  String? _duration;
  String? _dateRange;
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

  @override
  void initState() {
    super.initState();
    _prefs.readRecentSearches().then((list) {
      if (mounted) setState(() => _recentSearches = list);
    });
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
    await _prefs.writeRecentSearches(updated);
  }

  Future<void> _removeRecentSearch(String term) async {
    HapticFeedback.lightImpact();
    final updated = _recentSearches.where((x) => x != term).toList();
    setState(() => _recentSearches = updated);
    await _prefs.writeRecentSearches(updated);
  }

  Future<void> _clearAllRecentSearches() async {
    HapticFeedback.mediumImpact();
    setState(() => _recentSearches = []);
    await _prefs.writeRecentSearches([]);
  }

  Future<void> _search({bool more = false}) async {
    final query = more ? _committedQuery : _query.text.trim();
    if (query.isEmpty || (more && _loading)) return;
    if (!more) {
      ++_generation;
      _committedQuery = query;
      _committedSort = _sort;
      _committedDuration = _duration;
      _committedDateRange = _dateRange;
      _matchedChannel = null;
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
      final page = await _content.searchVideos(
        query: query,
        page: next,
        sort: sort,
        duration: _committedDuration,
        dateRange: _committedDateRange,
      );
      ChannelDetail? matchedChannel = more ? _matchedChannel : null;
      if (!more) {
        final clean = query.startsWith('@') ? query.substring(1) : query;
        try {
          matchedChannel = await _channels.getChannel(clean);
        } catch (_) {
          if (page.items.isNotEmpty) {
            final first = page.items.first;
            final normQ = query.toLowerCase().replaceAll('@', '').trim();
            if (first.channelName.toLowerCase().contains(normQ) ||
                first.channelHandle.toLowerCase().contains(normQ)) {
              try {
                matchedChannel = await _channels.getChannel(first.channelHandle);
              } catch (_) {}
            }
          }
        }
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = more ? [..._results, ...page.items] : page.items;
        _matchedChannel = matchedChannel;
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

  void _showFilterSheet() {
    var tempSort = _sort;
    var tempDuration = _duration;
    var tempDateRange = _dateRange;

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
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
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

    return ListView(
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
            prefixIcon: Padding(
              padding: const EdgeInsets.all(12),
              child: AppIcons.asset(AppIcons.search, size: 20),
            ),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    tooltip: AppStrings.t('search.clear'),
                    onPressed: () => setState(() {
                      ++_generation;
                      _loading = false;
                      _hasMore = false;
                      _page = 1;
                      _error = null;
                      _committedQuery = '';
                      _matchedChannel = null;
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
                : AppIcons.asset(
                    AppIcons.search,
                    size: 18,
                    color: Colors.white,
                  ),
            label: Text(AppStrings.t('search.submit')),
          ),
        ),

        // Recent searches section
        if (!_searched && _recentSearches.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppStrings.t('search.recent'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: _clearAllRecentSearches,
                child: Text(
                  AppStrings.t('search.clearAllRecent'),
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final term in _recentSearches)
                InputChip(
                  avatar: const Icon(Icons.history_rounded, size: 14),
                  label: Text(term),
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
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  shape: const StadiumBorder(),
                  avatar: AppIcons.asset(
                    AppIcons.filter,
                    size: 16,
                    color: activeFilters > 0 ? AppColors.primaryPink : null,
                  ),
                  label: Text(
                    activeFilters > 0
                        ? 'Bộ lọc ($activeFilters)'
                        : AppStrings.t('search.filterTitle'),
                    style: TextStyle(
                      color: activeFilters > 0 ? AppColors.primaryPink : null,
                      fontWeight:
                          activeFilters > 0 ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  onPressed: _showFilterSheet,
                ),
              ),
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
                  padding: const EdgeInsets.only(right: 8),
                  child: InputChip(
                    avatar: const Icon(Icons.timer_outlined, size: 14),
                    shape: const StadiumBorder(),
                    label: Text(
                      _duration == 'short'
                          ? AppStrings.t('search.durationShort')
                          : (_duration == 'medium'
                              ? AppStrings.t('search.durationMedium')
                              : AppStrings.t('search.durationLong')),
                    ),
                    onDeleted: () {
                      setState(() => _duration = null);
                      if (_searched) _search();
                    },
                  ),
                ),
              if (_dateRange != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InputChip(
                    avatar: const Icon(Icons.date_range_outlined, size: 14),
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
        else if (_loading && _results.isEmpty)
          const Padding(
            padding: EdgeInsets.all(36),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_results.isEmpty)
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
          if (_matchedChannel != null) ...[
            _SearchChannelCard(channel: _matchedChannel!, auth: widget.auth),
            const SizedBox(height: 8),
          ],
          for (final video in _results)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: VideoCardTile(video: video),
            ),
          if (_hasMore)
            OutlinedButton(
              onPressed: _loading ? null : () => _search(more: true),
              child: Text(
                AppStrings.t(_loading ? 'search.loading' : 'search.loadMore'),
              ),
            ),
        ],
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
            FilledButton.tonal(
              onPressed: () => context.push('/channels/${channel.handle}'),
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
