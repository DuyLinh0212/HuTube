import 'dart:async';
import 'dart:io';

import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth.dart';
import '../../channel/models/channel_models.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../content/content_models.dart';
import '../content/content_service.dart';
import '../plans/plan_service.dart';
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
  final _tags = TextEditingController();
  late final CreatorService _creator = CreatorService(widget.auth);
  late final ContentService _content = ContentService(widget.auth);
  List<Category> _categories = const [];
  XFile? _video;
  XFile? _thumbnail;
  NativeVideoPlayerController? _previewPlayer;
  int _durationSeconds = 0;
  String? _categoryId;
  List<VideoDetail> _relatedVideos = const [];
  final List<Map<String, dynamic>> _videoCards = [];
  String? _selectedRelatedVideoId;
  final _relatedTime = TextEditingController(text: '0:00');
  String _visibility = 'private';
  bool _ageRestricted = false;
  bool _canPromote = false;
  bool _promotionEnabled = false;
  bool _policyAccepted = false;
  bool _loadingCategories = true;
  bool _loadingRelatedVideos = true;
  bool _uploading = false;
  String? _error;
  final List<Map<String, dynamic>> _chapters = [];

  List<VideoDetail> get _availableRelatedVideos => _relatedVideos
      .where(
        (item) => !_videoCards.any((card) => card['videoId'] == item.id),
      )
      .toList();

  void _addChapter() {
    setState(() {
      final lastSec = _chapters.isEmpty
          ? 0
          : (_chapters.last['startSeconds'] as int) + 60;
      _chapters.add({
        'startSeconds': lastSec,
        'title': 'Chương ${_chapters.length + 1}',
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadRelatedVideos();
    _loadPromotionEntitlement();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _tags.dispose();
    _relatedTime.dispose();
    unawaited(_previewPlayer?.dispose());
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
    if (file == null || !mounted) return;
    final oldPlayer = _previewPlayer;
    setState(() {
      _video = file;
      _previewPlayer = null;
      _durationSeconds = 0;
      _error = null;
      if (_title.text.trim().isEmpty) {
        final rawName = file.name.split('.').first;
        _title.text = rawName.replaceAll('_', ' ').replaceAll('-', ' ');
      }
    });
    unawaited(oldPlayer?.dispose());
    final player = NativeVideoPlayerController(
      id: DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
      autoPlay: false,
      showNativeControls: true,
    );
    setState(() => _previewPlayer = player);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_previewPlayer, player)) {
        unawaited(_initializePreview(player, file));
      }
    });
  }

  Future<void> _initializePreview(
    NativeVideoPlayerController player,
    XFile file,
  ) async {
    try {
      final durationFuture = player.durationStream
          .firstWhere((duration) => duration > Duration.zero)
          .timeout(const Duration(seconds: 20));
      await player.initialize();
      await player.loadFile(path: file.path);
      final duration = await durationFuture;
      if (!mounted || !identical(_previewPlayer, player) || _video != file) {
        return;
      }
      setState(() => _durationSeconds = duration.inSeconds);
    } catch (_) {
      if (mounted && identical(_previewPlayer, player)) {
        setState(() => _error = AppStrings.t('upload.previewError'));
      }
    }
  }

  Future<void> _loadRelatedVideos() async {
    try {
      final result = await loadAllPages(
        (page) => _creator.managedVideos(widget.channel.id, page: page),
      );
      if (!mounted) return;
      setState(() {
        _relatedVideos = result.items
            .where(
              (item) =>
                  item.processingStatus == 'published' &&
                  item.moderationStatus == 'approved' &&
                  item.visibility == 'public' &&
                  item.publishedAt != null,
            )
            .toList();
        _loadingRelatedVideos = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRelatedVideos = false);
    }
  }

  Future<void> _loadPromotionEntitlement() async {
    try {
      final plan = await PlanService(widget.auth).myPlan();
      final features = plan?['features'];
      final allowed = features is Map && features['video_promotion'] == true;
      if (mounted) setState(() => _canPromote = allowed);
    } catch (_) {
      if (mounted) setState(() => _canPromote = false);
    }
  }

  static int _parseVideoCardTime(String value) {
    final match = RegExp(r'^(\d+):([0-5]?\d)$').firstMatch(value.trim());
    if (match == null) return -1;
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  static String _formatVideoCardTime(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  void _addVideoCard() {
    final videoId = _selectedRelatedVideoId;
    final seconds = _parseVideoCardTime(_relatedTime.text);
    if (videoId == null ||
        seconds < 0 ||
        seconds >= _durationSeconds ||
        _videoCards.length >= 5 ||
        _videoCards.any(
          (card) =>
              card['videoId'] == videoId || card['startSeconds'] == seconds,
        )) {
      setState(() => _error = AppStrings.t('upload.videoCardFieldsInvalid'));
      return;
    }
    setState(() {
      _videoCards.add({'videoId': videoId, 'startSeconds': seconds});
      _videoCards.sort(
        (left, right) => (left['startSeconds'] as int).compareTo(
          right['startSeconds'] as int,
        ),
      );
      _selectedRelatedVideoId = null;
      _relatedTime.text = '0:00';
      _error = null;
    });
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
    final duration = _durationSeconds;
    if (duration <= 0) {
      setState(() => _error = AppStrings.t('upload.durationInvalid'));
      return;
    }
    if (_videoCards.any((card) {
      final seconds = card['startSeconds'] as int;
      return seconds < 0 || seconds >= duration;
    })) {
      setState(() => _error = AppStrings.t('upload.videoCardsInvalid'));
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
        chapters: _chapters,
        videoCards: _videoCards,
        promotionEnabled: _canPromote && _promotionEnabled,
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.violetContainerFor(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.violet.withValues(alpha: .15),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    color: AppColors.violet,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppStrings.t('upload.videoQuotaHint'),
                      style: const TextStyle(
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _FilePicker(
              customIcon: AppIcons.asset(AppIcons.upload, size: 24),
              title: _video?.name ?? AppStrings.t('upload.chooseVideo'),
              subtitle: _video == null
                  ? AppStrings.t('upload.videoQuotaHint')
                  : AppStrings.t('upload.selectedVideo'),
              onTap: _uploading ? null : _pickVideo,
            ),
            if (_video != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _previewPlayer == null
                      ? const Center(child: CircularProgressIndicator())
                      : NativeVideoPlayer(controller: _previewPlayer!),
                ),
              ),
            ],
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
              maxLength: 100,
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
            InputDecorator(
              decoration: InputDecoration(
                labelText: AppStrings.t('upload.durationField'),
                helperText: AppStrings.t('upload.durationHint'),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _durationSeconds > 0
                      ? _formatVideoCardTime(_durationSeconds)
                      : _video == null
                      ? AppStrings.t('upload.durationWaitingForVideo')
                      : AppStrings.t('upload.preparing'),
                ),
              ),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Chương video (Chapters)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                TextButton.icon(
                  onPressed: _uploading ? null : _addChapter,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Thêm chương'),
                ),
              ],
            ),
            if (_chapters.isNotEmpty)
              ..._chapters.asMap().entries.map((entry) {
                final idx = entry.key;
                final ch = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 80,
                        child: TextFormField(
                          initialValue: '${ch['startSeconds']}',
                          enabled: !_uploading,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Giây',
                            isDense: true,
                          ),
                          onChanged: (val) {
                            ch['startSeconds'] = int.tryParse(val) ?? 0;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          initialValue: '${ch['title']}',
                          enabled: !_uploading,
                          decoration: const InputDecoration(
                            labelText: 'Tiêu đề chương',
                            isDense: true,
                          ),
                          onChanged: (val) {
                            ch['title'] = val.trim();
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: _uploading
                            ? null
                            : () => setState(() => _chapters.removeAt(idx)),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 14),
            Text(
              AppStrings.t('upload.relatedVideos'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.t('upload.relatedVideosHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_loadingRelatedVideos)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              )
            else if (_availableRelatedVideos.isNotEmpty &&
                _videoCards.length < 5) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedRelatedVideoId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: AppStrings.t('upload.relatedVideoSelect'),
                ),
                items: _availableRelatedVideos
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _uploading || _durationSeconds <= 0
                    ? null
                    : (value) =>
                          setState(() => _selectedRelatedVideoId = value),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _relatedTime,
                      enabled: !_uploading,
                      keyboardType: TextInputType.datetime,
                      decoration: InputDecoration(
                        labelText: AppStrings.t('upload.relatedVideoTime'),
                        hintText: '0:00',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _uploading ||
                            _durationSeconds <= 0 ||
                            _selectedRelatedVideoId == null
                        ? null
                        : _addVideoCard,
                    icon: const Icon(Icons.add),
                    label: Text(AppStrings.t('upload.addRelatedVideo')),
                  ),
                ],
              ),
            ] else if (_relatedVideos.isEmpty && !_loadingRelatedVideos)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(AppStrings.t('upload.noRelatedVideos')),
              ),
            if (_videoCards.isNotEmpty)
              ..._videoCards.map((card) {
                final relatedVideo = _relatedVideos
                    .where((item) => item.id == card['videoId'])
                    .firstOrNull;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    relatedVideo?.title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _formatVideoCardTime(card['startSeconds'] as int),
                  ),
                  trailing: IconButton(
                    tooltip: AppStrings.t('upload.removeRelatedVideo'),
                    icon: const Icon(Icons.close),
                    onPressed: _uploading
                        ? null
                        : () => setState(() => _videoCards.remove(card)),
                  ),
                );
              }),
            if (_canPromote)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _promotionEnabled,
                onChanged: _uploading
                    ? null
                    : (value) => setState(() => _promotionEnabled = value),
                title: Text(AppStrings.t('upload.promoteVideo')),
                subtitle: Text(AppStrings.t('upload.promoteVideoHint')),
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
                child: HuTubeSurface(
                  padding: const EdgeInsets.all(13),
                  color: Theme.of(context).colorScheme.errorContainer,
                  border: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: .25),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
            ),
          ],
        ),
      ),
    ),
  );
}

class _FilePicker extends StatelessWidget {
  const _FilePicker({
    this.icon,
    this.customIcon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData? icon;
  final Widget? customIcon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surfaceFor(context),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.borderFor(context)),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      onTap: onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: customIcon ?? Icon(icon, color: AppColors.primary),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );
}
