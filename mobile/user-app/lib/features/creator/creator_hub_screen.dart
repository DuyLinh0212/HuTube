import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../channel/models/channel_models.dart';
import '../../channel/screens/channel_invitations_screen.dart';
import '../../channel/screens/channel_settings_screen.dart';
import '../../channel/screens/create_channel_screen.dart';
import '../../channel/services/channel_service.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'creator_analytics_screen.dart';
import 'creator_comments_screen.dart';
import 'creator_content_screen.dart';
import 'video_upload_screen.dart';

class CreatorHubScreen extends StatefulWidget {
  const CreatorHubScreen({super.key, required this.auth});
  final AuthController auth;
  @override
  State<CreatorHubScreen> createState() => _CreatorHubScreenState();
}

class _CreatorHubScreenState extends State<CreatorHubScreen> {
  ChannelDetail? _channel;
  List<ChannelDetail> _accessibleChannels = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final selectedChannelId = _channel?.id;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = ChannelService(widget.auth);
      final accessibleChannels = await service.getAccessibleChannels();
      final selectedChannel = accessibleChannels
          .where((channel) => channel.id == selectedChannelId)
          .firstOrNull;
      final ownedChannel = accessibleChannels
          .where((channel) => channel.isOwner)
          .firstOrNull;
      if (mounted) {
        setState(() {
          _accessibleChannels = accessibleChannels;
          _channel =
              selectedChannel ?? ownedChannel ?? accessibleChannels.firstOrNull;
          _loading = false;
        });
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = AppStrings.apiError(error, fallback: 'common.error');
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

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
        children: const [
          _CreatorSkeleton(height: 172),
          SizedBox(height: 18),
          _CreatorSkeleton(height: 82),
          SizedBox(height: 10),
          _CreatorSkeleton(height: 82),
        ],
      );
    }
    if (_error != null) {
      return HuTubeStateView(
        icon: Icons.dashboard_outlined,
        title: _error!,
        message: AppStrings.t('common.networkError'),
        actionLabel: AppStrings.t('common.retry'),
        onAction: _load,
        accent: AppColors.violet,
      );
    }
    if (_channel == null) {
      return HuTubeStateView(
        icon: Icons.video_call_outlined,
        title: AppStrings.t('creator.noChannel'),
        message: AppStrings.t('creator.createChannelHint'),
        actionLabel: AppStrings.t('creator.createChannel'),
        onAction: () => _open(CreateChannelScreen(auth: widget.auth)),
        accent: AppColors.violet,
      );
    }
    final channel = _channel!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        if (_accessibleChannels.length > 1)
          DropdownButtonFormField<String>(
            initialValue: channel.id,
            decoration: InputDecoration(
              labelText: AppStrings.t('creator.channelSelector'),
            ),
            items: _accessibleChannels
                .map(
                  (item) => DropdownMenuItem(
                    value: item.id,
                    child: Text(
                      AppStrings.format('creator.managedAs', {
                        'name': item.name,
                        'role': _roleLabel(item),
                      }),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              final selected = _accessibleChannels
                  .where((item) => item.id == value)
                  .firstOrNull;
              if (selected != null) setState(() => _channel = selected);
            },
          ),
        if (_accessibleChannels.length > 1) const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.ink, Color(0xFF36263C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  HuTubeAvatar(
                    url: channel.avatarUrl,
                    label: channel.name,
                    radius: 26,
                    backgroundColor: AppColors.violet.withValues(alpha: .2),
                    foregroundColor: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          channel.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '@${channel.handle}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .68),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _StudioStat(
                      label: AppStrings.t('creator.metricSubscribers'),
                      value: AppStrings.number(channel.subscriberCount),
                    ),
                  ),
                  Expanded(
                    child: _StudioStat(
                      label: AppStrings.t('creator.metricVideos'),
                      value: AppStrings.number(channel.videoCount),
                    ),
                  ),
                  Expanded(
                    child: _StudioStat(
                      label: AppStrings.t('creator.metricViews'),
                      value: AppStrings.number(channel.viewCount),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _CreatorAction(
          customIcon: AppIcons.asset(
            AppIcons.upload,
            size: 20,
            color: AppColors.primaryPink,
          ),
          title: AppStrings.t('creator.upload'),
          detail: AppStrings.t('creator.uploadDescription'),
          onTap: () =>
              _open(VideoUploadScreen(auth: widget.auth, channel: channel)),
        ),
        _CreatorAction(
          customIcon: AppIcons.asset(
            AppIcons.myVideo,
            size: 20,
            color: AppColors.primaryPink,
          ),
          title: AppStrings.t('creator.content'),
          detail: AppStrings.t('creator.contentDescription'),
          onTap: () =>
              _open(CreatorContentScreen(auth: widget.auth, channel: channel)),
        ),
        _CreatorAction(
          customIcon: AppIcons.asset(
            AppIcons.statistics,
            size: 20,
            color: AppColors.primaryPink,
          ),
          title: AppStrings.t('creator.analytics'),
          detail: AppStrings.t('creator.analyticsDescription'),
          onTap: () => _open(
            CreatorAnalyticsScreen(auth: widget.auth, channel: channel),
          ),
        ),
        _CreatorAction(
          icon: Icons.forum_outlined,
          title: AppStrings.t('creator.comments'),
          detail: AppStrings.t('creator.commentsDescription'),
          onTap: () =>
              _open(CreatorCommentsScreen(auth: widget.auth, channel: channel)),
        ),
        _CreatorAction(
          customIcon: AppIcons.asset(
            AppIcons.setting,
            size: 20,
            color: AppColors.primaryPink,
          ),
          title: AppStrings.t('creator.settings'),
          detail: AppStrings.t('creator.settingsDescription'),
          onTap: () =>
              _open(ChannelSettingsScreen(auth: widget.auth, channel: channel)),
        ),
        _CreatorAction(
          icon: Icons.group_outlined,
          title: AppStrings.t('creator.invitations'),
          detail: AppStrings.t('creator.invitationsDescription'),
          onTap: () => _open(ChannelInvitationsScreen(auth: widget.auth)),
        ),
      ],
    );
  }

  String _roleLabel(ChannelDetail channel) {
    if (channel.isOwner) return AppStrings.t('channel.owner');
    return switch (channel.myRole) {
      'manager' => AppStrings.t('channel.roleManager'),
      'editor' => AppStrings.t('channel.roleEditor'),
      'moderator' => AppStrings.t('channel.roleModerator'),
      'viewer' => AppStrings.t('channel.roleViewer'),
      _ => channel.myRole ?? AppStrings.t('channel.roleViewer'),
    };
  }
}

class _CreatorAction extends StatelessWidget {
  const _CreatorAction({
    this.icon,
    this.customIcon,
    required this.title,
    required this.detail,
    this.onTap,
  });
  final IconData? icon;
  final Widget? customIcon;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: isDark ? const Color(0xFF1C1824) : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0xFF2C2436) : AppColors.cardBorder,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primaryPink.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child:
              customIcon ?? Icon(icon, color: AppColors.primaryPink, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(
          detail,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: onTap == null
            ? const Icon(Icons.info_outline, size: 18)
            : const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: onTap,
      ),
    );
  }
}

class _StudioStat extends StatelessWidget {
  const _StudioStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: .62),
          fontSize: 11,
        ),
      ),
    ],
  );
}

class _CreatorSkeleton extends StatelessWidget {
  const _CreatorSkeleton({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: AppColors.borderSubtle,
      borderRadius: BorderRadius.circular(16),
    ),
  );
}
