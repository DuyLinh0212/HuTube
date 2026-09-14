import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../core/errors/app_error.dart';
import '../../core/theme/app_theme.dart';
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
    if (widget.explore) _loadCategories();
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
      if (mounted)
        setState(() {
          _error = error.message;
          _loading = false;
          _moreLoading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _error = 'Không thể tải video. Kiểm tra kết nối rồi thử lại.';
          _loading = false;
          _moreLoading = false;
        });
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
    final title = widget.explore ? 'Khám phá' : 'Dành cho bạn';
    final description = widget.explore
        ? 'Chọn chủ đề để tìm nội dung mới trong cộng đồng HuTube.'
        : 'Video mới và nổi bật từ cộng đồng HuTube.';
    if (_loading)
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryPink),
      );
    if (_error != null && _videos.isEmpty) {
      return _Failure(message: _error!, onRetry: () => _load(refresh: true));
    }
    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: () => _load(refresh: true),
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
          if (widget.explore) ...[
            const SizedBox(height: 18),
            _FilterRow(
              sort: _sort,
              categoryId: _categoryId,
              categories: _categories,
              onSort: _setSort,
              onCategory: _setCategory,
            ),
          ],
          const SizedBox(height: 14),
          if (_error != null)
            _InlineError(message: _error!, onRetry: () => _load(refresh: true)),
          if (_videos.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 70),
              child: Center(child: Text('Chưa có video phù hợp.')),
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
    required this.onSort,
    required this.onCategory,
  });
  final String sort;
  final String? categoryId;
  final List<Category> categories;
  final ValueChanged<String> onSort;
  final ValueChanged<String?> onCategory;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final item in const [
              ('newest', 'Mới nhất'),
              ('popular', 'Phổ biến'),
              ('trending', 'Thịnh hành'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(item.$2),
                  selected: sort == item.$1,
                  onSelected: (_) => onSort(item.$1),
                ),
              ),
          ],
        ),
      ),
      if (categories.isNotEmpty) ...[
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: const Text('Tất cả chủ đề'),
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
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 48,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
        ],
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    color: AppColors.dangerBg,
    child: ListTile(
      leading: const Icon(Icons.error_outline, color: AppColors.danger),
      title: Text(message),
      trailing: TextButton(onPressed: onRetry, child: const Text('Thử lại')),
    ),
  );
}
