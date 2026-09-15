import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../channel/models/channel_models.dart';
import '../../channel/screens/channel_invitations_screen.dart';
import '../../channel/screens/channel_settings_screen.dart';
import '../../channel/screens/create_channel_screen.dart';
import '../../channel/services/channel_service.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = ChannelService(widget.auth);
      final results = await Future.wait([
        service.getMyChannel(),
        service.getAccessibleChannels(),
      ]);
      final ownedChannel = results[0] as ChannelDetail?;
      final accessibleChannels = results[1] as List<ChannelDetail>;
      if (mounted) {
        setState(() {
          _accessibleChannels = accessibleChannels;
          _channel =
              ownedChannel ??
              (accessibleChannels.isEmpty ? null : accessibleChannels.first);
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
      return Center(
        child: CircularProgressIndicator(color: AppColors.primaryPink),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _load,
              child: Text(AppStrings.t('common.retry')),
            ),
          ],
        ),
      );
    }
    if (_channel == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.video_call_outlined,
                size: 54,
                color: AppColors.primaryPink,
              ),
              const SizedBox(height: 12),
              Text(
                AppStrings.t('creator.noChannel'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () =>
                    _open(ChannelInvitationsScreen(auth: widget.auth)),
                child: Text(AppStrings.t('creator.openInvitations')),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () => _open(CreateChannelScreen(auth: widget.auth)),
                child: Text(AppStrings.t('creator.createChannel')),
              ),
            ],
          ),
        ),
      );
    }
    final channel = _channel!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
      children: [
        Text(
          AppStrings.t('creator.title'),
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          AppStrings.format('creator.manageDescription', {
            'name': channel.name,
          }),
        ),
        const SizedBox(height: 16),
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundImage: channel.avatarUrl == null
                      ? null
                      : NetworkImage(channel.avatarUrl!),
                  child: channel.avatarUrl == null
                      ? Text(channel.name.substring(0, 1))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '@${channel.handle} · ${AppStrings.format('channel.stats', {'subscribers': AppStrings.number(channel.subscriberCount), 'videos': AppStrings.number(channel.videoCount)})}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _CreatorAction(
          icon: Icons.upload_file_outlined,
          title: AppStrings.t('creator.upload'),
          detail: AppStrings.t('creator.uploadDescription'),
          onTap: () =>
              _open(VideoUploadScreen(auth: widget.auth, channel: channel)),
        ),
        _CreatorAction(
          icon: Icons.video_library_outlined,
          title: AppStrings.t('creator.content'),
          detail: AppStrings.t('creator.contentDescription'),
          onTap: () =>
              _open(CreatorContentScreen(auth: widget.auth, channel: channel)),
        ),
        _CreatorAction(
          icon: Icons.forum_outlined,
          title: AppStrings.t('creator.comments'),
          detail: AppStrings.t('creator.commentsDescription'),
          onTap: () =>
              _open(CreatorCommentsScreen(auth: widget.auth, channel: channel)),
        ),
        _CreatorAction(
          icon: Icons.settings_outlined,
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
        _CreatorAction(
          icon: Icons.subtitles_outlined,
          title: AppStrings.t('creator.subtitles'),
          detail: AppStrings.t('creator.subtitlesDescription'),
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
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon, color: AppColors.primaryPink),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(detail),
      trailing: onTap == null
          ? const Icon(Icons.info_outline)
          : const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}
