import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth.dart';
import '../../channel/models/channel_models.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../content/content_models.dart';
import '../content/content_service.dart';
import 'creator_service.dart';

class VideoUploadScreen extends StatefulWidget {
  const VideoUploadScreen({
    super.key,
    required this.auth,
    required this.channel,
  });
  final AuthController auth;
  final ChannelDetail channel;

  @override
  State<VideoUploadScreen> createState() => _VideoUploadScreenState();
}

class _VideoUploadScreenState extends State<VideoUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _duration = TextEditingController();
  final _tags = TextEditingController();
  late final CreatorService _creator = CreatorService(widget.auth);
  late final ContentService _content = ContentService(widget.auth);
  List<Category> _categories = const [];
  XFile? _video;
  XFile? _thumbnail;
  String? _categoryId;
  String _visibility = 'private';
  bool _ageRestricted = false;
  bool _policyAccepted = false;
  bool _loadingCategories = true;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _duration.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _content.categories();
      if (mounted) {
        setState(() {
          _categories = categories;
          _loadingCategories = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  Future<void> _pickVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file != null && mounted) setState(() => _video = file);
  }

  Future<void> _pickThumbnail() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file != null && mounted) setState(() => _thumbnail = file);
  }

  String _typeFor(String name, {required bool video}) {
    final extension = name.split('.').last.toLowerCase();
    if (video) {
      return switch (extension) {
        'webm' => 'video/webm',
        'mov' => 'video/quicktime',
        'mkv' => 'video/x-matroska',
        _ => 'video/mp4',
      };
    }
    return extension == 'png' ? 'image/png' : 'image/jpeg';
  }

  Future<void> _upload() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_video == null) {
      setState(() => _error = AppStrings.t('upload.chooseVideo'));
      return;
    }
    if (!_policyAccepted) {
      setState(() => _error = AppStrings.t('upload.policyRequired'));
      return;
    }
    final duration = int.tryParse(_duration.text.trim());
    if (duration == null || duration <= 0) {
      setState(() => _error = AppStrings.t('upload.durationInvalid'));
      return;
    }
    final video = _video!;
    final contentType = _typeFor(video.name, video: true);
    setState(() => _uploading = true);
    try {
      final size = await video.length();
      final allowed = await _creator.preflight(
        channelId: widget.channel.id,
        fileSize: size,
        duration: duration,
        contentType: contentType,
        quality: '720p',
      );
      if (!allowed.allowed) {
        if (mounted) {
          setState(
            () => _error = AppStrings.format('upload.quotaExceeded', {
              'size': _bytes(allowed.maxUploadSize),
              'minutes': AppStrings.number(allowed.maxDuration ~/ 60),
            }),
          );
        }
        return;
      }
      final tags = _tags.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .take(10)
          .toList();
      await _creator.upload(
        channelId: widget.channel.id,
        title: _title.text,
        description: _description.text,
        categoryId: _categoryId,
        visibility: _visibility,
        ageRestricted: _ageRestricted,
        duration: duration,
        quality: '720p',
        tags: tags,
        video: MultipartFilePayload(
          field: 'Video',
          path: video.path,
          fileName: video.name,
          contentType: contentType,
        ),
        thumbnail: _thumbnail == null
            ? null
            : MultipartFilePayload(
                field: 'Thumbnail',
                path: _thumbnail!.path,
                fileName: _thumbnail!.name,
                contentType: _typeFor(_thumbnail!.name, video: false),
              ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _visibility == 'public'
                ? AppStrings.t('upload.publicSuccess')
                : AppStrings.t('upload.success'),
          ),
        ),
      );
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(
          () => _error = AppStrings.apiError(error, fallback: 'upload.error'),
        );
      }
    } on FileSystemException {
      if (mounted) {
        setState(() => _error = AppStrings.t('upload.fileReadError'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppStrings.t('upload.error'));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  static String _bytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppStrings.t('upload.title'))),
    body: SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _FilePicker(
              icon: Icons.video_file_outlined,
              title: _video?.name ?? AppStrings.t('upload.chooseVideo'),
              subtitle: _video == null
                  ? AppStrings.t('upload.videoQuotaHint')
                  : AppStrings.t('upload.selectedVideo'),
              onTap: _uploading ? null : _pickVideo,
            ),
            const SizedBox(height: 12),
            _FilePicker(
              icon: Icons.image_outlined,
              title: _thumbnail?.name ?? AppStrings.t('upload.chooseThumbnail'),
              subtitle: _thumbnail == null
                  ? AppStrings.t('upload.thumbnailHint')
                  : AppStrings.t('upload.selectedThumbnail'),
              onTap: _uploading ? null : _pickThumbnail,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _title,
              enabled: !_uploading,
              maxLength: 150,
              decoration: InputDecoration(
                labelText: AppStrings.t('upload.titleField'),
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? AppStrings.t('upload.titleRequired')
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _description,
              enabled: !_uploading,
              minLines: 3,
              maxLines: 6,
              maxLength: 5000,
              decoration: InputDecoration(
                labelText: AppStrings.t('creator.descriptionField'),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _duration,
              enabled: !_uploading,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: AppStrings.t('upload.durationField'),
                helperText: AppStrings.t('upload.durationHint'),
              ),
              validator: (value) => int.tryParse(value ?? '') == null
                  ? AppStrings.t('upload.durationInvalid')
                  : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: AppStrings.t('upload.topic'),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(AppStrings.t('upload.none')),
                ),
                ..._categories.map(
                  (category) => DropdownMenuItem<String?>(
                    value: category.id,
                    child: Text(category.name),
                  ),
                ),
              ],
              onChanged: _loadingCategories || _uploading
                  ? null
                  : (value) => setState(() => _categoryId = value),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _tags,
              enabled: !_uploading,
              decoration: InputDecoration(
                labelText: AppStrings.t('upload.tags'),
                helperText: AppStrings.t('upload.tagsHint'),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _visibility,
              decoration: InputDecoration(
                labelText: AppStrings.t('upload.visibility'),
              ),
              items: [
                DropdownMenuItem(
                  value: 'private',
                  child: Text(AppStrings.t('upload.private')),
                ),
                DropdownMenuItem(
                  value: 'unlisted',
                  child: Text(AppStrings.t('upload.unlisted')),
                ),
                DropdownMenuItem(
                  value: 'public',
                  child: Text(AppStrings.t('upload.public')),
                ),
              ],
              onChanged: _uploading
                  ? null
                  : (value) => setState(() => _visibility = value!),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _ageRestricted,
              onChanged: _uploading
                  ? null
                  : (value) => setState(() => _ageRestricted = value),
              title: Text(AppStrings.t('upload.ageLimit')),
              subtitle: Text(AppStrings.t('upload.ageRestrictionDescription')),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _policyAccepted,
              onChanged: _uploading
                  ? null
                  : (value) => setState(() => _policyAccepted = value ?? false),
              title: Text(AppStrings.t('upload.policyAgreement')),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton.icon(
              onPressed: _uploading ? null : _upload,
              icon: _uploading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(
                _uploading
                    ? AppStrings.t('upload.uploading')
                    : AppStrings.t('upload.uploadAction'),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: AppColors.primaryPink,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FilePicker extends StatelessWidget {
  const _FilePicker({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      leading: Icon(icon, color: AppColors.primaryPink),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );
}
