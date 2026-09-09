import 'package:flutter/material.dart';
import '../../../auth.dart';
import '../../../core/theme/app_theme.dart';
import '../models/channel_models.dart';
import '../services/channel_service.dart';

class ChannelSettingsScreen extends StatefulWidget {
  const ChannelSettingsScreen({
    super.key,
    required this.auth,
    required this.channel,
  });

  final AuthController auth;
  final ChannelDetail channel;

  @override
  State<ChannelSettingsScreen> createState() => _ChannelSettingsScreenState();
}

class _ChannelSettingsScreenState extends State<ChannelSettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _inviteEmailController;
  late final ChannelService _channelService;
  List<ChannelRole> _roles = const [];
  String _inviteRole = 'editor';

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _channelService = ChannelService(widget.auth);
    _nameController = TextEditingController(text: widget.channel.name);
    _descriptionController = TextEditingController(
      text: widget.channel.description ?? '',
    );
    _inviteEmailController = TextEditingController();
    _loadRoles();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _inviteEmailController.dispose();
    super.dispose();
  }

  Future<void> _loadRoles() async {
    try {
      final roles = await _channelService.getRoles();
      if (mounted) setState(() => _roles = roles);
    } catch (_) {
      // The form keeps its safe Editor default when role metadata is unavailable.
    }
  }

  Future<void> _invite() async {
    final email = _inviteEmailController.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Vui lòng nhập email hợp lệ.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _channelService.inviteMember(widget.channel.id, email, _inviteRole);
      if (!mounted) return;
      _inviteEmailController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã gửi lời mời tham gia kênh.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Tên kênh không được để trống.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _channelService.updateChannel(
        widget.channel.id,
        name: name,
        description: _descriptionController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã cập nhật thông tin kênh thành công!'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Không thể cập nhật kênh.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmController = TextEditingController();
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final matches =
              confirmController.text.trim() == widget.channel.name.trim();
          return AlertDialog(
            title: const Text('Xác nhận xóa kênh?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hành động này sẽ ẩn kênh, danh sách video và handle của bạn khỏi HuTube.',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Nhập chính xác tên kênh "${widget.channel.name}" để xác nhận:',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmController,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(hintText: 'Nhập tên kênh'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Hủy'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  minimumSize: const Size(120, 44),
                ),
                onPressed: matches ? () => Navigator.of(ctx).pop(true) : null,
                child: const Text('Xác nhận xóa'),
              ),
            ],
          );
        },
      ),
    );

    if (shouldDelete == true) {
      setState(() => _busy = true);
      try {
        await _channelService.deleteChannel(widget.channel.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kênh đã được xóa.'),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
            ),
          );
          // Pop twice to go back to Profile
          Navigator.of(context).pop();
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = 'Không thể xóa kênh. Vui lòng thử lại sau.';
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt kênh'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.dangerBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.dangerBorder),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              const Text(
                'Thông tin cơ bản',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),

              const Text(
                'Tên kênh *',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                enabled: !_busy,
                decoration: const InputDecoration(
                  hintText: 'Nhập tên kênh',
                  prefixIcon: Icon(Icons.tv_outlined),
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'Định danh kênh (Handle)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextFormField(
                initialValue: '@${widget.channel.handle}',
                readOnly: true,
                enabled: false,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.alternate_email),
                  helperText: 'Handle không thể thay đổi sau khi tạo',
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'Mô tả kênh',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descriptionController,
                enabled: !_busy,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Giới thiệu về kênh của bạn...',
                ),
              ),
              const SizedBox(height: 24),

              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Lưu thay đổi'),
              ),

              if (widget.channel.permissions.contains('member.invite') ||
                  widget.channel.isOwner) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 22),
                const Text(
                  'Mời cộng tác viên',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Người được mời có thể xem rõ phạm vi quyền trước khi chấp nhận.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _inviteEmailController,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email người dùng',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _inviteRole,
                  decoration: const InputDecoration(labelText: 'Vai trò'),
                  items:
                      (_roles.isEmpty
                              ? const [
                                  ChannelRole(
                                    code: 'editor',
                                    name: 'Biên tập viên',
                                    description: '',
                                  ),
                                ]
                              : _roles)
                          .map(
                            (role) => DropdownMenuItem(
                              value: role.code,
                              child: Text(role.name),
                            ),
                          )
                          .toList(),
                  onChanged: _busy
                      ? null
                      : (value) =>
                            setState(() => _inviteRole = value ?? 'editor'),
                ),
                if (_roles.any((role) => role.code == _inviteRole)) ...[
                  const SizedBox(height: 7),
                  Text(
                    _roles
                        .firstWhere((role) => role.code == _inviteRole)
                        .description,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _invite,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Gửi lời mời'),
                ),
              ],

              const SizedBox(height: 36),
              const Divider(),
              const SizedBox(height: 24),

              // Danger Zone
              if (widget.channel.permissions.contains('channel.delete') ||
                  widget.channel.isOwner)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.dangerBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.dangerBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: AppColors.danger,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Vùng nguy hiểm',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.danger,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Xóa kênh sẽ chuyển kênh sang trạng thái đã xóa (soft-delete), ẩn các video và giải phóng handle của bạn. Sau khi xóa, bạn có thể tạo một kênh mới.',
                        style: TextStyle(
                          color: Color(0xFF991B1B),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: _busy ? null : _confirmDelete,
                        child: const Text('Xóa kênh này'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
