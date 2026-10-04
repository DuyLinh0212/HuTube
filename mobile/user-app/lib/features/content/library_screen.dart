import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/storage/app_preferences.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import 'content_models.dart';
import 'content_service.dart';
import 'video_card.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final ContentService _content;
  final _prefs = const AppPreferencesStore();
  bool _loading = true;
  bool _historyPaused = false;
  String? _error;
  List<LibraryVideo> _history = [];
  List<LibraryVideo> _liked = [];
  int _tab = 0;
  int? _rating;

  @override
  void initState() {
    super.initState();
    _content = ContentService(widget.auth);
    _prefs.readHistoryPaused().then((val) {
      if (mounted) setState(() => _historyPaused = val);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final history = await loadAllPages(
        (page) => _content.history(page: page),
      );
      final liked = await loadAllPages(
        (page) => _content.liked(page: page, rating: _rating),
      );
      if (mounted) {
        setState(() {
          _history = history.items;
          _liked = liked.items;
          _loading = false;
        });
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = AppStrings.apiError(error, fallback: 'library.loadError');
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppStrings.t('library.loadError');
          _loading = false;
        });
      }
    }
  }

  Future<void> _clearAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.t('library.clearAllHistory')),
        content: Text(AppStrings.t('library.clearConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.t('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.t('common.delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    HapticFeedback.mediumImpact();
    try {
      await _content.clearHistory();
      if (!mounted) return;
      setState(() => _history = []);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('library.clearSuccess'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('common.error'))),
      );
    }
  }

  Future<void> _togglePauseHistory() async {
    HapticFeedback.selectionClick();
    final next = !_historyPaused;
    setState(() => _historyPaused = next);
    await _prefs.writeHistoryPaused(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? AppStrings.t('library.historyPaused')
              : AppStrings.t('library.historyResumed'),
        ),
      ),
    );
  }

  Future<void> _removeHistoryItem(LibraryVideo video) async {
    HapticFeedback.lightImpact();
    try {
      await _content.deleteHistoryItem(video.id);
      if (!mounted) return;
      setState(() {
        _history.removeWhere((item) => item.id == video.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('library.removedSuccess'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('common.error'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
        children: const [
          _LibrarySkeleton(),
          SizedBox(height: 12),
          _LibrarySkeleton(),
          SizedBox(height: 12),
          _LibrarySkeleton(),
        ],
      );
    }
    if (_error != null) {
      return HuTubeStateView(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        message: AppStrings.t('common.networkError'),
        actionLabel: AppStrings.t('common.retry'),
        onAction: _load,
      );
    }
    final items = _tab == 0 ? _history : _liked;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: HuTubeSectionHeader(
              title: AppStrings.t('library.title'),
              subtitle: AppStrings.t('library.subtitle'),
              action: AppStrings.t('library.playlists'),
              onAction: () => context.push('/playlists'),
            ),
          ),
          TabBar(
            onTap: (value) => setState(() => _tab = value),
            tabs: [
              Tab(
                icon: AppIcons.asset(AppIcons.history, size: 20),
                text: AppStrings.t('library.history'),
              ),
              Tab(
                icon: AppIcons.asset(AppIcons.favorite, size: 20),
                text: AppStrings.t('library.liked'),
              ),
            ],
          ),
          if (_tab == 0)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  FilterChip(
                    avatar: Icon(
                      _historyPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      size: 16,
                      color: _historyPaused
                          ? AppColors.warning
                          : AppColors.textMuted,
                    ),
                    label: Text(
                      _historyPaused
                          ? AppStrings.t('library.resumeHistory')
                          : AppStrings.t('library.pauseHistory'),
                    ),
                    selected: _historyPaused,
                    selectedColor: AppColors.warning.withValues(alpha: 0.15),
                    onSelected: (_) => _togglePauseHistory(),
                  ),
                  if (_history.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: const Icon(
                        Icons.delete_sweep_outlined,
                        size: 16,
                        color: AppColors.danger,
                      ),
                      label: Text(
                        AppStrings.t('library.clearAllHistory'),
                        style: const TextStyle(color: AppColors.danger),
                      ),
                      onPressed: _clearAllHistory,
                    ),
                  ],
                ],
              ),
            ),
          if (_tab == 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  for (final score in <int?>[null, 1, 2, 3, 4, 5])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: score == null
                            ? null
                            : AppIcons.asset(AppIcons.star, size: 14),
                        label: Text(
                          score == null
                              ? AppStrings.t('library.allRatings')
                              : AppStrings.format('library.ratingStars', {
                                  'count': AppStrings.number(score),
                                }),
                        ),
                        selected: _rating == score,
                        showCheckmark: false,
                        shape: const StadiumBorder(),
                        onSelected: (_) {
                          setState(() => _rating = score);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primaryPink,
              onRefresh: _load,
              child: items.isEmpty
                  ? ListView(
                      children: [
                        HuTubeStateView(
                          icon: Icons.video_library_outlined,
                          title: AppStrings.t('library.empty'),
                          message: _tab == 0
                              ? AppStrings.t('library.historyDescription')
                              : AppStrings.t('library.likedDescription'),
                          compact: true,
                          accent: AppColors.violet,
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: items.length,
                      itemBuilder: (_, index) {
                        final item = items[index];
                        return VideoCardTile(
                          video: item,
                          progress: _tab == 0 ? item.progress : null,
                          trailing: _tab == 0
                              ? PopupMenuButton<String>(
                                  icon: const Icon(
                                    Icons.more_vert_rounded,
                                    size: 20,
                                  ),
                                  onSelected: (val) {
                                    if (val == 'remove') {
                                      _removeHistoryItem(item);
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    PopupMenuItem(
                                      value: 'remove',
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 18,
                                            color: AppColors.danger,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            AppStrings.t(
                                              'library.removeFromHistory',
                                            ),
                                            style: const TextStyle(
                                              color: AppColors.danger,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibrarySkeleton extends StatelessWidget {
  const _LibrarySkeleton();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 138,
        height: 82,
        decoration: BoxDecoration(
          color: AppColors.borderSubtle,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 14,
              child: ColoredBox(color: AppColors.borderSubtle),
            ),
            SizedBox(height: 8),
            SizedBox(
              width: 100,
              height: 12,
              child: ColoredBox(color: AppColors.borderSubtle),
            ),
          ],
        ),
      ),
    ],
  );
}
