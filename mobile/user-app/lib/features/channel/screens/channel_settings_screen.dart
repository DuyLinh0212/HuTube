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
  late final ChannelService _channelService;

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _channelService = ChannelService(widget.auth);
    _nameController = TextEditingController(text: widget.channel.name);
    _descriptionController = TextEditingController(text: widget.channel.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
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
          final matches = confirmController.text.trim() == widget.channel.name.trim();
          return AlertDialog(
            title: const Text('Xác nhận xóa kênh?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hành động này sẽ ẩn kênh, danh sách video và handle của bạn khỏi HuTube.',
                  style: TextStyle(color: AppColors.danger, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'Nhập chính xác tên kênh "${widget.channel.name}" để xác nhận:',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmController,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Nhập tên kênh',
                  ),
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
                    style: const TextStyle(color: AppColors.danger, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              const Text(
                'Thông tin cơ bản',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),

              const Text('Tên kênh *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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

              const Text('Định danh kênh (Handle)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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

              const Text('Mô tả kênh', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Lưu thay đổi'),
              ),

              const SizedBox(height: 36),
              const Divider(),
              const SizedBox(height: 24),

              // Danger Zone
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
                        Icon(Icons.warning_amber_rounded, color: AppColors.danger),
                        SizedBox(width: 8),
                        Text(
                          'Vùng nguy hiểm',
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.danger, fontSize: 15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Xóa kênh sẽ chuyển kênh sang trạng thái đã xóa (soft-delete), ẩn các video và giải phóng handle của bạn. Sau khi xóa, bạn có thể tạo một kênh mới.',
                      style: TextStyle(color: Color(0xFF991B1B), fontSize: 13, height: 1.4),
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
