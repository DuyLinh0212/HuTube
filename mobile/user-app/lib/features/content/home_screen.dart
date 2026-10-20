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

  int _generation = 0;
  late int _sessionGeneration;
  late bool _authenticated;

  bool get _hasVideos =>
      _recommendations.isNotEmpty ||
      _subscriptions.isNotEmpty ||
      _popular.isNotEmpty ||
      _random.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _sessionGeneration = widget.auth.sessionGeneration;
    _authenticated = widget.auth.authenticated;
    widget.auth.addListener(_identityChanged);
    unawaited(_load());
  }

  void _identityChanged() {
    if (_sessionGeneration == widget.auth.sessionGeneration &&
        _authenticated == widget.auth.authenticated) {
      return;
    }
    _sessionGeneration = widget.auth.sessionGeneration;
    _authenticated = widget.auth.authenticated;
    _recommendations = _subscriptions = _popular = _random = const [];
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.auth.removeListener(_identityChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final session = widget.auth.sessionGeneration;
    final authenticated = widget.auth.authenticated;
    var pending = authenticated ? 4 : 3;
    final sections = <int, List<VideoCard>>{};
    String? failure;
    setState(() {
      _loading = true;
      _error = null;
    });

    Future<void> fetch(int index, Future<PageResult<VideoCard>> request) async {
      try {
        sections[index] = (await request).items;
      } catch (error) {
        failure ??= error is ApiFailure
            ? AppStrings.apiError(error, fallback: 'feed.loadError')
            : AppStrings.t('feed.loadError');
      } finally {
        pending--;
        if (mounted &&
            generation == _generation &&
            session == widget.auth.sessionGeneration &&
            authenticated == widget.auth.authenticated) {
          // Keep deterministic section priority, regardless of response order.
          final seen = <String>{};
          setState(() {
            _recommendations = _unique(sections[0] ?? const [], seen);
            _subscriptions = _unique(sections[1] ?? const [], seen);
            _popular = _unique(sections[2] ?? const [], seen);
            _random = _unique(sections[3] ?? const [], seen);
            _loading = pending > 0;
            _error = pending == 0 ? failure : null;
          });
        }
      }
    }

    await Future.wait([
      fetch(0, _content.feed(explore: false, pageSize: 20, sort: 'popular')),
      if (authenticated) fetch(1, _content.subscriptionsFeed(pageSize: 12)),
      fetch(2, _content.feed(explore: true, pageSize: 20, sort: 'popular')),
      fetch(3, _content.feed(explore: true, pageSize: 20, sort: 'random')),
    ]);
  }

  List<VideoCard> _unique(List<VideoCard> items, Set<String> seen) =>
      items.where((item) => item.id.isNotEmpty && seen.add(item.id)).toList();

  @override
  Widget build(BuildContext context) {
    if (_loading && !_hasVideos) return const _HomeLoading();
    if (_error != null && !_hasVideos) {
      return _HomeFailure(message: _error!, onRetry: _load);
    }
    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
            sliver: SliverMainAxisGroup(
              slivers: [
                ..._section(context, _recommendations, 'home.forYouTitle'),
                ..._section(
                  context,
                  _subscriptions,
                  'home.followingTitle',
                  kicker: 'home.followingKicker',
                  horizontal: true,
                ),
                ..._section(
                  context,
                  _popular,
                  'home.popularTitle',
                  kicker: 'home.popularKicker',
                ),
                ..._section(
                  context,
                  _random,
                  'home.randomTitle',
                  kicker: 'home.randomKicker',
                ),
                if (!_hasVideos)
                  SliverToBoxAdapter(
                    child: HuTubeStateView(
                      icon: Icons.video_library_outlined,
                      title: AppStrings.t('home.empty'),
                      message: AppStrings.t('feed.homeDescription'),
                      compact: true,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _section(
    BuildContext context,
    List<VideoCard> videos,
    String title, {
    String? kicker,
    bool horizontal = false,
  }) {
    if (videos.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(
            top: identical(videos, _recommendations) ? 0 : 26,
            bottom: 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (kicker != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    AppStrings.t(kicker),
                    style: TextStyle(
                      color: AppColors.textMutedFor(context),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              Text(
                AppStrings.t(title),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.45,
                ),
              ),
            ],
          ),
        ),
      ),
      if (horizontal)
        SliverToBoxAdapter(
          child: SizedBox(
            height: 146 + MediaQuery.textScalerOf(context).scale(60),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: videos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, index) => _HomeCompactCard(video: videos[index]),
            ),
          ),
        )
      else
        SliverList.builder(
          itemCount: videos.length,
          itemBuilder: (_, index) => Padding(
            key: ValueKey(videos[index].id),
            padding: const EdgeInsets.only(bottom: 10),
            child: VideoCardTile(video: videos[index], auth: widget.auth),
          ),
        ),
    ];
  }
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
                            cacheWidth: 672,
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
