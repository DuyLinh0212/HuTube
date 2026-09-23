import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../content/content_models.dart';
import '../content/content_service.dart';
import '../content/video_card.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  late final ContentService _content = ContentService(widget.auth);
  final _scroll = ScrollController();
  List<VideoCard> _videos = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadMoreIfNeeded);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (_loadingMore || (more && !_hasMore)) return;
    final requestedPage = more ? _page + 1 : 1;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final result = await _content.subscriptionsFeed(page: requestedPage);
      if (!mounted) return;
      setState(() {
        _videos = more ? [..._videos, ...result.items] : result.items;
        _page = result.page;
        _hasMore = result.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = AppStrings.apiError(error, fallback: 'feed.loadError');
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppStrings.t('common.networkError');
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _loadMoreIfNeeded() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 400 && _hasMore) {
      _load(more: true);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text(
          AppStrings.t('nav.subscriptions'),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Video mới từ những kênh bạn đang theo dõi.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        HuTubeSurface(
          color: AppColors.violetContainerFor(context),
          border: BorderSide(color: AppColors.violet.withValues(alpha: .12)),
          child: Row(
            children: [
              const Icon(Icons.subscriptions_rounded, color: AppColors.violet),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Theo dõi kênh để nhận video mới ngay tại đây.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Khám phá kênh',
                onPressed: () => context.go('/explore'),
                icon: const Icon(Icons.explore_outlined),
              ),
            ],
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(36),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          HuTubeStateView(
            icon: Icons.wifi_off_rounded,
            title: _error!,
            message: AppStrings.t('common.networkError'),
            actionLabel: AppStrings.t('common.retry'),
            onAction: _load,
            compact: true,
            accent: AppColors.violet,
          )
        else if (_videos.isEmpty)
          HuTubeStateView(
            icon: Icons.subscriptions_outlined,
            title: 'Chưa có video mới',
            message: 'Khám phá và theo dõi kênh để xem video mới ở đây.',
            actionLabel: 'Khám phá video',
            onAction: () => context.go('/explore'),
            compact: true,
            accent: AppColors.violet,
          )
        else ...[
          const SizedBox(height: 18),
          for (final video in _videos)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: VideoCardTile(video: video),
            ),
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ],
    ),
  );
}
