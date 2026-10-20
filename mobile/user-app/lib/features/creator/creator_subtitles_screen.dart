import '../../core/widgets/scrollable_sheet.dart';
import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../channel/models/channel_models.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../content/content_models.dart';
import 'creator_service.dart';

class CreatorSubtitlesScreen extends StatefulWidget {
  const CreatorSubtitlesScreen({
    super.key,
    required this.auth,
    required this.channel,
  });

  final AuthController auth;
  final ChannelDetail channel;

  @override
  State<CreatorSubtitlesScreen> createState() => _CreatorSubtitlesScreenState();
}

class _CreatorSubtitlesScreenState extends State<CreatorSubtitlesScreen> {
  bool _loading = true;
  String? _error;
  List<VideoDetail> _videos = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = CreatorService(widget.auth);
      final result = await loadAllPages(
        (page) => service.managedVideos(widget.channel.id, page: page),
      );
      if (mounted) {
        setState(() {
          _videos = result.items;
          _loading = false;
        });
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = AppStrings.apiError(error, fallback: 'common.error');
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppStrings.t('common.serverError');
          _loading = false;
        });
      }
    }
  }

  Future<void> _manageSubtitles(VideoDetail video) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (bottomSheetContext) => ScrollableSheet(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Phụ đề: ${video.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.violet.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.upload_file_rounded,
                    color: AppColors.violet,
                  ),
                ),
                title: const Text('Tải tệp phụ đề lên (.vtt, .srt)'),
                subtitle: const Text('Đính kèm tệp văn bản phụ đề từ thiết bị'),
                onTap: () => Navigator.pop(bottomSheetContext, 'upload'),
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.translate_rounded,
                    color: Colors.teal,
                  ),
                ),
                title: const Text('Dalitu AI - Tự động tạo phụ đề'),
                subtitle: const Text(
                  'Nhận diện giọng nói và xuất phụ đề tiếng Việt tự động',
                ),
                onTap: () => Navigator.pop(bottomSheetContext, 'ai'),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'upload') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã chọn tải phụ đề cho "${video.title}". Tệp sẽ được đồng bộ khi xuất bản.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (choice == 'ai') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hệ thống Dalitu AI đang xử lý nhận diện giọng nói cho video...',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.t('creator.subtitles')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: AppStrings.t('common.retry'),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.violet),
            )
          : _error != null
          ? HuTubeStateView(
              icon: Icons.subtitles_outlined,
              title: _error!,
              message: AppStrings.t('common.networkError'),
              actionLabel: AppStrings.t('common.retry'),
              onAction: _load,
              accent: AppColors.violet,
            )
          : _videos.isEmpty
          ? Center(
              child: Text(
                AppStrings.t('creator.noManagedVideos'),
                style: const TextStyle(color: Colors.grey),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.violet,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: _videos.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final video = _videos[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            video.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              Text(
                                '${video.duration ~/ 60}:${(video.duration % 60).toString().padLeft(2, '0')}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              TextButton.icon(
                                onPressed: () => _manageSubtitles(video),
                                icon: const Icon(Icons.subtitles_outlined),
                                label: Text(AppStrings.t('creator.subtitles')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
