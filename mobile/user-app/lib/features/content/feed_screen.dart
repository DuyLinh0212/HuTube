import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'content_models.dart';
import 'content_service.dart';
import 'video_card.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, required this.auth, this.explore = false});
  final AuthController auth;
  final bool explore;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late final ContentService _content;
  final _scroll = ScrollController();
  List<VideoCard> _videos = [];
  List<Category> _categories = [];
  bool _loading = true;
  bool _moreLoading = false;
  String? _error;
  int _page = 1;
  int _total = 0;
  String _sort = 'newest';
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    _content = ContentService(widget.auth);
    _scroll.addListener(_maybeLoadMore);
    _load();
    _loadCategories();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _content.categories();
      if (mounted) setState(() => _categories = categories);
    } catch (_) {
      // Explore remains usable without a category list.
    }
  }

  Future<void> _load({bool refresh = false}) async {
    final nextPage = refresh ? 1 : _page;
    setState(() {
      if (refresh) _loading = true;
      _error = null;
    });
    try {
      final page = await _content.feed(
        explore: widget.explore,
        page: nextPage,
        categoryId: _categoryId,
        sort: widget.explore ? _sort : 'popular',
      );
      if (!mounted) return;
      setState(() {
        _videos = nextPage == 1 ? page.items : [..._videos, ...page.items];
        _page = page.page;
        _total = page.total;
        _loading = false;
        _moreLoading = false;
      });
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = AppStrings.apiError(error, fallback: 'feed.loadError');
          _loading = false;
          _moreLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppStrings.t('feed.loadError');
          _loading = false;
          _moreLoading = false;
        });
      }
    }
  }

  void _maybeLoadMore() {
    if (_loading || _moreLoading || _videos.length >= _total) return;
    if (_scroll.position.extentAfter > 360) return;
    setState(() {
      _moreLoading = true;
      _page += 1;
    });
    _load();
  }

  void _setSort(String value) {
    if (value == _sort) return;
    setState(() => _sort = value);
    _load(refresh: true);
  }

  void _setCategory(String? value) {
    if (value == _categoryId) return;
    setState(() => _categoryId = value);
    _load(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final title = AppStrings.t(
      widget.explore ? 'feed.exploreTitle' : 'feed.homeTitle',
    );
    final description = widget.explore
        ? AppStrings.t('feed.exploreDescription')
        : AppStrings.t('feed.homeDescription');
    if (_loading) {
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
        children: [
          const _FeedSkeletonHeader(),
          const SizedBox(height: 24),
          for (var index = 0; index < 3; index++) ...[
            const _FeedSkeletonTile(),
            if (index != 2) const SizedBox(height: 22),
          ],
        ],
      );
    }
    if (_error != null && _videos.isEmpty) {
      return _Failure(message: _error!, onRetry: () => _load(refresh: true));
    }
    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: () => _load(refresh: true),
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            widget.explore ? 'KHÁM PHÁ HU TUBE' : 'CHÀO MỪNG TRỞ LẠI',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 7),
          HuTubeSectionHeader(title: title, subtitle: description),
          const SizedBox(height: 18),
          _FilterRow(
            sort: _sort,
            categoryId: _categoryId,
            categories: _categories,
            showSort: widget.explore,
            onSort: _setSort,
            onCategory: _setCategory,
          ),
          const SizedBox(height: 22),
          if (_error != null)
            _InlineError(message: _error!, onRetry: () => _load(refresh: true)),
          if (_videos.isEmpty)
            HuTubeStateView(
              icon: Icons.video_library_outlined,
              title: AppStrings.t('feed.empty'),
              message:
                  'Thử chọn chủ đề khác hoặc quay lại sau để xem nội dung mới.',
              compact: true,
            ),
          ..._videos.map((video) => VideoCardTile(video: video)),
          if (_moreLoading)
            const Padding(
              padding: EdgeInsets.all(22),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primaryPink),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.sort,
    required this.categoryId,
    required this.categories,
    required this.showSort,
    required this.onSort,
    required this.onCategory,
  });
  final String sort;
  final String? categoryId;
  final List<Category> categories;
  final bool showSort;
  final ValueChanged<String> onSort;
  final ValueChanged<String?> onCategory;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (showSort)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final item in const [
                ('newest', 'feed.sortNewest'),
                ('popular', 'feed.sortPopular'),
                ('trending', 'feed.sortTrending'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(AppStrings.t(item.$2)),
                    selected: sort == item.$1,
                    onSelected: (_) => onSort(item.$1),
                  ),
                ),
            ],
          ),
        ),
      if (categories.isNotEmpty) ...[
        if (showSort) const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(AppStrings.t('feed.allTopics')),
                  selected: categoryId == null,
                  onSelected: (_) => onCategory(null),
                ),
              ),
              for (final category in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(category.name),
                    selected: categoryId == category.id,
                    onSelected: (_) => onCategory(category.id),
                  ),
                ),
            ],
          ),
        ),
      ],
    ],
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: HuTubeStateView(
      icon: Icons.cloud_off_rounded,
      title: message,
      message: 'Kiểm tra kết nối rồi thử lại.',
      actionLabel: AppStrings.t('common.retry'),
      onAction: onRetry,
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    color: AppColors.dangerContainerFor(context),
    child: ListTile(
      leading: Icon(
        Icons.error_outline,
        color: AppColors.onDangerContainerFor(context),
      ),
      title: Text(message),
      trailing: TextButton(
        onPressed: onRetry,
        child: Text(AppStrings.t('common.retry')),
      ),
    ),
  );
}

class _FeedSkeletonHeader extends StatelessWidget {
  const _FeedSkeletonHeader();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(width: 130, height: 11, color: AppColors.borderSubtle),
      const SizedBox(height: 12),
      Container(width: 190, height: 27, color: AppColors.borderSubtle),
      const SizedBox(height: 9),
      Container(width: 290, height: 14, color: AppColors.borderSubtle),
      const SizedBox(height: 18),
      Row(
        children: [
          Container(width: 72, height: 32, color: AppColors.borderSubtle),
          const SizedBox(width: 8),
          Container(width: 82, height: 32, color: AppColors.borderSubtle),
          const SizedBox(width: 8),
          Container(width: 75, height: 32, color: AppColors.borderSubtle),
        ],
      ),
    ],
  );
}

class _FeedSkeletonTile extends StatelessWidget {
  const _FeedSkeletonTile();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.borderSubtle,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      const SizedBox(height: 11),
      Row(
        children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.borderSubtle,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 13, color: AppColors.borderSubtle),
                const SizedBox(height: 7),
                Container(
                  width: 150,
                  height: 11,
                  color: AppColors.borderSubtle,
                ),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}
