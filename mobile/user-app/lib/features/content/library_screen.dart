import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 1);
    _content = ContentService(widget.auth);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final history = await loadAllPages(
        (page) => _content.history(page: page),
      );
      final liked = await loadAllPages(
        (page) => _content.liked(page: page, rating: _rating),
      );
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
              subtitle: AppStrings.t('library.subtitle'),
              action: AppStrings.t('library.playlists'),
              onAction: () => context.push('/playlists'),
            ),
          ),
          TabBar(
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
                        shape: const StadiumBorder(),
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
                              ? AppStrings.t('library.historyDescription')
                              : AppStrings.t('library.likedDescription'),
                          compact: true,
                          accent: AppColors.violet,
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: items.length,
                      itemBuilder: (_, index) {
                        final item = items[index];
                        return VideoCardTile(
                          video: item,
                          progress: _tab == 0 ? item.progress : null,
                          trailing: _tab == 1
                              ? const SizedBox(width: 28)
                              : null,
                        );
                      },
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
