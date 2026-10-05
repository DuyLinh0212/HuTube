import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'content_models.dart';
import 'content_service.dart';
import 'video_card.dart';

/// Mobile equivalent of the Web User home feed sections.
///
/// The old mobile home rendered only one paginated list. The Web User home
/// separates recommendations, followed channels, popular videos and a random
/// discovery rail, so the mobile screen keeps those same content intents while
/// adapting the layout to touch scrolling.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ContentService _content = ContentService(widget.auth);

  List<VideoCard> _recommendations = const [];
  List<VideoCard> _subscriptions = const [];
  List<VideoCard> _popular = const [];
  List<VideoCard> _random = const [];
  bool _loading = true;
  String? _error;

  List<VideoCard> get _allVideos => [
    ..._recommendations,
    ..._subscriptions,
    ..._popular,
    ..._random,
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final recommendations = await _content.feed(
        explore: false,
        page: 1,
        pageSize: 20,
        sort: 'popular',
      );
      if (!mounted) return;

      final seen = <String>{};
      final recommendedItems = _unique(recommendations.items, seen);
      var subscriptions = <VideoCard>[];
      if (widget.auth.authenticated) {
        try {
          final result = await _content.subscriptionsFeed(
            page: 1,
            pageSize: 12,
          );
          subscriptions = _unique(result.items, seen);
        } catch (_) {
          // A missing subscription feed should not hide public home content.
        }
      }

      var popular = <VideoCard>[];
      try {
        final result = await _content.feed(
          explore: true,
          page: 1,
          pageSize: 20,
          sort: 'popular',
        );
        popular = _unique(result.items, seen);
      } catch (_) {}

      var random = <VideoCard>[];
      try {
        final result = await _content.feed(
          explore: true,
          page: 1,
          pageSize: 20,
          sort: 'random',
        );
        random = _unique(result.items, seen);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _recommendations = recommendedItems;
        _subscriptions = subscriptions;
        _popular = popular;
        _random = random;
        _loading = false;
      });
    } on ApiFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppStrings.apiError(error, fallback: 'feed.loadError');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppStrings.t('feed.loadError');
      });
    }
  }

  List<VideoCard> _unique(List<VideoCard> items, Set<String> seen) =>
      items.where((item) => item.id.isNotEmpty && seen.add(item.id)).toList();

  @override
  Widget build(BuildContext context) {
    if (_loading && _allVideos.isEmpty) return const _HomeLoading();
    if (_error != null && _allVideos.isEmpty) {
      return _HomeFailure(message: _error!, onRetry: _load);
    }

    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
        children: [
          if (_recommendations.isNotEmpty)
            _HomeSection(
              title: AppStrings.t('home.forYouTitle'),
              videos: _recommendations,
            ),
          if (_subscriptions.isNotEmpty) ...[
            const SizedBox(height: 26),
            _HomeSection(
              title: AppStrings.t('home.followingTitle'),
              kicker: AppStrings.t('home.followingKicker'),
              videos: _subscriptions,
              horizontal: true,
            ),
          ],
          if (_popular.isNotEmpty) ...[
            const SizedBox(height: 26),
            _HomeSection(
              title: AppStrings.t('home.popularTitle'),
              kicker: AppStrings.t('home.popularKicker'),
              videos: _popular,
            ),
          ],
          if (_random.isNotEmpty) ...[
            const SizedBox(height: 26),
            _HomeSection(
              title: AppStrings.t('home.randomTitle'),
              kicker: AppStrings.t('home.randomKicker'),
              videos: _random,
            ),
          ],
          if (_allVideos.isEmpty)
            HuTubeStateView(
              icon: Icons.video_library_outlined,
              title: AppStrings.t('home.empty'),
              message: AppStrings.t('feed.homeDescription'),
              compact: true,
            ),
        ],
      ),
    );
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({
    this.title,
    this.kicker,
    required this.videos,
    this.horizontal = false,
  });

  final String? title;
  final String? kicker;
  final List<VideoCard> videos;
  final bool horizontal;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (title != null) ...[
        if (kicker != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              kicker!,
              style: TextStyle(
                color: AppColors.textMutedFor(context),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
        Text(
          title!,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -.45,
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (horizontal)
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: videos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) =>
                _HomeCompactCard(video: videos[index]),
          ),
        )
      else
        ...videos.map(
          (video) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: VideoCardTile(video: video),
          ),
        ),
    ],
  );
}

class _HomeCompactCard extends StatelessWidget {
  const _HomeCompactCard({required this.video});

  final VideoCard video;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 224,
    child: InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () => context.push('/watch/${video.id}'),
      child: Ink(
        decoration: BoxDecoration(
          color: AppColors.surfaceFor(context),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppColors.borderFor(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(15),
              ),
              child: SizedBox(
                height: 126,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    video.thumbnailUrl?.startsWith('http') == true
                        ? Image.network(
                            video.thumbnailUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const _HomeThumbnailFallback(),
                          )
                        : const _HomeThumbnailFallback(),
                    if (video.isPromoted)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: HuTubePill(
                          label: AppStrings.t('home.promoted'),
                          icon: Icons.campaign_outlined,
                          color: AppColors.primaryPink,
                          textColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${video.channelName} · ${AppStrings.format('feed.views', {'count': AppStrings.number(video.views)})}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textMutedFor(context),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _HomeThumbnailFallback extends StatelessWidget {
  const _HomeThumbnailFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF371426), Color(0xFF171927)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Center(
      child: Icon(
        Icons.play_circle_fill_rounded,
        color: Colors.white70,
        size: 38,
      ),
    ),
  );
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
    children: [
      Container(width: 150, height: 22, color: AppColors.borderSubtle),
      const SizedBox(height: 14),
      for (var index = 0; index < 3; index++) ...[
        Container(
          height: 205,
          decoration: BoxDecoration(
            color: AppColors.borderSubtle,
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        if (index != 2) const SizedBox(height: 12),
      ],
    ],
  );
}

class _HomeFailure extends StatelessWidget {
  const _HomeFailure({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: HuTubeStateView(
      icon: Icons.cloud_off_rounded,
      title: message,
      message: AppStrings.t('common.checkConnection'),
      actionLabel: AppStrings.t('common.retry'),
      onAction: () => unawaited(onRetry()),
    ),
  );
}
