import 'package:flutter/material.dart';
import '../../../auth.dart';
import '../../../core/theme/app_theme.dart';
import '../models/account_models.dart';
import '../services/account_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  late final AccountService _accountService;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  NotificationSettingModel _settings = const NotificationSettingModel();

  @override
  void initState() {
    super.initState();
    _accountService = AccountService(widget.auth);
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _accountService.getNotificationSettings();
      if (mounted) {
        setState(() {
          _settings = res;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Không thể tải cài đặt thông báo.';
        });
      }
    }
  }

  Future<void> _save(NotificationSettingModel updated) async {
    setState(() {
      _settings = updated;
      _saving = true;
      _error = null;
    });

    try {
      final res = await _accountService.updateNotificationSettings(updated);
      if (mounted) {
        setState(() => _settings = res);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Không thể lưu cài đặt.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt thông báo'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : ListView(
                padding: const EdgeInsets.all(20),
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

                  _switchTile(
                    title: 'Video mới từ kênh đã đăng ký',
                    subtitle: 'Nhận thông báo khi kênh bạn theo dõi xuất bản video mới.',
                    value: _settings.notifyNewVideos,
                    onChanged: (val) => _save(_settings.copyWith(notifyNewVideos: val)),
                  ),
                  const Divider(height: 24),

                  _switchTile(
                    title: 'Bình luận & Phản hồi',
                    subtitle: 'Thông báo về hoạt động trên bình luận và video của bạn.',
                    value: _settings.notifyComments,
                    onChanged: (val) => _save(_settings.copyWith(notifyComments: val)),
                  ),
                  const Divider(height: 24),

                  _switchTile(
                    title: 'Hoạt động kênh đăng ký',
                    subtitle: 'Nhận tóm tắt về hoạt động của các kênh bạn quan tâm.',
                    value: _settings.notifySubscriptions,
                    onChanged: (val) => _save(_settings.copyWith(notifySubscriptions: val)),
                  ),
                  const Divider(height: 24),

                  _switchTile(
                    title: 'Email thông tin & Cập nhật sản phẩm',
                    subtitle: 'Nhận tin tức về các tính năng mới từ HuTube.',
                    value: _settings.notifyMarketing,
                    onChanged: (val) => _save(_settings.copyWith(notifyMarketing: val)),
                  ),

                  if (_saving) ...[
                    const SizedBox(height: 20),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        ),
                        SizedBox(width: 8),
                        Text('Đang tự động lưu...', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch.adaptive(
          value: value,
          activeTrackColor: AppColors.primary,
          activeThumbColor: Colors.white,
          onChanged: _saving ? null : onChanged,
        ),
      ],
    );
  }
}
