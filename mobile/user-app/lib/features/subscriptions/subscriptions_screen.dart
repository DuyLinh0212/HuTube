import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../../channel/models/channel_models.dart';
import '../../channel/services/channel_service.dart';
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
  late final ChannelService _channelService = ChannelService(widget.auth);
  final _scroll = ScrollController();
  List<VideoCard> _videos = const [];
  List<SubscribedChannelResponse> _channels = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  int _page = 0;

  String _selectedFilter = 'Tất cả';
  String? _selectedChannelId;
  static const _filterOptions = ['Tất cả', 'Hôm nay', 'Video', 'Shorts', 'Trực tiếp'];

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

  Future<void> _selectChannel(String? channelId) async {
    if (_selectedChannelId == channelId) {
      channelId = null;
    }
    setState(() {
      _selectedChannelId = channelId;
      _videos = [];
      _page = 0;
      _hasMore = false;
      _loading = true;
      _error = null;
    });
    await _load(more: false);
  }

  Future<void> _load({bool more = false}) async {
    if (!widget.auth.authenticated) {
      if (mounted) setState(() => _loading = false);
      return;
    }

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
      if (!more && _channels.isEmpty) {
        final channels = await _channelService.getSubscribedChannels();
        if (mounted) setState(() => _channels = channels);
      }

      final PageResult<VideoCard> result;
      if (_selectedChannelId != null) {
        result = await _content.searchVideos(
          query: '',
          channelId: _selectedChannelId,
          sort: 'newest',
          page: requestedPage,
          pageSize: 20,
        );
      } else {
        result = await _content.subscriptionsFeed(page: requestedPage);
      }

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

  List<VideoCard> get _filteredVideos {
    var list = _videos;
    if (_selectedFilter == 'Shorts') {
      list = list.where((v) => v.duration <= 60).toList();
    } else if (_selectedFilter == 'Video') {
      list = list.where((v) => v.duration > 60).toList();
    } else if (_selectedFilter == 'Hôm nay') {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      list = list.where((v) {
        if (v.publishedAt == null) return false;
        return v.publishedAt!.isAfter(todayStart);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textPrimary;

    // Guest prompt if not logged in
    if (!widget.auth.authenticated) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F0F0F) : AppColors.background,
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF0F0F0F) : AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          title: Text(
            AppStrings.t('nav.subscriptions'),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.subscriptions_outlined,
                  size: 88,
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
                const SizedBox(height: 20),
                Text(
                  'Đừng bỏ lỡ video mới',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Đăng nhập để xem cập nhật mới nhất từ các kênh HuTube bạn yêu thích.',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? const Color(0xFFAAAAAA) : AppColors.textMuted,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.push('/auth'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryPink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text(
                    'Đăng nhập',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final videosToDisplay = _filteredVideos;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primaryPink,
        onRefresh: () => _load(more: false),
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // ================= 1. CHANNELS STORIES BAR (Image 3) =================
            if (_channels.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 94,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: _channels.length + 1,
                  separatorBuilder: (_, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    if (index == _channels.length) {
                      // "Tất cả" (All) button at the end
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          _selectChannel(null);
                        },
                        child: Container(
                          width: 64,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isDark ? const Color(0xFF272727) : AppColors.surfaceAlt,
                                  border: Border.all(
                                    color: isDark ? const Color(0xFF3F3F3F) : AppColors.borderSubtle,
                                  ),
                                ),
                                child: Icon(
                                  Icons.grid_view_rounded,
                                  size: 22,
                                  color: isDark ? Colors.white : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Tất cả',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? const Color(0xFF3EA6FF) : AppColors.primaryPink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final channel = _channels[index];
                    final isSelected = _selectedChannelId == channel.channelId;

                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        _selectChannel(channel.channelId);
                      },
                      onLongPress: () {
                        context.push('/channels/${channel.handle}');
                      },
                      child: Container(
                        width: 66,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: isSelected
                                        ? Border.all(color: AppColors.primaryPink, width: 2)
                                        : null,
                                  ),
                                  child: HuTubeAvatar(
                                    url: channel.avatarUrl,
                                    label: channel.name,
                                    radius: 23,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              channel.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected
                                    ? (isDark ? Colors.white : AppColors.textPrimary)
                                    : (isDark ? const Color(0xFFAAAAAA) : AppColors.textMuted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
            ],

            // ================= 2. FILTER CHIPS ROW (Image 3) =================
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: _filterOptions.map((filter) {
                  final active = _selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        filter,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: active ? FontWeight.bold : FontWeight.w500,
                          color: active
                              ? (isDark ? Colors.black : Colors.white)
                              : (isDark ? Colors.white : AppColors.textPrimary),
                        ),
                      ),
                      selected: active,
                      showCheckmark: false,
                      shape: const StadiumBorder(),
                      onSelected: (_) {
                        setState(() => _selectedFilter = filter);
                      },
                      backgroundColor: isDark ? const Color(0xFF272727) : AppColors.surfaceAlt,
                      selectedColor: isDark ? Colors.white : AppColors.ink,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                  );
                }).toList(),
              ),
            ),

            // ================= 2.1 SELECTED CHANNEL CARD =================
            if (_selectedChannelId != null) ...[
              () {
                final selectedChannel = _channels.cast<SubscribedChannelResponse?>().firstWhere(
                  (c) => c?.channelId == _selectedChannelId,
                  orElse: () => null,
                );
                if (selectedChannel == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.push('/channels/${selectedChannel.handle}'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? const Color(0xFF333333) : AppColors.borderSubtle,
                        ),
                      ),
                      child: Row(
                        children: [
                          HuTubeAvatar(
                            url: selectedChannel.avatarUrl,
                            label: selectedChannel.name,
                            radius: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedChannel.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                Text(
                                  '@${selectedChannel.handle}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white60 : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            AppStrings.t('channel.view'),
                            style: TextStyle(
                              color: isDark ? const Color(0xFF3EA6FF) : AppColors.primaryPink,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: isDark ? const Color(0xFF3EA6FF) : AppColors.primaryPink,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }(),
            ],

            // ================= 3. SECTION TITLE =================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Text(
                'Phù hợp nhất',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),

            // ================= 4. CONTENT / VIDEOS =================
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator(color: AppColors.primaryPink)),
              )
            else if (_error != null)
              HuTubeStateView(
                icon: Icons.wifi_off_rounded,
                title: _error!,
                message: AppStrings.t('common.networkError'),
                actionLabel: AppStrings.t('common.retry'),
                onAction: _load,
                compact: true,
                accent: AppColors.primaryPink,
              )
            else if (videosToDisplay.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
                child: HuTubeStateView(
                  icon: Icons.subscriptions_outlined,
                  title: AppStrings.t('subscriptions.noVideos'),
                  message: _selectedChannelId != null
                      ? 'Kênh này hiện chưa có video mới.'
                      : AppStrings.t('subscriptions.noVideosDescription'),
                  actionLabel: AppStrings.t('subscriptions.exploreVideos'),
                  onAction: () => context.go('/explore'),
                  compact: true,
                  accent: AppColors.primaryPink,
                ),
              )
            else ...[
              for (final video in videosToDisplay)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: VideoCardTile(video: video),
                ),
              if (_loadingMore)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primaryPink),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
