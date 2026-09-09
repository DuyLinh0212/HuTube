import 'package:flutter/material.dart';
import '../../../auth.dart';
import '../../../core/theme/app_theme.dart';
import '../models/channel_models.dart';
import '../services/channel_service.dart';

class ChannelInvitationsScreen extends StatefulWidget {
  const ChannelInvitationsScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<ChannelInvitationsScreen> createState() =>
      _ChannelInvitationsScreenState();
}

class _ChannelInvitationsScreenState extends State<ChannelInvitationsScreen> {
  late final ChannelService _service;
  List<ChannelInvitation> _invitations = const [];
  List<ChannelRole> _roles = const [];
  bool _loading = true;
  String? _busyId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = ChannelService(widget.auth);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        _service.getMyInvitations(),
        _service.getRoles(),
      ]);
      if (!mounted) return;
      setState(() {
        _invitations = values[0] as List<ChannelInvitation>;
        _roles = values[1] as List<ChannelRole>;
      });
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _roleName(String code) =>
      _roles.where((role) => role.code == code).firstOrNull?.name ?? code;
  String _roleDescription(String code) =>
      _roles.where((role) => role.code == code).firstOrNull?.description ?? '';

  Future<void> _respond(ChannelInvitation invitation, bool accept) async {
    setState(() {
      _busyId = invitation.id;
      _error = null;
    });
    try {
      if (accept) {
        await _service.acceptInvitation(invitation.id);
      } else {
        await _service.declineInvitation(invitation.id);
      }
      if (!mounted) return;
      setState(
        () => _invitations = _invitations
            .where((item) => item.id != invitation.id)
            .toList(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Đã tham gia kênh ${invitation.channelName}.'
                : 'Đã từ chối lời mời.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Lời mời tham gia kênh')),
    body: RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) _Notice(text: _error!, error: true),
                if (_invitations.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 100),
                    child: Column(
                      children: [
                        Icon(
                          Icons.mark_email_read_outlined,
                          size: 52,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(height: 14),
                        Text(
                          'Không có lời mời đang chờ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Kéo xuống để kiểm tra lại.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                for (final invitation in _invitations)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                child: Text(
                                  invitation.channelName.isEmpty
                                      ? '?'
                                      : invitation.channelName[0].toUpperCase(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      invitation.channelName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      '@${invitation.channelHandle}',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Chip(label: Text(_roleName(invitation.roleCode))),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _roleDescription(invitation.roleCode),
                            style: const TextStyle(fontSize: 13, height: 1.4),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: _busyId == null
                                      ? () => _respond(invitation, true)
                                      : null,
                                  child: Text(
                                    _busyId == invitation.id
                                        ? 'Đang xử lý…'
                                        : 'Chấp nhận',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _busyId == null
                                      ? () => _respond(invitation, false)
                                      : null,
                                  child: const Text('Từ chối'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.error});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error ? AppColors.dangerBg : const Color(0xFFF0FDF4),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: TextStyle(color: error ? AppColors.danger : AppColors.success),
    ),
  );
}
