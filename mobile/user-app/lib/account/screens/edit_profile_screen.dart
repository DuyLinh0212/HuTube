import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../../core/widgets/unsaved_changes_guard.dart';
import '../models/account_models.dart';
import '../services/account_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.auth,
    required this.profile,
    this.imagePicker,
  });
  final AuthController auth;
  final UserProfile profile;
  final Future<XFile?> Function()? imagePicker;
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.displayName);
  late final _bio = TextEditingController(text: widget.profile.bio ?? '');
  late final _service = AccountService(widget.auth);
  late String _country = widget.profile.country ?? 'Việt Nam';
  late String _initialCountry = _country;
  late String? _avatar = widget.profile.avatarUrl;
  late final int _session = widget.auth.sessionGeneration;
  bool _countryEdited = false;
  bool _countryReady = false;
  bool _busy = false;
  bool _saved = false;
  String? _error;
  final _countries = [
    'Việt Nam',
    'Hoa Kỳ',
    'Nhật Bản',
    'Hàn Quốc',
    'Singapore',
    'Khác',
  ];
  bool get _current => mounted && _session == widget.auth.sessionGeneration;
  bool get _dirty =>
      !_saved &&
      (_name.text.trim() != widget.profile.displayName ||
          _bio.text.trim() != (widget.profile.bio ?? '') ||
          _country != _initialCountry);

  @override
  void initState() {
    super.initState();
    _name.addListener(_changed);
    _bio.addListener(_changed);
    if (!_countries.contains(_country)) _countries.add(_country);
    unawaited(_loadCountry());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCountry() async {
    try {
      final preferences = await _service.getPreferences();
      if (!_current) return;
      final location = preferences.location?.trim();
      setState(() {
        if (!_countryEdited && location != null && location.isNotEmpty) {
          _country = location;
          _initialCountry = location;
          if (!_countries.contains(location)) _countries.add(location);
        }
        _countryReady = true;
      });
    } catch (_) {
      /* Never overwrite a location that could not be loaded. */
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_current || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await _service.updateProfile(
        displayName: _name.text.trim(),
        bio: _bio.text.trim(),
        country: _countryReady || _countryEdited ? _country : null,
      );
      if (!_current) return;
      setState(() {
        _saved = true;
        _busy = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_current) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.t('profile.updated'))));
      Navigator.of(context).pop(updated);
    } on ApiFailure catch (e) {
      if (_current) {
        setState(
          () => _error = AppStrings.apiError(
            e,
            fallback: 'editProfile.saveError',
          ),
        );
      }
    } catch (_) {
      if (_current) {
        setState(() => _error = AppStrings.t('editProfile.saveError'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAvatar() async {
    if (_busy) return;
    try {
      final image =
          await (widget.imagePicker?.call() ??
              ImagePicker().pickImage(
                source: ImageSource.gallery,
                imageQuality: 90,
                maxWidth: 1200,
              ));
      if (image == null || !_current) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      final profile = await _service.uploadAvatar(image);
      if (_current) setState(() => _avatar = profile.avatarUrl);
    } on ApiFailure catch (e) {
      if (_current) setState(() => _error = AppStrings.apiError(e));
    } catch (_) {
      if (_current) setState(() => _error = AppStrings.t('common.error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return UnsavedChangesGuard(
      dirty: _dirty,
      busy: _busy,
      child: Scaffold(
        appBar: AppBar(title: Text(AppStrings.t('editProfile.title'))),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Material(
            color: colors.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: FilledButton.icon(
                  key: const ValueKey('profile-save'),
                  onPressed: _busy || !_dirty ? null : _save,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded, size: 20),
                  label: Text(AppStrings.t('editProfile.saveBtn')),
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Form(
                key: _form,
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    if (_error != null) ...[
                      ErrorBanner(message: _error!),
                      const SizedBox(height: 16),
                    ],
                    HuTubeSurface(
                      padding: const EdgeInsets.all(18),
                      borderRadius: 20,
                      child: Row(
                        children: [
                          HuTubeAvatar(
                            url: _avatar,
                            label: _name.text,
                            radius: 32,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _name.text.trim().isEmpty
                                      ? widget.profile.displayName
                                      : _name.text.trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '@${widget.profile.username}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _busy ? null : _pickAvatar,
                                  icon: const Icon(
                                    Icons.add_a_photo_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    AppStrings.t('editProfile.changeAvatar'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppStrings.t('editProfile.publicInfo'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      AppStrings.t('editProfile.publicInfoHint'),
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    HuTubeSurface(
                      padding: const EdgeInsets.all(16),
                      borderRadius: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            key: const ValueKey('profile-display-name'),
                            controller: _name,
                            enabled: !_busy,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            maxLength: 100,
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? AppStrings.t(
                                    'editProfile.displayNameRequired',
                                  )
                                : null,
                            decoration: InputDecoration(
                              labelText: AppStrings.t(
                                'editProfile.displayName',
                              ),
                              hintText: AppStrings.t(
                                'editProfile.displayNameHint',
                              ),
                              prefixIcon: const Icon(
                                Icons.person_outline_rounded,
                              ),
                              counterText: '',
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            key: const ValueKey('profile-bio'),
                            controller: _bio,
                            enabled: !_busy,
                            minLines: 3,
                            maxLines: 5,
                            maxLength: 160,
                            decoration: InputDecoration(
                              labelText: AppStrings.t('editProfile.bio'),
                              alignLabelWithHint: true,
                              hintText: AppStrings.t('editProfile.bioHint'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppStrings.t('editProfile.country'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('profile-country-$_initialCountry'),
                      isExpanded: true,
                      initialValue: _country,
                      items: _countries
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(
                                _countryLabel(value),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                              _country = value!;
                              _countryEdited = true;
                            }),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.public_outlined),
                        helperText: AppStrings.t('editProfile.countryHint'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _countryLabel(String value) => switch (value) {
    'Việt Nam' => AppStrings.t('editProfile.countryVietnam'),
    'Hoa Kỳ' => AppStrings.t('editProfile.countryUs'),
    'Nhật Bản' => AppStrings.t('editProfile.countryJapan'),
    'Hàn Quốc' => AppStrings.t('editProfile.countryKorea'),
    'Singapore' => AppStrings.t('editProfile.countrySingapore'),
    'Khác' => AppStrings.t('editProfile.countryOther'),
    _ => value,
  };
}
