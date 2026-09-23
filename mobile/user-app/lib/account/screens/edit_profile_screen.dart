import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/error_banner.dart';
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
  late String? _avatarUrl;
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
    _displayNameController = TextEditingController(
      text: widget.profile.displayName,
    );
    _bioController = TextEditingController(text: widget.profile.bio ?? '');
    _bioLength = _bioController.text.length;
    _country = widget.profile.country ?? 'Việt Nam';
    _avatarUrl = widget.profile.avatarUrl;
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
      setState(() => _error = AppStrings.t('editProfile.displayNameRequired'));
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
          SnackBar(
            content: Text(AppStrings.t('profile.updated')),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(updated);
      }
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(
          () => _error = AppStrings.apiError(e, fallback: 'common.error'),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppStrings.t('editProfile.saveError'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1200,
    );
    if (image == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = await _accountService.uploadAvatar(image);
      if (mounted) setState(() => _avatarUrl = profile.avatarUrl);
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _error = AppStrings.apiError(error));
    } catch (_) {
      if (mounted) setState(() => _error = AppStrings.t('common.error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.t('editProfile.title')),
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
                ErrorBanner(message: _error!),
                const SizedBox(height: 16),
              ],

              // Avatar center display
              Center(
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: AppColors.primaryPink.withValues(
                    alpha: 0.15,
                  ),
                  backgroundImage: _avatarUrl != null
                      ? NetworkImage(_avatarUrl!)
                      : null,
                  child: _avatarUrl == null
                      ? Text(
                          (widget.profile.displayName.isNotEmpty
                                  ? widget.profile.displayName[0]
                                  : 'U')
                              .toUpperCase(),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryPink,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _busy ? null : _pickAvatar,
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: const Text('Đổi ảnh đại diện'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '@${widget.profile.username}',
                  style: TextStyle(
                    color: AppColors.textSecondaryFor(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Form fields
              Text(
                '${AppStrings.t('editProfile.displayName')} *',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _displayNameController,
                enabled: !_busy,
                decoration: InputDecoration(
                  hintText: AppStrings.t('editProfile.displayNameHint'),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                '${AppStrings.t('editProfile.country')} / ${AppStrings.t('editProfile.region')}',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _country,
                onChanged: _busy
                    ? null
                    : (val) => setState(() => _country = val ?? 'Việt Nam'),
                items: _countries
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(_countryLabel(c)),
                      ),
                    )
                    .toList(),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.public_outlined),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${AppStrings.t('editProfile.bio')} (Bio)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text(
                    '$_bioLength/160',
                    style: TextStyle(
                      fontSize: 12,
                      color: _bioLength > 160
                          ? AppColors.dangerFor(context)
                          : AppColors.textMutedFor(context),
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
                buildCounter:
                    (
                      context, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
                decoration: InputDecoration(
                  hintText: AppStrings.t('editProfile.bioHint'),
                ),
              ),
              const SizedBox(height: 32),

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
                    : Text(AppStrings.t('editProfile.saveBtn')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _countryLabel(String value) {
    return switch (value) {
      'Việt Nam' => AppStrings.t('editProfile.countryVietnam'),
      'Hoa Kỳ' => AppStrings.t('editProfile.countryUs'),
      'Nhật Bản' => AppStrings.t('editProfile.countryJapan'),
      'Hàn Quốc' => AppStrings.t('editProfile.countryKorea'),
      'Singapore' => AppStrings.t('editProfile.countrySingapore'),
      'Khác' => AppStrings.t('editProfile.countryOther'),
      _ => value,
    };
  }
}
