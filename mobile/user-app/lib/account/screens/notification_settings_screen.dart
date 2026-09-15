import 'package:flutter/material.dart';
import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/error_banner.dart';
import '../models/account_models.dart';
import '../services/account_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
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
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = AppStrings.apiError(e, fallback: 'notif.loadError');
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = AppStrings.t('notif.loadError');
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
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(
          () => _error = AppStrings.apiError(e, fallback: 'notif.saveError'),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppStrings.t('notif.saveError'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.t('notif.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primaryPink),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null) ...[
                    ErrorBanner(message: _error!),
                    const SizedBox(height: 16),
                  ],

                  _switchTile(
                    title: AppStrings.t('notifications.videoUpdates'),
                    subtitle: AppStrings.t('notifications.videoUpdatesDesc'),
                    value: _settings.notifyNewVideos,
                    onChanged: (val) =>
                        _save(_settings.copyWith(notifyNewVideos: val)),
                  ),
                  const Divider(height: 24),

                  _switchTile(
                    title: AppStrings.t('notifications.comments'),
                    subtitle: AppStrings.t('notifications.commentsDesc'),
                    value: _settings.notifyComments,
                    onChanged: (val) =>
                        _save(_settings.copyWith(notifyComments: val)),
                  ),
                  const Divider(height: 24),

                  _switchTile(
                    title: AppStrings.t('notifications.channelActivity'),
                    subtitle: AppStrings.t('notifications.channelActivityDesc'),
                    value: _settings.notifySubscriptions,
                    onChanged: (val) =>
                        _save(_settings.copyWith(notifySubscriptions: val)),
                  ),
                  const Divider(height: 24),

                  _switchTile(
                    title: AppStrings.t('notifications.marketing'),
                    subtitle: AppStrings.t('notifications.marketingDesc'),
                    value: _settings.notifyMarketing,
                    onChanged: (val) =>
                        _save(_settings.copyWith(notifyMarketing: val)),
                  ),

                  if (_saving) ...[
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primaryPink,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          AppStrings.t('notif.autoSaving'),
                          style: TextStyle(
                            color: AppColors.textSecondaryFor(context),
                            fontSize: 12,
                          ),
                        ),
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
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: AppColors.textSecondaryFor(context),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch.adaptive(
          value: value,
          activeTrackColor: AppColors.primaryPink,
          activeThumbColor: Colors.white,
          onChanged: _saving ? null : onChanged,
        ),
      ],
    );
  }
}
