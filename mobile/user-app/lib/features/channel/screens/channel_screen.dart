import 'package:flutter/material.dart';
import '../../../auth.dart';
import '../../../core/theme/app_theme.dart';
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
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Không thể tải thông tin kênh.';
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
          _isSubscribed ? 'Đã đăng ký kênh' : 'Đã hủy đăng ký kênh',
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
        appBar: AppBar(title: const Text('Kênh')),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_error != null || _channel == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kênh')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppColors.danger,
                ),
                const SizedBox(height: 12),
                Text(
                  _error ?? 'Kênh không tồn tại hoặc đã bị xóa.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: const Text('Thử lại')),
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
                const SnackBar(
                  content: Text('Đã sao chép liên kết kênh vào bộ nhớ tạm'),
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
                        ? AppColors.primaryGradient
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
                        backgroundColor: AppColors.primaryLight,
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
                                  color: AppColors.primary,
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
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.check_circle,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '@${c.handle} · $_subscriberCount người đăng ký · ${c.videoCount} video',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
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
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textPrimary,
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
                                  backgroundColor: AppColors.primaryLight,
                                  foregroundColor: AppColors.primary,
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.tune_rounded, size: 18),
                                label: const Text('Quản lý kênh & Cài đặt'),
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
                                      ? const Color(0xFFF3F4F6)
                                      : AppColors.primary,
                                  foregroundColor: _isSubscribed
                                      ? AppColors.textPrimary
                                      : Colors.white,
                                  elevation: 0,
                                ),
                                onPressed: _toggleSubscribe,
                                child: Text(
                                  _isSubscribed ? 'Đã đăng ký ✓' : 'Đăng ký',
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
                                backgroundColor: const Color(0xFFF3F4F6),
                                foregroundColor: AppColors.textPrimary,
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
                indicatorColor: AppColors.primary,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                tabs: const [
                  Tab(text: 'TRANG CHỦ'),
                  Tab(text: 'VIDEO'),
                  Tab(text: 'PLAYLIST'),
                  Tab(text: 'GIỚI THIỆU'),
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
        const Text(
          'Video mới nhất',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        _videoCard(
          title: 'Chào mừng bạn đến với kênh ${c.name} trên HuTube!',
          views: '${c.viewCount} lượt xem',
          duration: '04:15',
          date: 'Gần đây',
        ),
      ],
    );
  }

  Widget _videosTab(ChannelDetail c) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _videoCard(
          title: 'Giới thiệu nội dung và định hướng kênh ${c.name}',
          views: '1.2K lượt xem',
          duration: '10:45',
          date: '3 ngày trước',
        ),
        const SizedBox(height: 16),
        _videoCard(
          title: 'Hướng dẫn sử dụng nền tảng video HuTube toàn tập',
          views: '5.8K lượt xem',
          duration: '15:20',
          date: '1 tuần trước',
        ),
      ],
    );
  }

  Widget _playlistsTab() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.playlist_play_rounded, size: 64, color: AppColors.border),
          SizedBox(height: 8),
          Text(
            'Chưa có danh sách phát nào',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _aboutTab(ChannelDetail c) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Mô tả',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          c.description != null && c.description!.isNotEmpty
              ? c.description!
              : 'Kênh này chưa thêm mô tả chi tiết.',
          style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        const Text(
          'Thông tin chi tiết',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        _aboutRow(Icons.link, 'mach.vn/@${c.handle}'),
        _aboutRow(Icons.people_outline, '$_subscriberCount người đăng ký'),
        _aboutRow(
          Icons.video_library_outlined,
          '${c.videoCount} video đã đăng tải',
        ),
        _aboutRow(Icons.visibility_outlined, '${c.viewCount} tổng lượt xem'),
        _aboutRow(
          Icons.calendar_today_outlined,
          'Đã tham gia: ${_formatDate(c.createdAt)}',
        ),
      ],
    );
  }

  Widget _aboutRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
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
                color: const Color(0xFFF3F4F6),
                child: const Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    size: 50,
                    color: AppColors.primary,
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$views · $date',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
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
    return '${d.day}/${d.month}/${d.year}';
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
    return Container(color: Colors.white, child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}
