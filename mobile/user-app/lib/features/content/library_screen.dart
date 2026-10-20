import 'package:flutter/material.dart';
import '../../core/widgets/content_filters.dart';
import 'package:go_router/go_router.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'content_models.dart';
import 'content_service.dart';
import 'video_card.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.auth, this.initialTab = 0});
  final AuthController auth;
  final int initialTab;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final ContentService _content;
  bool _loading = true;
  String? _error;
  List<LibraryVideo> _history = [];
  List<LibraryVideo> _liked = [];
  late int _tab;
  int? _rating;
  String _query = '';
  String _sort = 'newest';
  String _dateRange = 'all';
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 1);
    _content = ContentService(widget.auth);
    _load();
  }

  Future<void> _load() async {
    final generation = ++_requestGeneration;
    final query = _query, sort = _sort, dateRange = _dateRange;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final history = await loadAllPages(
        (page) => _content.history(
          page: page,
          query: query,
          sort: sort,
          dateRange: dateRange,
        ),
      );
      final liked = await loadAllPages(
        (page) => _content.liked(page: page, rating: _rating),
      );
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _history = history.items;
          _liked = liked.items;
          _loading = false;
        });
      }
    } on ApiFailure catch (error) {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _error = AppStrings.apiError(error, fallback: 'library.loadError');
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _error = AppStrings.t('library.loadError');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    initialIndex: _tab,
    length: 2,
    child: RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: HuTubeSectionHeader(
                title: AppStrings.t('library.title'),
                subtitle: AppStrings.t('library.subtitle'),
                action: AppStrings.t('library.playlists'),
                onAction: () => context.push('/playlists'),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              onTap: (value) => setState(() => _tab = value),
              tabs: [
                Tab(
                  icon: AppIcons.asset(AppIcons.history, size: 20),
                  text: AppStrings.t('library.history'),
                ),
                Tab(
                  icon: AppIcons.asset(AppIcons.favorite, size: 20),
                  text: AppStrings.t('library.liked'),
                ),
              ],
            ),
          ),
          if (_tab == 0)
            SliverToBoxAdapter(
              child: ContentFilters(
                initialQuery: _query,
                initialValues: {'sort': _sort, 'dateRange': _dateRange},
                options: const {
                  'sort': ['newest', 'oldest'],
                  'dateRange': ['all', 'today', 'week', 'month'],
                },
                onChanged: (query, values) {
                  _query = query;
                  _sort = values['sort'] ?? 'newest';
                  _dateRange = values['dateRange'] ?? 'all';
                  _load();
                },
              ),
            ),
          if (_tab == 1)
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    for (final score in <int?>[null, 1, 2, 3, 4, 5])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          avatar: score == null
                              ? null
                              : AppIcons.asset(AppIcons.star, size: 14),
                          label: Text(
                            score == null
                                ? AppStrings.t('library.allRatings')
                                : AppStrings.format('library.ratingStars', {
                                    'count': AppStrings.number(score),
                                  }),
                          ),
                          selected: _rating == score,
                          showCheckmark: false,
                          onSelected: (_) {
                            setState(() => _rating = score);
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (_loading)
            SliverList.list(
              children: [
                for (var i = 0; i < 3; i++)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: _LibrarySkeleton(),
                  ),
              ],
            )
          else if (_error != null)
            SliverToBoxAdapter(
              child: HuTubeStateView(
                icon: Icons.cloud_off_rounded,
                title: _error!,
                message: AppStrings.t('common.networkError'),
                actionLabel: AppStrings.t('common.retry'),
                onAction: _load,
              ),
            )
          else if ((_tab == 0 ? _history : _liked).isEmpty)
            SliverToBoxAdapter(
              child: HuTubeStateView(
                icon: Icons.video_library_outlined,
                title: AppStrings.t('library.empty'),
                message: AppStrings.t(
                  _tab == 0
                      ? 'library.historyDescription'
                      : 'library.likedDescription',
                ),
                compact: true,
                accent: AppColors.violet,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              sliver: SliverList.builder(
                itemCount: (_tab == 0 ? _history : _liked).length,
                itemBuilder: (_, index) {
                  final item = (_tab == 0 ? _history : _liked)[index];
                  return VideoCardTile(
                    video: item,
                    progress: _tab == 0 ? item.progress : null,
                  );
                },
              ),
            ),
        ],
      ),
    ),
  );
}

class _LibrarySkeleton extends StatelessWidget {
  const _LibrarySkeleton();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 138,
        height: 82,
        decoration: BoxDecoration(
          color: AppColors.borderSubtle,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 14,
              child: ColoredBox(color: AppColors.borderSubtle),
            ),
            SizedBox(height: 8),
            SizedBox(
              width: 100,
              height: 12,
              child: ColoredBox(color: AppColors.borderSubtle),
            ),
          ],
        ),
      ),
    ],
  );
}
