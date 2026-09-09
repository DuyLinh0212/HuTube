import 'package:flutter/material.dart';
import '../../../auth.dart';
import '../../../core/theme/app_theme.dart';
import '../models/account_models.dart';
import '../services/account_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.auth,
    required this.profile,
  });

  final AuthController auth;
  final UserProfile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _bioController;
  late String _country;
  late final AccountService _accountService;

  bool _busy = false;
  String? _error;
  int _bioLength = 0;

  final List<String> _countries = [
    'Việt Nam',
    'Hoa Kỳ',
    'Nhật Bản',
    'Hàn Quốc',
    'Singapore',
    'Khác',
  ];

  @override
  void initState() {
    super.initState();
    _accountService = AccountService(widget.auth);
    _displayNameController = TextEditingController(text: widget.profile.displayName);
    _bioController = TextEditingController(text: widget.profile.bio ?? '');
    _bioLength = _bioController.text.length;
    _country = widget.profile.country ?? 'Việt Nam';
    if (!_countries.contains(_country)) {
      _countries.add(_country);
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _displayNameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Tên hiển thị không được để trống.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final updated = await _accountService.updateProfile(
        displayName: name,
        bio: _bioController.text.trim(),
        country: _country,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã cập nhật thông tin hồ sơ thành công!'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(updated);
      }
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Có lỗi xảy ra khi lưu thông tin.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chỉnh sửa hồ sơ'),
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
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: AppColors.danger, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Avatar center display
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: AppColors.primaryLight,
                      backgroundImage: widget.profile.avatarUrl != null
                          ? NetworkImage(widget.profile.avatarUrl!)
                          : null,
                      child: widget.profile.avatarUrl == null
                          ? Text(
                              (widget.profile.displayName.isNotEmpty
                                      ? widget.profile.displayName[0]
                                      : 'U')
                                  .toUpperCase(),
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '@${widget.profile.username}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Form fields
              const Text(
                'Tên hiển thị *',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _displayNameController,
                enabled: !_busy,
                decoration: const InputDecoration(
                  hintText: 'Nhập tên hiển thị của bạn',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'Quốc gia / Khu vực',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _country,
                onChanged: _busy ? null : (val) => setState(() => _country = val ?? 'Việt Nam'),
                items: _countries.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.public_outlined),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Giới thiệu bản thân (Bio)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text(
                    '$_bioLength/160',
                    style: TextStyle(
                      fontSize: 12,
                      color: _bioLength > 160 ? AppColors.danger : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _bioController,
                enabled: !_busy,
                maxLines: 3,
                maxLength: 160,
                onChanged: (val) => setState(() => _bioLength = val.length),
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                decoration: const InputDecoration(
                  hintText: 'Chia sẻ ngắn gọn về bạn với cộng đồng HuTube...',
                ),
              ),
              const SizedBox(height: 32),

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
            ],
          ),
        ),
      ),
    );
  }
}
