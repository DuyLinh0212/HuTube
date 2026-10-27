import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../../features/content/content_models.dart';
import '../../features/content/content_service.dart';
import '../../features/content/video_card.dart';
import '../../features/moderation/report_dialog.dart';
import '../../features/moderation/moderation_screen.dart';
import '../../features/playlists/playlist_service.dart';
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
  late ChannelService _channelService;
  late final TabController _tabController;

  bool _loading = true;
  String? _error;
  String? _errorReference;
  bool _videosLoading = false, _playlistsLoading = false;
  bool _subscriptionLoading = false, _subscriptionFailed = false;
  bool _videosFailed = false, _playlistsFailed = false;
  late int _sessionGeneration;
  late bool _authenticated;
  ChannelDetail? _channel;
  bool _isSubscribed = false;
  bool _notificationsEnabled = false;
  bool _subscriptionBusy = false;
  int _subscriberCount = 0;
  bool _showFullDesc = false;
  List<VideoCard> _videos = const [];
  VideoCard? _trailerVideo;
  int _videoPage = 1;
  int _videoTotal = 0;
  int _loadGeneration = 0;
  bool _loadingMore = false;
  List<PlaylistSummary> _playlists = const [];

  bool get _contentUnavailable =>
      _channel != null && _channel!.status.toLowerCase() != 'active';

  @override
  void initState() {
    super.initState();
    _channelService = ChannelService(widget.auth);
    _tabController = TabController(length: 4, vsync: this);
    _sessionGeneration = widget.auth.sessionGeneration;
    _authenticated = widget.auth.authenticated;
    widget.auth.addListener(_identityChanged);
    _load();
  }

  void _identityChanged() {
    if (_sessionGeneration == widget.auth.sessionGeneration &&
        _authenticated == widget.auth.authenticated) {
      return;
    }
    _sessionGeneration = widget.auth.sessionGeneration;
    _authenticated = widget.auth.authenticated;
    _load();
  }

  @override
  void didUpdateWidget(covariant ChannelScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth) {
      oldWidget.auth.removeListener(_identityChanged);
      _channelService = ChannelService(widget.auth);
      widget.auth.addListener(_identityChanged);
      _sessionGeneration = widget.auth.sessionGeneration;
      _authenticated = widget.auth.authenticated;
    }
    if (oldWidget.channelOrHandle != widget.channelOrHandle ||
        oldWidget.auth != widget.auth) {
      _load();
    }
  }

  @override
  void dispose() {
    widget.auth.removeListener(_identityChanged);
    _tabController.dispose();
    super.dispose();
  }

  bool _current(int generation, int session) =>
      mounted &&
      generation == _loadGeneration &&
      session == widget.auth.sessionGeneration;

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final session = widget.auth.sessionGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _errorReference = null;
      _channel = null;
      _videos = [];
      _playlists = [];
      _trailerVideo = null;
      _loadingMore = false;
      _videosFailed = _playlistsFailed = false;
      _videosLoading = _playlistsLoading = false;
      _subscriptionLoading = false;
      _subscriptionFailed = false;
      _subscriptionBusy = false;
    });
    try {
      final detail = await _channelService.getChannel(widget.channelOrHandle);
      if (!_current(generation, session)) return;
      setState(() {
        _channel = detail;
        _isSubscribed = detail.isSubscribed;
        _notificationsEnabled = false;
        _subscriberCount = detail.subscriberCount;
        _videoPage = 1;
        _videoTotal = 0;
        _loading = false;
      });
      if (_contentUnavailable) return;
      // Render the channel as soon as its profile is ready. Secondary failures
      // belong to their own sections, just as on user-web.
      unawaited(_loadVideos(detail, generation, session));
      unawaited(_loadPlaylists(detail, generation, session));
      unawaited(_loadSubscription(detail, generation, session));
      unawaited(_loadTrailer(detail, generation));
    } on ApiFailure catch (error) {
      if (!_current(generation, session)) return;
      setState(() {
        _error = error.status == 404
            ? AppStrings.t('channel.notFound')
            : AppStrings.apiError(error, fallback: 'channel.loadError');
        _errorReference = [
          if (error.status > 0) 'HTTP ${error.status}',
          error.code,
          if (error.traceId != null) error.traceId!,
        ].join(' · ');
        _loading = false;
      });
    } catch (_) {
      if (!_current(generation, session)) return;
      setState(() {
        _error = AppStrings.t('channel.loadError');
        _errorReference = 'CHANNEL_RESPONSE_INVALID';
        _loading = false;
      });
    }
  }

  Future<void> _loadVideos(
    ChannelDetail channel,
    int generation,
    int session,
  ) async {
    if (!_current(generation, session) || _videosLoading) return;
    setState(() {
      _videosLoading = true;
      _videosFailed = false;
    });
    try {
      final page = await ContentService(widget.auth).searchVideos(
        query: '',
        channelId: channel.id,
        page: 1,
        pageSize: 30,
        sort: 'newest',
      );
      if (!_current(generation, session)) return;
      setState(() {
        _videos = page.items;
        _videoPage = page.page;
        _videoTotal = page.total;
      });
    } catch (_) {
      if (_current(generation, session)) setState(() => _videosFailed = true);
    } finally {
      if (_current(generation, session)) setState(() => _videosLoading = false);
    }
  }

  Future<void> _loadPlaylists(
    ChannelDetail channel,
    int generation,
    int session,
  ) async {
    if (!_current(generation, session) || _playlistsLoading) return;
    setState(() {
      _playlistsLoading = true;
      _playlistsFailed = false;
    });
    try {
      // The channel page is public, including when its owner is viewing it.
      // Private library playlists belong to the account / Studio screens.
      final lists = await PlaylistService(
        widget.auth,
      ).publicByChannel(channel.id);
      if (_current(generation, session)) setState(() => _playlists = lists);
    } catch (_) {
      if (_current(generation, session)) {
        setState(() => _playlistsFailed = true);
      }
    } finally {
      if (_current(generation, session)) {
        setState(() => _playlistsLoading = false);
      }
    }
  }

  Future<void> _loadSubscription(
    ChannelDetail channel,
    int generation,
    int session,
  ) async {
    if (!_current(generation, session)) return;
    if (!widget.auth.authenticated || channel.isOwner) {
      setState(() {
        _subscriptionLoading = false;
        _subscriptionFailed = false;
      });
      return;
    }
    setState(() {
      _subscriptionLoading = true;
      _subscriptionFailed = false;
    });
    try {
      final status = await _channelService.getSubscriptionStatus(channel.id);
      if (!_current(generation, session)) return;
      setState(() {
        _isSubscribed = status?['status'] == 'active';
        _notificationsEnabled =
            _isSubscribed && status?['notificationsEnabled'] == true;
      });
    } catch (_) {
      if (_current(generation, session)) {
        setState(() => _subscriptionFailed = true);
      }
    } finally {
      if (_current(generation, session)) {
        setState(() => _subscriptionLoading = false);
      }
    }
  }

  Widget _sectionNotice(String key, VoidCallback retry) => HuTubeNotice(
    message: AppStrings.t(key),
    actionLabel: AppStrings.t('channel.retry'),
    onAction: retry,
  );

  Widget _videosNotice(ChannelDetail c) => _sectionNotice(
    'channel.videosLoadError',
    () => _loadVideos(c, _loadGeneration, widget.auth.sessionGeneration),
  );

  Future<void> _loadTrailer(ChannelDetail detail, int generation) async {
    final id = _parseTrailerVideoId(detail.settings);
    if (id == null || _videos.any((video) => video.id == id)) return;
    try {
      final video = await ContentService(widget.auth).detail(id);
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _trailerVideo = video);
    } catch (_) {
      /* Unavailable trailers do not block the channel. */
    }
  }

  Future<void> _loadMoreVideos() async {
    final channel = _channel;
    if (channel == null || _loadingMore || _videos.length >= _videoTotal) {
      return;
    }
    final generation = _loadGeneration;
    setState(() => _loadingMore = true);
    try {
      final page = await ContentService(widget.auth).searchVideos(
        query: '',
        channelId: channel.id,
        page: _videoPage + 1,
        pageSize: 30,
        sort: 'newest',
      );
      if (!mounted || generation != _loadGeneration) return;
      final seen = _videos.map((item) => item.id).toSet();
      setState(() {
        _videos = [
          ..._videos,
          ...page.items.where((item) => seen.add(item.id)),
        ];
        _videoPage = page.page;
        _videoTotal = page.total;
      });
    } catch (_) {
      /* Keep loaded videos and the retry button. */
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _toggleSubscribe() async {
    if (_subscriptionBusy ||
        _subscriptionLoading ||
        _subscriptionFailed ||
        _channel == null ||
        _contentUnavailable) {
      return;
    }
    if (!widget.auth.authenticated) {
      context.go('/auth');
      return;
    }
    setState(() => _subscriptionBusy = true);
    try {
      if (_isSubscribed) {
        await _channelService.unsubscribe(_channel!.id);
        if (mounted) {
          setState(() {
            _isSubscribed = false;
            _notificationsEnabled = false;
            _subscriberCount = (_subscriberCount - 1).clamp(0, 1 << 31);
          });
        }
      } else {
        final result = await _channelService.subscribe(_channel!.id);
        if (mounted) {
          setState(() {
            _isSubscribed = true;
            _notificationsEnabled = result['notificationsEnabled'] == true;
            _subscriberCount += 1;
          });
        }
      }
      if (mounted) {
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
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.apiError(error, fallback: 'common.serverError'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _subscriptionBusy = false);
    }
  }

  Future<void> _toggleNotifications() async {
    if (_contentUnavailable) return;
    if (!widget.auth.authenticated) {
      context.go('/auth');
      return;
    }
    if (_channel == null || !_isSubscribed || _subscriptionBusy) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.t('channel.subscribeBeforeNotifications')),
        ),
      );
      return;
    }
    setState(() => _subscriptionBusy = true);
    try {
      final result = await _channelService.updateSubscriptionNotifications(
        _channel!.id,
        !_notificationsEnabled,
      );
      if (mounted) {
        setState(
          () => _notificationsEnabled = result['notificationsEnabled'] == true,
        );
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.apiError(error, fallback: 'common.serverError'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _subscriptionBusy = false);
    }
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
                if (_errorReference != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    _errorReference!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textMutedFor(context),
                    ),
                  ),
                ],
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
          if (!c.isOwner)
            IconButton(
              tooltip: AppStrings.t('channel.reportAction'),
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => showContentReportDialog(
                context,
                auth: widget.auth,
                targetType: 'channel',
                targetId: c.id,
              ),
            ),
          IconButton(
            tooltip: AppStrings.t('common.search'),
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => Share.share('Dalitu · ${c.name}\n@${c.handle}'),
          ),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_contentUnavailable)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _channelStatusNotice(c),
                  ),
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
                            _socialLinksChips(c),
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
                              child: ListTile(
                                key: const ValueKey('channel-manage-action'),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                leading: const Icon(
                                  Icons.tune_rounded,
                                  size: 22,
                                ),
                                title: Text(
                                  AppStrings.t('channel.manage'),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 20,
                                ),
                                onTap: () async {
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
                                onPressed:
                                    (_contentUnavailable ||
                                        _subscriptionBusy ||
                                        _subscriptionLoading ||
                                        _subscriptionFailed)
                                    ? null
                                    : _toggleSubscribe,
                                child: Text(
                                  _isSubscribed
                                      ? '${AppStrings.t('channel.subscribed')} ✓'
                                      : AppStrings.t('channel.subscribe'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              onPressed:
                                  _contentUnavailable ||
                                      _subscriptionLoading ||
                                      _subscriptionFailed
                                  ? null
                                  : _toggleNotifications,
                              tooltip: _notificationsEnabled
                                  ? AppStrings.t('channel.notificationsOff')
                                  : AppStrings.t('channel.notificationsOn'),
                              icon: Icon(
                                _notificationsEnabled
                                    ? Icons.notifications_active_rounded
                                    : Icons.notifications_none_rounded,
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
          if (_subscriptionFailed)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _sectionNotice(
                  'channel.subscriptionLoadError',
                  () => _loadSubscription(
                    c,
                    _loadGeneration,
                    widget.auth.sessionGeneration,
                  ),
                ),
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

  Widget _channelStatusNotice(ChannelDetail channel) {
    final colors = Theme.of(context).colorScheme;
    final suspended = channel.status.toLowerCase() == 'suspended';
    return Semantics(
      liveRegion: true,
      child: HuTubeSurface(
        key: const ValueKey('channel-status-notice'),
        color: colors.errorContainer,
        border: BorderSide.none,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.pause_circle_outline_rounded,
                  color: colors.onErrorContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppStrings.t(
                      suspended
                          ? 'channel.suspendedTitle'
                          : 'channel.inactiveTitle',
                    ),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.t('channel.contentUnavailable'),
              style: TextStyle(color: colors.onErrorContainer, height: 1.5),
            ),
            if (channel.isOwner) ...[
              const SizedBox(height: 8),
              Text(
                channel.statusReason?.trim().isNotEmpty == true
                    ? AppStrings.format('channel.suspensionReason', {
                        'reason': channel.statusReason!.trim(),
                      })
                    : AppStrings.t('channel.suspensionReasonMissing'),
                style: TextStyle(color: colors.onErrorContainer, height: 1.5),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: Text(AppStrings.t('moderation.title')),
                        ),
                        body: ModerationScreen(
                          auth: widget.auth,
                          channel: channel,
                        ),
                      ),
                    ),
                  );
                  if (mounted) _load();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.onErrorContainer,
                  side: BorderSide(
                    color: colors.onErrorContainer.withValues(alpha: .4),
                  ),
                ),
                icon: const Icon(Icons.policy_outlined, size: 18),
                label: Text(AppStrings.t('channel.statusAndAppeal')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _unavailableTab() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Icon(
        Icons.visibility_off_outlined,
        size: 32,
        color: AppColors.textMutedFor(context),
      ),
      const SizedBox(height: 12),
      Text(
        AppStrings.t('channel.contentUnavailable'),
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textMutedFor(context), height: 1.5),
      ),
    ],
  );

  Widget _homeTab(ChannelDetail c) {
    if (_contentUnavailable) return _unavailableTab();
    final trailerId = _parseTrailerVideoId(c.settings);
    VideoCard? trailerVideo;
    if (trailerId != null) {
      trailerVideo =
          _videos.where((v) => v.id == trailerId).firstOrNull ?? _trailerVideo;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (trailerVideo != null) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.violet.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.violet.withValues(alpha: .25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.violet,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'VIDEO GIỚI THIỆU',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        trailerVideo.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                VideoCardTile(video: trailerVideo),
              ],
            ),
          ),
        ],
        Text(
          AppStrings.t('channel.latestVideo'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        if (_videosLoading)
          const LinearProgressIndicator(minHeight: 2)
        else if (_videosFailed)
          _videosNotice(c)
        else if (_videos.isEmpty)
          Text(
            AppStrings.t('channel.noPublicVideos'),
            style: TextStyle(color: AppColors.textSecondaryFor(context)),
          )
        else
          for (final video in _videos.where((v) => v.id != trailerId).take(5))
            VideoCardTile(video: video),
      ],
    );
  }

  Widget _videosTab(ChannelDetail c) {
    if (_contentUnavailable) return _unavailableTab();
    if (_videosLoading || _videosFailed) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_videosLoading)
            const LinearProgressIndicator(minHeight: 2)
          else
            _videosNotice(c),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _videos.isEmpty
          ? [
              Text(
                AppStrings.t('channel.noPublicVideos'),
                style: TextStyle(color: AppColors.textSecondaryFor(context)),
              ),
            ]
          : [
              for (final video in _videos) VideoCardTile(video: video),
              if (_videos.length < _videoTotal)
                TextButton(
                  onPressed: _loadingMore ? null : _loadMoreVideos,
                  child: Text(AppStrings.t('notifications.loadMore')),
                ),
            ],
    );
  }

  Widget _playlistsTab() {
    if (_contentUnavailable) return _unavailableTab();
    if (_playlistsLoading || _playlistsFailed) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_playlistsLoading)
            const LinearProgressIndicator(minHeight: 2)
          else
            _sectionNotice(
              'channel.playlistsLoadError',
              () => _loadPlaylists(
                _channel!,
                _loadGeneration,
                widget.auth.sessionGeneration,
              ),
            ),
        ],
      );
    }
    if (_playlists.isNotEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _playlists.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final playlist = _playlists[index];
          return Card(
            child: ListTile(
              leading: const Icon(
                Icons.playlist_play_rounded,
                color: AppColors.primary,
              ),
              title: Text(
                playlist.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                AppStrings.format('channel.videoCount', {
                  'count': AppStrings.number(playlist.itemCount),
                }),
              ),
              onTap: () => context.push('/playlists/${playlist.id}'),
            ),
          );
        },
      );
    }
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
        if (c.contactEmail?.isNotEmpty == true)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.mail_outline_rounded),
            title: Text(AppStrings.t('channel.contactEmail')),
            subtitle: Text(c.contactEmail!),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: () => launchUrl(
              Uri(scheme: 'mailto', path: c.contactEmail),
              mode: LaunchMode.externalApplication,
            ),
          ),
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
        _socialLinksAbout(c),
      ],
    );
  }

  Widget _socialLinksChips(ChannelDetail c) {
    final links = _parseLinks(c.settings);
    if (links.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: links.map((l) {
            final platform = l['platform'] ?? 'website';
            final title = (l['title'] ?? '').isEmpty ? platform : l['title']!;
            final url = l['url']!;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                avatar: _platformIcon(platform),
                label: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  final uri = Uri.tryParse(url);
                  if (uri != null) {
                    try {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    } catch (_) {}
                  }
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _socialLinksAbout(ChannelDetail c) {
    final links = _parseLinks(c.settings);
    if (links.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 16),
        const Text(
          'Liên kết mạng xã hội',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        for (final link in links)
          InkWell(
            onTap: () async {
              final uri = Uri.tryParse(link['url'] ?? '');
              if (uri != null) {
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (_) {}
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  _platformIcon(link['platform'] ?? 'website'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          link['title'] ?? 'Liên kết',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          link['url'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.violet,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.open_in_new_rounded,
                    size: 16,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<Map<String, String>> _parseLinks(String? settings) {
    if (settings == null || settings.isEmpty) return const [];
    try {
      final json = jsonDecode(settings) as Map<String, dynamic>;
      final links = json['links'];
      if (links is List) {
        return links
            .whereType<Map>()
            .map(
              (l) => {
                'platform': '${l['platform'] ?? 'website'}',
                'title': '${l['title'] ?? ''}',
                'url': '${l['url'] ?? ''}',
              },
            )
            .where((l) => l['url']!.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  String? _parseTrailerVideoId(String? settings) {
    if (settings == null || settings.isEmpty) return null;
    try {
      final json = jsonDecode(settings) as Map<String, dynamic>;
      final id = json['trailerVideoId'];
      if (id is String && id.trim().isNotEmpty) return id.trim();
    } catch (_) {}
    return null;
  }

  Widget _platformIcon(String platform) {
    return switch (platform.toLowerCase()) {
      'facebook' => const Icon(Icons.facebook, size: 16, color: Colors.blue),
      'tiktok' => const Icon(
        Icons.music_note,
        size: 16,
        color: Colors.pinkAccent,
      ),
      'instagram' => const Icon(
        Icons.camera_alt,
        size: 16,
        color: Colors.purpleAccent,
      ),
      'twitter' => const Icon(
        Icons.alternate_email,
        size: 16,
        color: Colors.lightBlue,
      ),
      'youtube' => const Icon(
        Icons.play_circle_filled,
        size: 16,
        color: Colors.red,
      ),
      'discord' => const Icon(Icons.forum, size: 16, color: Colors.indigo),
      _ => const Icon(Icons.language, size: 16, color: Colors.teal),
    };
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
