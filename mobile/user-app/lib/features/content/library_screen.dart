import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'content_models.dart';
import 'content_service.dart';
import 'video_card.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final ContentService _content;
  bool _loading = true;
  String? _error;
  List<LibraryVideo> _history = [];
  List<LibraryVideo> _liked = [];
  int _tab = 0;
  int? _rating;

  @override
  void initState() {
    super.initState();
    _content = ContentService(widget.auth);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final history = await _content.history();
      final liked = await _content.liked(rating: _rating);
      if (mounted) {
        setState(() {
          _history = history.items;
          _liked = liked.items;
          _loading = false;
        });
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = AppStrings.apiError(error, fallback: 'library.loadError');
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppStrings.t('library.loadError');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
        children: const [
          _LibrarySkeleton(),
          SizedBox(height: 12),
          _LibrarySkeleton(),
          SizedBox(height: 12),
          _LibrarySkeleton(),
        ],
      );
    }
    if (_error != null) {
      return HuTubeStateView(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        message: AppStrings.t('common.networkError'),
        actionLabel: AppStrings.t('common.retry'),
        onAction: _load,
      );
    }
    final items = _tab == 0 ? _history : _liked;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: HuTubeSectionHeader(
              title: AppStrings.t('library.title'),
              subtitle: 'Những video bạn muốn xem lại hoặc đã đánh giá.',
              action: 'Playlist',
              onAction: () => context.push('/playlists'),
            ),
          ),
          TabBar(
            onTap: (value) => setState(() => _tab = value),
            tabs: [
              Tab(text: AppStrings.t('library.history')),
              Tab(text: AppStrings.t('library.liked')),
            ],
          ),
          if (_tab == 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  for (final score in <int?>[null, 1, 2, 3, 4, 5])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(
                          score == null
                              ? AppStrings.t('library.allRatings')
                              : AppStrings.format('library.ratingStars', {
                                  'count': AppStrings.number(score),
                                }),
                        ),
                        selected: _rating == score,
                        onSelected: (_) {
                          setState(() => _rating = score);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primaryPink,
              onRefresh: _load,
              child: items.isEmpty
                  ? ListView(
                      children: [
                        HuTubeStateView(
                          icon: Icons.video_library_outlined,
                          title: AppStrings.t('library.empty'),
                          message: _tab == 0
                              ? 'Video bạn đã xem sẽ được lưu tại đây.'
                              : 'Hãy thả tim video để tìm lại chúng nhanh hơn.',
                          compact: true,
                          accent: AppColors.violet,
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: items.length,
                      itemBuilder: (_, index) => VideoCardTile(
                        video: items[index],
                        progress: _tab == 0 ? items[index].progress : null,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
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
