import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/error_banner.dart';
import '../models/channel_models.dart';
import '../services/channel_service.dart';

typedef ChannelImagePicker = Future<XFile?> Function(bool avatar);

class ChannelSettingsScreen extends StatefulWidget {
  const ChannelSettingsScreen({
    super.key,
    required this.auth,
    required this.channel,
    this.imagePicker,
  });

  final AuthController auth;
  final ChannelDetail channel;
  final ChannelImagePicker? imagePicker;

  @override
  State<ChannelSettingsScreen> createState() => _ChannelSettingsScreenState();
}

class _ChannelSettingsScreenState extends State<ChannelSettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _inviteEmailController;
  late final ChannelService _channelService;
  late ChannelDetail _channel;
  final ImagePicker _picker = ImagePicker();
  List<ChannelRole> _roles = const [];
  List<ChannelInvitation> _pendingInvitations = const [];
  String _inviteRole = 'editor';

  bool _busy = false;
  String? _revokingInvitationId;
  bool _uploadingAvatar = false;
  bool _uploadingBanner = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _channel = widget.channel;
    _channelService = ChannelService(widget.auth);
    _nameController = TextEditingController(text: _channel.name);
    _descriptionController = TextEditingController(
      text: _channel.description ?? '',
    );
    _inviteEmailController = TextEditingController();
    _loadInviteData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _inviteEmailController.dispose();
    super.dispose();
  }

  Future<void> _loadInviteData() async {
    try {
      final roles = await _channelService.getRoles();
      if (mounted) setState(() => _roles = roles);
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(
          () => _error = AppStrings.apiError(error, fallback: 'common.error'),
        );
      }
    } catch (_) {
      // The form keeps its safe Editor default when role metadata is unavailable.
    }

    if (!_canInvite) return;
    try {
      final invitations = await _channelService.getPendingInvitations(
        _channel.id,
      );
      if (mounted) setState(() => _pendingInvitations = invitations);
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(
          () => _error = AppStrings.apiError(error, fallback: 'common.error'),
        );
      }
    } catch (_) {
      // Role and invitation metadata are auxiliary to channel editing.
    }
  }

  Future<void> _reloadPendingInvitations() async {
    if (!_canInvite) return;
    try {
      final invitations = await _channelService.getPendingInvitations(
        _channel.id,
      );
      if (mounted) setState(() => _pendingInvitations = invitations);
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(
          () => _error = AppStrings.apiError(error, fallback: 'common.error'),
        );
      }
    } catch (_) {
      // Keep the invitation that was just created visible if a refresh fails.
    }
  }

  bool get _canInvite =>
      _channel.isOwner || _channel.permissions.contains('member.invite');

  String _roleName(String code) {
    final localized = switch (code) {
      'manager' => AppStrings.t('channel.roleManager'),
      'editor' => AppStrings.t('channel.roleEditor'),
      'moderator' => AppStrings.t('channel.roleModerator'),
      'viewer' => AppStrings.t('channel.roleViewer'),
      _ => null,
    };
    return localized ??
        _roles.where((role) => role.code == code).firstOrNull?.name ??
        code;
  }

  String _roleDescription(String code) {
    final localized = switch (code) {
      'manager' => AppStrings.t('channel.roleManagerDescription'),
      'editor' => AppStrings.t('channel.roleEditorDescription'),
      'moderator' => AppStrings.t('channel.roleModeratorDescription'),
      'viewer' => AppStrings.t('channel.roleViewerDescription'),
      _ => null,
    };
    return localized ??
        _roles.where((role) => role.code == code).firstOrNull?.description ??
        '';
  }

  String _formatInvitationExpiry(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return AppStrings.t('channel.invitationExpiryUnknown');
    final formattedDate = AppStrings.date(date);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return AppStrings.format('channel.invitationExpiry', {
      'date': formattedDate,
      'time': '$hour:$minute',
    });
  }

  Future<void> _revokeInvitation(ChannelInvitation invitation) async {
    final shouldRevoke = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.t('channel.confirmRevoke')),
        content: Text(
          AppStrings.format('channel.invitationRevokeDescription', {
            'email': invitation.invitedEmail ?? AppStrings.t('common.user'),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppStrings.t('channel.revoke')),
          ),
        ],
      ),
    );
    if (shouldRevoke != true || !mounted) return;

    setState(() {
      _revokingInvitationId = invitation.id;
      _error = null;
    });
    try {
      await _channelService.revokeInvitation(_channel.id, invitation.id);
      if (!mounted) return;
      setState(
        () => _pendingInvitations = _pendingInvitations
            .where((item) => item.id != invitation.id)
            .toList(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.t('channel.inviteRevoked')),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(
          () => _error = AppStrings.apiError(error, fallback: 'common.error'),
        );
      }
    } finally {
      if (mounted) setState(() => _revokingInvitationId = null);
    }
  }

  Widget _pendingInvitationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppStrings.t('channel.pendingInvites'),
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        if (_pendingInvitations.isEmpty)
          Text(
            AppStrings.t('channel.noPendingInvitations'),
            style: TextStyle(
              color: AppColors.textSecondaryFor(context),
              fontSize: 13,
            ),
          ),
        for (final invitation in _pendingInvitations)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceFor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderFor(context)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.mail_outline, color: AppColors.primaryPink),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invitation.invitedEmail ??
                            AppStrings.t('channel.unknownEmail'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_roleName(invitation.roleCode)} · ${_formatInvitationExpiry(invitation.expiresAt)}',
                        style: TextStyle(
                          color: AppColors.textSecondaryFor(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: AppStrings.t('channel.revokeInvitationTooltip'),
                  onPressed: _busy || _revokingInvitationId != null
                      ? null
                      : () => _revokeInvitation(invitation),
                  icon: _revokingInvitationId == invitation.id
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _invite() async {
    final email = _inviteEmailController.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = AppStrings.t('channel.emailInvalid'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _channelService.inviteMember(_channel.id, email, _inviteRole);
      if (!mounted) return;
      _inviteEmailController.clear();
      await _reloadPendingInvitations();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.t('channel.inviteSent')),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(
          () => _error = AppStrings.apiError(error, fallback: 'common.error'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = AppStrings.t('channel.nameEmpty'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _channelService.updateChannel(
        _channel.id,
        name: name,
        description: _descriptionController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.t('channel.updateSuccess')),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = AppStrings.apiError(e, fallback: 'channel.updateError'),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = AppStrings.t('channel.updateError'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canEditBranding =>
      _channel.isOwner ||
      _channel.permissions.contains('channel.edit_branding');

  Future<XFile?> _pickFromGallery(bool avatar) {
    final customPicker = widget.imagePicker;
    if (customPicker != null) return customPicker(avatar);
    return _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: avatar ? 1200 : 2560,
      maxHeight: avatar ? 1200 : 1440,
      imageQuality: 88,
      requestFullMetadata: false,
    );
  }

  Future<void> _pickAndUpload(bool avatar) async {
    if (!_canEditBranding || _busy || _uploadingAvatar || _uploadingBanner) {
      return;
    }
    try {
      final file = await _pickFromGallery(avatar);
      if (file == null || !mounted) return;
      setState(() {
        _error = null;
        if (avatar) {
          _uploadingAvatar = true;
        } else {
          _uploadingBanner = true;
        }
      });
      final updated = avatar
          ? await _channelService.uploadAvatar(_channel.id, file)
          : await _channelService.uploadBanner(_channel.id, file);
      if (!mounted) return;
      setState(() => _channel = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            avatar
                ? AppStrings.t('channel.avatarUpdated')
                : AppStrings.t('channel.bannerUpdated'),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(
          () => _error = AppStrings.apiError(
            error,
            fallback: 'channel.imageError',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppStrings.t('channel.imageReadError'));
      }
    } finally {
      if (mounted) {
        setState(() {
          if (avatar) {
            _uploadingAvatar = false;
          } else {
            _uploadingBanner = false;
          }
        });
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirmController = TextEditingController();
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final matches = confirmController.text.trim() == _channel.name.trim();
          return AlertDialog(
            title: Text(AppStrings.t('channel.confirmDeleteTitle')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.t('channel.confirmDeleteDescription'),
                  style: TextStyle(
                    color: AppColors.dangerFor(context),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  AppStrings.format('channel.confirmDeletePrompt', {
                    'name': _channel.name,
                  }),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmController,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    hintText: AppStrings.t('channel.confirmDeleteHint'),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(AppStrings.t('common.cancel')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.dangerFor(context),
                  minimumSize: const Size(120, 44),
                ),
                onPressed: matches ? () => Navigator.of(ctx).pop(true) : null,
                child: Text(AppStrings.t('channel.confirmDeleteAction')),
              ),
            ],
          );
        },
      ),
    );

    if (shouldDelete == true) {
      setState(() => _busy = true);
      try {
        await _channelService.deleteChannel(_channel.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppStrings.t('channel.deleteSuccess')),
              backgroundColor: AppColors.dangerFor(context),
              behavior: SnackBarBehavior.floating,
            ),
          );
          // Pop twice to go back to Profile
          Navigator.of(context).pop();
          Navigator.of(context).pop(true);
        }
      } on ApiFailure catch (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = AppStrings.apiError(e, fallback: 'channel.deleteError');
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = AppStrings.t('channel.deleteError');
          });
        }
      }
    }
  }

  Widget _bannerEditor() {
    final url = _channel.bannerUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            key: const ValueKey('channel-banner-preview'),
            height: 132,
            color: AppColors.primaryPink.withValues(alpha: 0.15),
            child: url == null || url.isEmpty
                ? const Center(
                    child: Icon(
                      Icons.panorama_outlined,
                      size: 42,
                      color: AppColors.primaryPink,
                    ),
                  )
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    semanticLabel: AppStrings.t(
                      'channel.currentBannerSemantic',
                    ),
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(Icons.broken_image_outlined, size: 40),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('upload-channel-banner'),
          onPressed: _uploadingBanner || _uploadingAvatar
              ? null
              : () => _pickAndUpload(false),
          icon: _uploadingBanner
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            _uploadingBanner
                ? AppStrings.t('channel.uploadingBanner')
                : AppStrings.t('channel.changeBanner'),
          ),
        ),
      ],
    );
  }

  Widget _avatarEditor() {
    final url = _channel.avatarUrl;
    return Column(
      children: [
        CircleAvatar(
          key: const ValueKey('channel-avatar-preview'),
          radius: 48,
          backgroundColor: AppColors.primaryPink.withValues(alpha: 0.15),
          backgroundImage: url == null || url.isEmpty
              ? null
              : NetworkImage(url),
          child: url == null || url.isEmpty
              ? Text(
                  _channel.name.isEmpty ? 'C' : _channel.name[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primaryPink,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('upload-channel-avatar'),
          onPressed: _uploadingAvatar || _uploadingBanner
              ? null
              : () => _pickAndUpload(true),
          icon: _uploadingAvatar
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.account_circle_outlined),
          label: Text(
            _uploadingAvatar
                ? AppStrings.t('channel.uploadingAvatar')
                : AppStrings.t('channel.changeAvatar'),
          ),
        ),
      ],
    );
  }

  Widget _brandingSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceFor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderFor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.t('channel.brandingTitle'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 5),
          Text(
            AppStrings.t('channel.brandingDescription'),
            style: TextStyle(
              color: AppColors.textSecondaryFor(context),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          _bannerEditor(),
          const SizedBox(height: 18),
          _avatarEditor(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.t('channel.settingsTitle')),
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

              if (_canEditBranding) ...[
                _brandingSection(),
                const SizedBox(height: 28),
              ],

              Text(
                AppStrings.t('channel.basicInfo'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),

              Text(
                '${AppStrings.t('channel.createName')} *',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                enabled: !_busy,
                decoration: InputDecoration(
                  hintText: AppStrings.t('channel.nameHint'),
                  prefixIcon: Icon(Icons.tv_outlined),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                '${AppStrings.t('channel.createHandle')} (Handle)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextFormField(
                initialValue: '@${_channel.handle}',
                readOnly: true,
                enabled: false,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.alternate_email),
                  helperText: AppStrings.t('channel.handleImmutable'),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                AppStrings.t('channel.createDescription'),
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descriptionController,
                enabled: !_busy,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: AppStrings.t('channel.descriptionHintEdit'),
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
                    : Text(AppStrings.t('common.save')),
              ),

              if (_channel.permissions.contains('member.invite') ||
                  _channel.isOwner) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 22),
                Text(
                  AppStrings.t('channel.inviteHeading'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppStrings.t('channel.inviteDescription'),
                  style: TextStyle(
                    color: AppColors.textSecondaryFor(context),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _inviteEmailController,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: AppStrings.t('channel.inviteEmail'),
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _inviteRole,
                  decoration: InputDecoration(
                    labelText: AppStrings.t('channel.inviteRole'),
                  ),
                  items:
                      (_roles.isEmpty
                              ? [
                                  ChannelRole(
                                    code: 'editor',
                                    name: AppStrings.t('channel.roleEditor'),
                                    description: '',
                                  ),
                                ]
                              : _roles)
                          .map(
                            (role) => DropdownMenuItem(
                              value: role.code,
                              child: Text(_roleName(role.code)),
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
                    _roleDescription(_inviteRole),
                    style: TextStyle(
                      color: AppColors.textSecondaryFor(context),
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _busy || _revokingInvitationId != null
                      ? null
                      : _invite,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(AppStrings.t('channel.inviteAction')),
                ),
                const SizedBox(height: 18),
                _pendingInvitationsSection(),
              ],

              const SizedBox(height: 36),
              const Divider(),
              const SizedBox(height: 24),

              // Danger Zone
              if (_channel.permissions.contains('channel.delete') ||
                  _channel.isOwner)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.dangerContainerFor(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.dangerFor(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: AppColors.dangerFor(context),
                          ),
                          SizedBox(width: 8),
                          Text(
                            AppStrings.t('channel.dangerTitle'),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.dangerFor(context),
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppStrings.t('channel.dangerDescription'),
                        style: TextStyle(
                          color: AppColors.onDangerContainerFor(context),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.dangerFor(context),
                          side: BorderSide(color: AppColors.dangerFor(context)),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: _busy ? null : _confirmDelete,
                        child: Text(AppStrings.t('channel.deleteThis')),
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
