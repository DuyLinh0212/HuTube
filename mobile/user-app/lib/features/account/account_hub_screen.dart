import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth.dart';
import '../../channel/screens/create_channel_screen.dart';
import '../../channel/services/channel_service.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../content/content_models.dart';
import '../content/content_service.dart';
import '../content/local_download_manager.dart';
import '../notifications/notification_center.dart';
import '../playlists/playlist_service.dart';
import 'account_settings_screen.dart';

class AccountHubScreen extends StatefulWidget {
  const AccountHubScreen({
    super.key,
    required this.auth,
    required this.notifications,
  });

  final AuthController auth;
  final NotificationCenter notifications;

  @override
  State<AccountHubScreen> createState() => _AccountHubScreenState();
}

class _AccountHubScreenState extends State<AccountHubScreen> {
  late final ContentService _content;
  late final ChannelService _channelService;
  late final PlaylistService _playlistService;

  bool _loading = true;
  String? _channelHandle;
  List<LibraryVideo> _history = [];
  List<LibraryVideo> _liked = [];
  List<PlaylistSummary> _playlists = [];
  int _downloadCount = 0;

  @override
  void initState() {
    super.initState();
    _content = ContentService(widget.auth);
    _channelService = ChannelService(widget.auth);
    _playlistService = PlaylistService(widget.auth);
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await Future.wait([
      _loadChannel(),
      _loadHistory(),
      _loadLiked(),
      _loadPlaylists(),
      _loadDownloads(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadChannel() async {
    try {
      final channel = await _channelService.getMyChannel();
      if (mounted) {
        setState(() {
          _channelHandle = channel?.handle;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    try {
      final res = await _content.history(page: 1);
      if (mounted) {
        setState(() => _history = res.items);
      }
    } catch (_) {}
  }

  Future<void> _loadLiked() async {
    try {
      final res = await _content.liked(page: 1);
      if (mounted) {
        setState(() => _liked = res.items);
      }
    } catch (_) {}
  }

  Future<void> _loadPlaylists() async {
    try {
      final summaries = (await _playlistService.mine())
          .where(
            (playlist) => !const {
              'Video đã lưu',
              'Xem sau',
              'Watch later',
            }.contains(playlist.name.trim()),
          )
          .toList();
      final res = await Future.wait(
        summaries.map((playlist) async {
          if (playlist.coverUrl?.isNotEmpty == true) return playlist;
          try {
            final detail = await _playlistService.get(playlist.id);
            return PlaylistSummary(
              id: playlist.id,
              name: playlist.name,
              visibility: playlist.visibility,
              itemCount: playlist.itemCount,
              description: playlist.description,
              coverUrl: detail.coverUrl ?? playlist.coverUrl,
              updatedAt: playlist.updatedAt,
            );
          } catch (_) {
            return playlist;
          }
        }),
      );
      if (mounted) {
        setState(() => _playlists = res);
      }
    } catch (_) {}
  }

  Future<void> _loadDownloads() async {
    try {
      final manager = LocalDownloadManager.instance;
      await manager.ensureLoaded();
      if (mounted) {
        setState(() => _downloadCount = manager.items.length);
      }
    } catch (_) {}
  }

  Future<void> _sharePlaylist(PlaylistSummary playlist) async {
    await Share.share('${playlist.name}\nhutube://playlists/${playlist.id}');
  }

  Future<void> _deletePlaylist(PlaylistSummary playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.t('playlists.deleteTitle')),
        content: Text(
          AppStrings.format('playlists.deleteDescription', {
            'name': playlist.name,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppStrings.t('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _playlistService.delete(playlist.id);
      if (mounted) {
        setState(() => _playlists.removeWhere((item) => item.id == playlist.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.t('playlists.deleted'))),
        );
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.apiError(error))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.t('playlists.deleteError'))),
        );
      }
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountSettingsScreen(
          auth: widget.auth,
          notifications: widget.notifications,
        ),
      ),
    ).then((_) {
      if (mounted) _loadAll();
    });
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '00:00';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    final h = m ~/ 60;
    if (h > 0) {
      final remM = m % 60;
      return '${h.toString().padLeft(2, '0')}:${remM.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!widget.auth.authenticated) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F0F0F) : AppColors.background,
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF0F0F0F) : AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          title: Text(
            'Bạn',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          actions: [
            IconButton(
              tooltip: AppStrings.t('common.search'),
              onPressed: () => context.push('/search'),
              icon: Icon(
                Icons.search_rounded,
                size: 24,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            IconButton(
              tooltip: 'Cài đặt',
              onPressed: _openSettings,
              icon: Icon(
                Icons.settings_outlined,
                size: 24,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.account_circle_outlined,
                  size: 96,
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
                const SizedBox(height: 20),
                Text(
                  'Tận hưởng HuTube trọn vẹn hơn',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Đăng nhập để xem lịch sử, danh sách phát, video đã lưu và nhiều tính năng khác.',
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

    final user = widget.auth.user;
    final name = (user?['displayName'] as String?) ?? 'Danh Ngô Công';
    final username = (user?['username'] as String?) ?? 'danhcongngo6005';
    final avatarUrl = user?['avatarUrl'] as String?;
    final hasPlan = user?['plan'] != null || user?['isPremium'] == true;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : AppColors.background,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F0F0F) : AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Text(
          'Bạn',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        actions: [
          AnimatedBuilder(
            animation: widget.notifications,
            builder: (context, _) => IconButton(
              tooltip: AppStrings.t('common.notifications'),
              onPressed: () => context.push('/notifications'),
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 24,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                  if (widget.notifications.unreadCount > 0)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: AppStrings.t('common.search'),
            onPressed: () => context.push('/search'),
            icon: Icon(
              Icons.search_rounded,
              size: 24,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          IconButton(
            tooltip: 'Cài đặt',
            onPressed: _openSettings,
            icon: Icon(
              Icons.settings_outlined,
              size: 24,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primaryPink,
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            // ================= HEADER PROFILE SECTION =================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Avatar
                      HuTubeAvatar(
                        url: avatarUrl,
                        label: name,
                        radius: 38,
                        backgroundColor: AppColors.primaryPink.withValues(alpha: 0.25),
                      ),
                      const SizedBox(width: 16),
                      // Name & Handle
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : AppColors.textPrimary,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    '@$username',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? const Color(0xFFAAAAAA) : AppColors.textMuted,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  hasPlan ? 'Thành viên Premium' : 'Thành viên HuTube',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? const Color(0xFFAAAAAA) : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Action buttons: "Xem kênh" and "Các lợi ích của gói Premi..."
                  Row(
                    children: [
                      // Pill 1: Xem kênh / Tạo kênh
                      FilledButton(
                        onPressed: () {
                          if (_channelHandle != null) {
                            context.push('/channels/$_channelHandle');
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CreateChannelScreen(auth: widget.auth),
                              ),
                            ).then((_) => _loadChannel());
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: isDark ? Colors.white : AppColors.ink,
                          foregroundColor: isDark ? Colors.black : Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          elevation: 0,
                          minimumSize: const Size(0, 38),
                        ),
                        child: Text(
                          _channelHandle != null ? 'Xem kênh' : 'Tạo kênh',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Pill 2: Các lợi ích của gói
                      OutlinedButton(
                        onPressed: () => context.push('/plans'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: isDark ? const Color(0xFF272727) : AppColors.surfaceAlt,
                          foregroundColor: isDark ? Colors.white : AppColors.textPrimary,
                          side: BorderSide(
                            color: isDark ? const Color(0xFF3F3F3F) : AppColors.borderSubtle,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          minimumSize: const Size(0, 38),
                        ),
                        child: const Text(
                          'Các lợi ích của gói',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // ================= SECTION 1: VIDEO ĐÃ XEM =================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => context.push('/library'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Video đã xem',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 22,
                            color: isDark ? Colors.white : AppColors.textPrimary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Horizontal List of History Videos
            if (_loading && _history.isEmpty)
              SizedBox(
                height: 175,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: 3,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, _) => _skeletonVideoCard(isDark),
                ),
              )
            else if (_history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A1A1A) : AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.history_toggle_off_rounded, color: isDark ? Colors.white54 : AppColors.textMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Chưa có video đã xem. Các video bạn xem sẽ hiển thị tại đây.',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white70 : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                height: 185,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _history.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final item = _history[index];
                    return _buildHistoryCard(item, isDark);
                  },
                ),
              ),

            const SizedBox(height: 18),

            // ================= SECTION 2: THƯ VIỆN =================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Text(
                'Thư viện',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),

            // Horizontal Filter Chips: "Gần đây v", "Đã tải xuống", "Danh sách phát", "Kho lưu trữ"
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _filterChip(
                    label: 'Gần đây',
                    hasDropdown: true,
                    isDark: isDark,
                    onTap: () {},
                  ),
                  const SizedBox(width: 8),
                  _filterChip(
                    label: 'Đã tải xuống',
                    count: _downloadCount > 0 ? _downloadCount : null,
                    isDark: isDark,
                    onTap: () => context.push('/downloads'),
                  ),
                  const SizedBox(width: 8),
                  _filterChip(
                    label: 'Danh sách phát',
                    count: _playlists.isNotEmpty ? _playlists.length : null,
                    isDark: isDark,
                    onTap: () => context.push('/playlists'),
                  ),
                  const SizedBox(width: 8),
                  _filterChip(
                    label: 'Video của bạn',
                    isDark: isDark,
                    onTap: () => context.push('/creator'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Library items list: liked videos and user playlists.
            _buildPlaylistTile(
              title: 'Video đã thích',
              subtitle: 'Riêng tư',
              countText: '${_liked.length} video',
              thumbnailUrl: _liked.isNotEmpty ? _liked.first.thumbnailUrl : null,
              fallbackIcon: Icons.thumb_up_alt_rounded,
              isDark: isDark,
              onTap: () => context.push('/library'),
            ),

            // Custom playlists from user
            for (final p in _playlists)
              _buildPlaylistTile(
                title: p.name,
                subtitle: p.visibility == 'public' ? 'Công khai' : 'Riêng tư',
                countText: '${p.itemCount} video',
                thumbnailUrl: p.coverUrl,
                fallbackIcon: Icons.playlist_play_rounded,
                isDark: isDark,
                onTap: () => context.push('/playlists/${p.id}'),
                menuItems: [
                  PopupMenuItem(
                    value: 'share',
                    child: Text(AppStrings.t('common.share')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(AppStrings.t('common.delete')),
                  ),
                ],
                onMenuSelected: (value) {
                  if (value == 'share') _sharePlaylist(p);
                  if (value == 'delete') _deletePlaylist(p);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    int? count,
    bool hasDropdown = false,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final displayText = count != null ? '$label ($count)' : label;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF272727) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? const Color(0xFF3F3F3F) : AppColors.borderSubtle,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              displayText,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            if (hasDropdown) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(LibraryVideo video, bool isDark) => SizedBox(
    width: 160,
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push('/watch/${video.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail with duration / live badge & progress
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (video.thumbnailUrl != null && video.thumbnailUrl!.isNotEmpty)
                    Image.network(
                      video.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: isDark ? const Color(0xFF272727) : AppColors.surfaceAlt,
                        child: const Icon(Icons.video_file_outlined),
                      ),
                    )
                  else
                    Container(
                      color: isDark ? const Color(0xFF272727) : AppColors.surfaceAlt,
                      child: const Icon(Icons.video_file_outlined),
                    ),

                  // Duration badge in bottom right
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatDuration(video.duration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  // Red watch progress line at bottom
                  if (video.progress > 0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: (video.progress / 100).clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: Colors.black45,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Title + 3 dots row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: isDark ? const Color(0xFFAAAAAA) : AppColors.textMuted,
                ),
                onSelected: (val) {
                  if (val == 'share') {
                    Share.share('https://hutube.app/watch/${video.id}');
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(Icons.share_outlined, size: 20),
                        SizedBox(width: 10),
                        Text('Chia sẻ'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Channel Name
          Text(
            video.channelName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? const Color(0xFFAAAAAA) : AppColors.textMuted,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildPlaylistTile({
    required String title,
    required String subtitle,
    String? countText,
    String? thumbnailUrl,
    required IconData fallbackIcon,
    required bool isDark,
    required VoidCallback onTap,
    List<PopupMenuEntry<String>>? menuItems,
    ValueChanged<String>? onMenuSelected,
  }) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Thumbnail or rounded badge container
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 110,
              height: 62,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF272727) : AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
                    Image.network(
                      thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: isDark ? const Color(0xFF272727) : AppColors.surfaceAlt,
                        child: Icon(fallbackIcon, color: isDark ? Colors.white70 : AppColors.textMuted),
                      ),
                    )
                  else
                    Container(
                      color: isDark ? const Color(0xFF272727) : AppColors.surfaceAlt,
                      child: Icon(fallbackIcon, size: 28, color: isDark ? Colors.white70 : AppColors.textMuted),
                    ),

                  // Bottom badge icon overlay
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        fallbackIcon,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Title & Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  countText != null ? '$subtitle • $countText' : subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? const Color(0xFFAAAAAA) : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (menuItems != null && menuItems.isNotEmpty)
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.more_vert_rounded,
                color: isDark ? const Color(0xFFAAAAAA) : AppColors.textMuted,
                size: 20,
              ),
              onSelected: onMenuSelected,
              itemBuilder: (_) => menuItems,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    ),
  );

  Widget _skeletonVideoCard(bool isDark) => SizedBox(
    width: 160,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 160,
          height: 90,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF272727) : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 120,
          height: 12,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF272727) : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 80,
          height: 10,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF272727) : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    ),
  );
}
