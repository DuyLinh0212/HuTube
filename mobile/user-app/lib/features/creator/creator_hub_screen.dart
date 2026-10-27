import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../channel/models/channel_models.dart';
import '../../channel/screens/channel_invitations_screen.dart';
import '../../channel/screens/channel_settings_screen.dart';
import '../../channel/screens/create_channel_screen.dart';
import '../../channel/services/channel_service.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'creator_analytics_screen.dart';
import 'creator_comments_screen.dart';
import 'creator_content_screen.dart';
import 'creator_subtitles_screen.dart';
import 'video_upload_screen.dart';
import '../../channel/screens/channel_members_screen.dart';
import '../../channel/screens/channel_links_screen.dart';
import '../moderation/moderation_screen.dart';
import '../policies/policies_screen.dart';

class CreatorHubScreen extends StatefulWidget {
  const CreatorHubScreen({
    super.key,
    required this.auth,
    this.openUpload = false,
  });
  final bool openUpload;
  final AuthController auth;
  @override
  State<CreatorHubScreen> createState() => _CreatorHubScreenState();
}

class _CreatorHubScreenState extends State<CreatorHubScreen> {
  ChannelDetail? _channel;
  List<ChannelDetail> _accessibleChannels = const [];
  bool _loading = true;
  String? _error;
  bool _uploadOpened = false;

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
      final accessibleChannels = [...await service.getAccessibleChannels()];
      // The accessible endpoint omits suspended channels. Check ownership before
      // claiming that a creator has no channel and offering to create another.
      if (!accessibleChannels.any((channel) => channel.isOwner)) {
        try {
          final own = await service.getMyChannel();
          if (own != null &&
              own.id.isNotEmpty &&
              !accessibleChannels.any((channel) => channel.id == own.id)) {
            accessibleChannels.insert(0, own);
          }
        } catch (_) {
          if (accessibleChannels.isEmpty) rethrow;
        }
      }
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
        if (widget.openUpload &&
            !_uploadOpened &&
            _channel?.can('video.upload') == true) {
          _uploadOpened = true;
          await _open(VideoUploadScreen(auth: widget.auth, channel: _channel!));
        }
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
    if (channel.status == 'suspended' && _accessibleChannels.length == 1) {
      return HuTubeStateView(
        icon: Icons.pause_circle_outline_rounded,
        title: AppStrings.t('channel.suspendedTitle'),
        message: AppStrings.t('creator.uploadSuspended'),
        actionLabel: AppStrings.t('channel.statusAndAppeal'),
        onAction: () => _open(
          Scaffold(
            appBar: AppBar(
              title: Text(AppStrings.t('channel.statusAndAppeal')),
            ),
            body: ModerationScreen(auth: widget.auth, channel: channel),
          ),
        ),
        accent: Theme.of(context).colorScheme.error,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            AppStrings.t('creator.title'),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.format('creator.manageDescription', {
              'name': channel.name,
            }),
            style: TextStyle(color: AppColors.textSecondaryFor(context)),
          ),
          const SizedBox(height: 16),
          if (channel.status == 'suspended') ...[
            HuTubeNotice(
              message: AppStrings.t('creator.uploadSuspended'),
              actionLabel: AppStrings.t('channel.statusAndAppeal'),
              onAction: () => _open(
                Scaffold(
                  appBar: AppBar(
                    title: Text(AppStrings.t('channel.statusAndAppeal')),
                  ),
                  body: ModerationScreen(auth: widget.auth, channel: channel),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_accessibleChannels.length > 1)
            DropdownButtonFormField<String>(
              isExpanded: true,
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
              gradient: LinearGradient(
                colors: [
                  AppColors.surfaceFor(context),
                  Color.alphaBlend(
                    AppColors.primaryPink.withValues(alpha: .09),
                    AppColors.surfaceFor(context),
                  ),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.borderFor(context)),
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
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            channel.name,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '@${channel.handle}',
                            style: TextStyle(
                              color: AppColors.textSecondaryFor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
                if (channel.can('video.upload'))
                  SizedBox(
                    width: null,
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: () => _open(
                        VideoUploadScreen(auth: widget.auth, channel: channel),
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(AppStrings.t('creator.upload')),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _CreatorTools(
            children: [
              if (channel.can('video.view'))
                _CreatorAction(
                  icon: Icons.video_library_outlined,
                  title: AppStrings.t('creator.content'),
                  detail: AppStrings.t('creator.contentDescription'),
                  onTap: () => _open(
                    CreatorContentScreen(auth: widget.auth, channel: channel),
                  ),
                ),
              if (channel.can('analytics.view'))
                _CreatorAction(
                  icon: Icons.insights_rounded,
                  title: AppStrings.t('creator.analytics'),
                  detail: AppStrings.t('creator.analyticsDescription'),
                  onTap: () => _open(
                    CreatorAnalyticsScreen(auth: widget.auth, channel: channel),
                  ),
                ),
              if (channel.can('comment.manage'))
                _CreatorAction(
                  icon: Icons.forum_outlined,
                  title: AppStrings.t('creator.comments'),
                  detail: AppStrings.t('creator.commentsDescription'),
                  onTap: () => _open(
                    CreatorCommentsScreen(auth: widget.auth, channel: channel),
                  ),
                ),
              if (channel.can('video.view'))
                _CreatorAction(
                  icon: Icons.subtitles_outlined,
                  title: AppStrings.t('creator.subtitles'),
                  detail: AppStrings.t('creator.subtitlesDescription'),
                  onTap: () => _open(
                    CreatorSubtitlesScreen(auth: widget.auth, channel: channel),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (channel.can('channel.setting.view') ||
              channel.can('channel.edit_profile') ||
              channel.can('channel.edit_branding'))
            _CreatorAction(
              compact: true,
              icon: Icons.settings_outlined,
              title: AppStrings.t('creator.settings'),
              detail: AppStrings.t('creator.settingsDescription'),
              onTap: () => _open(
                ChannelSettingsScreen(auth: widget.auth, channel: channel),
              ),
            ),
          _CreatorAction(
            compact: true,
            icon: Icons.group_outlined,
            title: AppStrings.t('creator.invitations'),
            detail: AppStrings.t('creator.invitationsDescription'),
            onTap: () => _open(ChannelInvitationsScreen(auth: widget.auth)),
          ),
          if (channel.can('channel.edit_profile'))
            _CreatorAction(
              compact: true,
              icon: Icons.link_rounded,
              title: AppStrings.t('channel.socialLinks'),
              detail: AppStrings.t('channel.linksDescription'),
              onTap: () => _open(
                ChannelLinksScreen(auth: widget.auth, channel: channel),
              ),
            ),
          if (channel.can('member.view'))
            _CreatorAction(
              compact: true,
              icon: Icons.manage_accounts_outlined,
              title: AppStrings.t('channel.members'),
              detail: AppStrings.t('channel.inviteDescription'),
              onTap: () => _open(
                ChannelMembersScreen(auth: widget.auth, channel: channel),
              ),
            ),
          _CreatorAction(
            compact: true,
            icon: Icons.policy_outlined,
            title: AppStrings.t('policies.title'),
            detail: AppStrings.t('policies.description'),
            onTap: () => _open(
              Scaffold(
                appBar: AppBar(title: Text(AppStrings.t('policies.title'))),
                body: PoliciesScreen(auth: widget.auth),
              ),
            ),
          ),
          if (channel.isOwner || channel.can('copyright.view'))
            _CreatorAction(
              compact: true,
              icon: Icons.verified_user_outlined,
              title: AppStrings.t('creator.channelStatus'),
              detail: AppStrings.t('creator.channelStatusHint'),
              onTap: () =>
                  _open(ModerationScreen(auth: widget.auth, channel: channel)),
            ),
        ],
      ),
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
    this.compact = false,
    required this.title,
    required this.detail,
    this.onTap,
  });
  final IconData? icon;
  final bool compact;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.primaryPink.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
    );
    return Card(
      elevation: 0,
      margin: EdgeInsets.only(bottom: compact ? 8 : 0),
      color: AppColors.surfaceFor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.borderFor(context)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: iconWidget,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(
          detail,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: onTap == null
            ? const Icon(Icons.info_outline, size: 18)
            : const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: onTap,
      ),
    );
  }
}

class _CreatorTools extends StatelessWidget {
  const _CreatorTools({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final child in children)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: child),
    ],
  );
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
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        style: TextStyle(
          color: AppColors.textSecondaryFor(context),
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
