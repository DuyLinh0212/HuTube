import 'package:flutter/material.dart';
import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../models/channel_models.dart';
import '../services/channel_service.dart';
import 'channel_settings_screen.dart';

class ChannelScreen extends StatefulWidget {
  const ChannelScreen({
    super.key,
    required this.auth,
    required this.channelOrHandle,
  });

  final AuthController auth;
  final String channelOrHandle;

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen>
    with SingleTickerProviderStateMixin {
  late final ChannelService _channelService;
  late final TabController _tabController;

  bool _loading = true;
  String? _error;
  ChannelDetail? _channel;
  bool _isSubscribed = false;
  int _subscriberCount = 0;
  bool _showFullDesc = false;

  @override
  void initState() {
    super.initState();
    _channelService = ChannelService(widget.auth);
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final detail = await _channelService.getChannel(widget.channelOrHandle);
      if (mounted) {
        setState(() {
          _channel = detail;
          _isSubscribed = detail.isSubscribed;
          _subscriberCount = detail.subscriberCount;
          _loading = false;
        });
      }
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = AppStrings.apiError(e, fallback: 'common.error');
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppStrings.t('common.serverError');
          _loading = false;
        });
      }
    }
  }

  void _toggleSubscribe() {
    setState(() {
      _isSubscribed = !_isSubscribed;
      _subscriberCount += _isSubscribed ? 1 : -1;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isSubscribed
              ? AppStrings.t('channel.subscribedToast')
              : AppStrings.t('channel.unsubscribedToast'),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(AppStrings.t('channel.title'))),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primaryPink),
        ),
      );
    }

    if (_error != null || _channel == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppStrings.t('channel.title'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppColors.dangerFor(context),
                ),
                const SizedBox(height: 12),
                Text(
                  _error ?? AppStrings.t('channel.notFound'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _load,
                  child: Text(AppStrings.t('channel.retry')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final c = _channel!;

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppStrings.t('channel.copied')),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Banner
                Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: c.bannerUrl == null
                        ? const LinearGradient(
                            colors: [
                              Color(0xFF33101E),
                              Color(0xFF1E1020),
                              Color(0xFF10121E),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    image: c.bannerUrl != null
                        ? DecorationImage(
                            image: NetworkImage(c.bannerUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: c.bannerUrl == null
                      ? Center(
                          child: Text(
                            c.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(color: Colors.black26, blurRadius: 4),
                              ],
                            ),
                          ),
                        )
                      : null,
                ),

                // Channel Info Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: AppColors.primaryPink.withValues(
                          alpha: 0.15,
                        ),
                        backgroundImage: c.avatarUrl != null
                            ? NetworkImage(c.avatarUrl!)
                            : null,
                        child: c.avatarUrl == null
                            ? Text(
                                c.name.isNotEmpty
                                    ? c.name[0].toUpperCase()
                                    : 'C',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryPink,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    c.name,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimaryFor(context),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.check_circle,
                                  size: 16,
                                  color: AppColors.primaryPink,
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '@${c.handle} · ${AppStrings.format('channel.stats', {'subscribers': AppStrings.number(_subscriberCount), 'videos': AppStrings.number(c.videoCount)})}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondaryFor(context),
                              ),
                            ),
                            if (c.description != null &&
                                c.description!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: () => setState(
                                  () => _showFullDesc = !_showFullDesc,
                                ),
                                child: Text(
                                  c.description!,
                                  maxLines: _showFullDesc ? 10 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textPrimaryFor(context),
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Action Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: c.isOwner
                      ? Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primaryPink
                                      .withValues(alpha: 0.15),
                                  foregroundColor: AppColors.primaryPink,
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.tune_rounded, size: 18),
                                label: Text(AppStrings.t('channel.manage')),
                                onPressed: () async {
                                  final result = await Navigator.of(context)
                                      .push<bool>(
                                        MaterialPageRoute(
                                          builder: (_) => ChannelSettingsScreen(
                                            auth: widget.auth,
                                            channel: c,
                                          ),
                                        ),
                                      );
                                  if (result == true) _load();
                                },
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _isSubscribed
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest
                                      : AppColors.primaryPink,
                                  foregroundColor: _isSubscribed
                                      ? AppColors.textPrimaryFor(context)
                                      : Colors.white,
                                  elevation: 0,
                                ),
                                onPressed: _toggleSubscribe,
                                child: Text(
                                  _isSubscribed
                                      ? '${AppStrings.t('channel.subscribed')} ✓'
                                      : AppStrings.t('channel.subscribe'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              onPressed: () {},
                              icon: const Icon(
                                Icons.notifications_none_rounded,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                foregroundColor: AppColors.textPrimaryFor(
                                  context,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverAppBarDelegate(
              TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primaryPink,
                labelColor: AppColors.primaryPink,
                unselectedLabelColor: AppColors.textSecondaryFor(context),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                tabs: [
                  Tab(text: AppStrings.t('channel.home')),
                  Tab(text: AppStrings.t('channel.videos')),
                  Tab(text: AppStrings.t('channel.playlists')),
                  Tab(text: AppStrings.t('channel.about')),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [_homeTab(c), _videosTab(c), _playlistsTab(), _aboutTab(c)],
        ),
      ),
    );
  }

  Widget _homeTab(ChannelDetail c) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          AppStrings.t('channel.latestVideo'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        _videoCard(
          title: AppStrings.format('channel.welcomeVideo', {'name': c.name}),
          views: AppStrings.format('channel.viewCount', {
            'count': AppStrings.number(c.viewCount),
          }),
          duration: '04:15',
          date: AppStrings.t('channel.recent'),
        ),
      ],
    );
  }

  Widget _videosTab(ChannelDetail c) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _videoCard(
          title: AppStrings.format('channel.introVideo', {'name': c.name}),
          views: AppStrings.format('channel.viewCount', {'count': '1.2K'}),
          duration: '10:45',
          date: AppStrings.format('channel.daysAgo', {'count': '3'}),
        ),
        const SizedBox(height: 16),
        _videoCard(
          title: AppStrings.t('channel.tutorialVideo'),
          views: AppStrings.format('channel.viewCount', {'count': '5.8K'}),
          duration: '15:20',
          date: AppStrings.t('channel.weekAgo'),
        ),
      ],
    );
  }

  Widget _playlistsTab() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.playlist_play_rounded,
            size: 64,
            color: AppColors.textMutedFor(context),
          ),
          SizedBox(height: 8),
          Text(
            AppStrings.t('channel.noPlaylists'),
            style: TextStyle(color: AppColors.textSecondaryFor(context)),
          ),
        ],
      ),
    );
  }

  Widget _aboutTab(ChannelDetail c) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          AppStrings.t('channel.description'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          c.description != null && c.description!.isNotEmpty
              ? c.description!
              : AppStrings.t('channel.descriptionEmptyLong'),
          style: TextStyle(
            color: AppColors.textSecondaryFor(context),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        Text(
          AppStrings.t('channel.detailedInfo'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        _aboutRow(
          Icons.link,
          AppStrings.format('channel.channelUrl', {'handle': c.handle}),
        ),
        _aboutRow(
          Icons.people_outline,
          AppStrings.format('channel.subscriberCount', {
            'count': AppStrings.number(_subscriberCount),
          }),
        ),
        _aboutRow(
          Icons.video_library_outlined,
          AppStrings.format('channel.uploadedVideos', {
            'count': AppStrings.number(c.videoCount),
          }),
        ),
        _aboutRow(
          Icons.visibility_outlined,
          AppStrings.format('channel.totalViews', {
            'count': AppStrings.number(c.viewCount),
          }),
        ),
        _aboutRow(
          Icons.calendar_today_outlined,
          AppStrings.format('channel.joined', {
            'date': _formatDate(c.createdAt),
          }),
        ),
      ],
    );
  }

  Widget _aboutRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondaryFor(context)),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _videoCard({
    required String title,
    required String views,
    required String duration,
    required String date,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceFor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderFor(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                height: 160,
                width: double.infinity,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    size: 50,
                    color: AppColors.primaryPink,
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(190),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    duration,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textPrimaryFor(context),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$views · $date',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String raw) {
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    return AppStrings.date(d);
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);
  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: AppColors.surfaceFor(context), child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}
