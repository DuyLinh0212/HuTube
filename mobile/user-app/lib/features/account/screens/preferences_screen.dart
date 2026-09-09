import 'package:flutter/material.dart';
import '../../../auth.dart';
import '../../../core/theme/app_theme.dart';
import '../models/account_models.dart';
import '../services/account_service.dart';

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  late final AccountService _accountService;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  UserPreferencesModel _preferences = const UserPreferencesModel();

  @override
  void initState() {
    super.initState();
    _accountService = AccountService(widget.auth);
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _accountService.getPreferences();
      if (mounted) {
        setState(() {
          _preferences = res;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Không thể tải cài đặt & giao diện.';
        });
      }
    }
  }

  Future<void> _save(UserPreferencesModel updated) async {
    setState(() {
      _preferences = updated;
      _saving = true;
      _error = null;
    });

    try {
      final res = await _accountService.updatePreferences(updated);
      if (mounted) setState(() => _preferences = res);
    } catch (_) {
      if (mounted) setState(() => _error = 'Không thể lưu cài đặt.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt & Giao diện'),
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

                  // Theme Selection
                  const Text(
                    'Giao diện ứng dụng',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _themeOption('system', 'Hệ thống', Icons.settings_suggest_outlined),
                      const SizedBox(width: 8),
                      _themeOption('light', 'Sáng', Icons.light_mode_outlined),
                      const SizedBox(width: 8),
                      _themeOption('dark', 'Tối', Icons.dark_mode_outlined),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Playback
                  const Text(
                    'Phát video',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  _switchTile(
                    title: 'Tự động phát video tiếp theo',
                    subtitle: 'Tiếp tục phát các video liên quan khi video hiện tại kết thúc.',
                    value: _preferences.autoplayNext,
                    onChanged: (val) => _save(_preferences.copyWith(autoplayNext: val)),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chất lượng video mặc định',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                          Text(
                            'Áp dụng khi xem video',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                      DropdownButton<String>(
                        value: _preferences.defaultPlaybackQuality,
                        underline: const SizedBox(),
                        onChanged: _saving
                            ? null
                            : (val) {
                                if (val != null) {
                                  _save(_preferences.copyWith(defaultPlaybackQuality: val));
                                }
                              },
                        items: const [
                          DropdownMenuItem(value: 'auto', child: Text('Tự động')),
                          DropdownMenuItem(value: '1080p', child: Text('1080p (FHD)')),
                          DropdownMenuItem(value: '720p', child: Text('720p (HD)')),
                          DropdownMenuItem(value: '480p', child: Text('480p (SD)')),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Privacy
                  const Text(
                    'Quyền riêng tư',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  _switchTile(
                    title: 'Giữ các kênh đã đăng ký ở chế độ riêng tư',
                    subtitle: 'Không hiển thị danh sách kênh bạn đăng ký trên trang cá nhân.',
                    value: _preferences.keepSubscriptionsPrivate,
                    onChanged: (val) => _save(_preferences.copyWith(keepSubscriptionsPrivate: val)),
                  ),
                  const Divider(height: 24),
                  _switchTile(
                    title: 'Giữ danh sách phát đã lưu riêng tư',
                    subtitle: 'Chỉ bạn mới có thể xem các playlist đã tạo và lưu.',
                    value: _preferences.keepPlaylistsPrivate,
                    onChanged: (val) => _save(_preferences.copyWith(keepPlaylistsPrivate: val)),
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

  Widget _themeOption(String key, String label, IconData icon) {
    final selected = _preferences.theme == key;
    return Expanded(
      child: GestureDetector(
        onTap: _saving ? null : () => _save(_preferences.copyWith(theme: key)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryLight : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? AppColors.primary : AppColors.textSecondary, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ],
          ),
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
