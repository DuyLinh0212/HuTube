import 'package:flutter/material.dart';
import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../models/channel_models.dart';
import '../services/channel_service.dart';

class ChannelMembersScreen extends StatefulWidget {
  const ChannelMembersScreen({
    super.key,
    required this.auth,
    required this.channel,
  });
  final AuthController auth;
  final ChannelDetail channel;
  @override
  State<ChannelMembersScreen> createState() => _ChannelMembersScreenState();
}

class _ChannelMembersScreenState extends State<ChannelMembersScreen> {
  late final _service = ChannelService(widget.auth);
  late final _session = widget.auth.sessionGeneration;
  List<ChannelMember> _members = const [];
  List<ChannelRole> _roles = const [];
  bool _loading = true;
  int _editVersion = 0;
  String? _error;
  final _busy = <String>{};
  bool get _current => mounted && _session == widget.auth.sessionGeneration;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.channel.can('member.view')) {
      setState(() {
        _loading = false;
        _error = AppStrings.t('common.forbidden');
      });
      return;
    }
    try {
      final data = await Future.wait([
        _service.getMembers(widget.channel.id),
        _service.getRoles(),
      ]);
      if (!_current) return;
      setState(() {
        _members = data[0] as List<ChannelMember>;
        _roles = data[1] as List<ChannelRole>;
        _loading = false;
        _error = null;
      });
    } on ApiFailure catch (e) {
      if (_current) {
        setState(() {
          _loading = false;
          _error = AppStrings.apiError(e);
        });
      }
    } catch (_) {
      if (_current) {
        setState(() {
          _loading = false;
          _error = AppStrings.t('common.error');
        });
      }
    }
  }

  Future<void> _changeRole(ChannelMember member, String role) async {
    if (!_busy.add(member.userId)) return;
    setState(() {});
    try {
      await _service.changeMemberRole(widget.channel.id, member.userId, role);
      if (_current) await _load();
    } on ApiFailure catch (e) {
      if (_current) setState(() => _error = AppStrings.apiError(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(member.userId);
          _editVersion++;
        });
      }
    }
  }

  Future<void> _remove(ChannelMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: AppStrings.t('channel.removeMember'),
        message: AppStrings.format('channel.removeMemberMessage', {
          'name': member.displayName,
        }),
        confirmLabel: AppStrings.t('common.delete'),
        destructive: true,
        icon: Icons.person_remove_outlined,
      ),
    );
    if (confirmed != true || !_current || !_busy.add(member.userId)) return;
    setState(() {});
    try {
      await _service.removeMember(widget.channel.id, member.userId);
      if (_current) await _load();
    } on ApiFailure catch (e) {
      if (_current) setState(() => _error = AppStrings.apiError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(member.userId));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppStrings.t('channel.members'))),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.channel.name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  HuTubeNotice(
                    message: _error!,
                    actionLabel: AppStrings.t('common.retry'),
                    onAction: _load,
                  ),
                  const SizedBox(height: 16),
                ],
                if (_members.isEmpty && _error == null)
                  Text(AppStrings.t('channel.membersEmpty')),
                for (final member in _members)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: HuTubeSurface(
                      padding: const EdgeInsets.all(16),
                      borderRadius: 18,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              HuTubeAvatar(
                                url: member.avatarUrl,
                                label: member.displayName,
                                radius: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      member.displayName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      member.email,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              if (member.roleCode != 'owner' &&
                                  member.userId !=
                                      widget.auth.user?['userId'] &&
                                  widget.channel.can('member.remove'))
                                IconButton(
                                  tooltip: AppStrings.t('channel.removeMember'),
                                  onPressed: _busy.contains(member.userId)
                                      ? null
                                      : () => _remove(member),
                                  icon: const Icon(
                                    Icons.person_remove_outlined,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (member.roleCode != 'owner' &&
                              member.userId != widget.auth.user?['userId'] &&
                              widget.channel.can('member.change_role'))
                            DropdownButtonFormField<String>(
                              key: ValueKey(
                                '${member.userId}-${member.roleCode}-$_editVersion',
                              ),
                              initialValue:
                                  _roles.any((r) => r.code == member.roleCode)
                                  ? member.roleCode
                                  : null,
                              isExpanded: true,
                              items: _roles
                                  .map(
                                    (role) => DropdownMenuItem(
                                      value: role.code,
                                      child: Text(_role(role.code)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _busy.contains(member.userId)
                                  ? null
                                  : (value) {
                                      if (value != null &&
                                          value != member.roleCode) {
                                        _changeRole(member, value);
                                      }
                                    },
                              decoration: InputDecoration(
                                labelText: AppStrings.t('channel.inviteRole'),
                              ),
                            )
                          else
                            Text(
                              _role(member.roleCode),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
  );
  String _role(String code) => AppStrings.t(switch (code) {
    'owner' => 'channel.owner',
    'manager' => 'channel.roleManager',
    'editor' => 'channel.roleEditor',
    'moderator' => 'channel.roleModerator',
    _ => 'channel.roleViewer',
  });
}
