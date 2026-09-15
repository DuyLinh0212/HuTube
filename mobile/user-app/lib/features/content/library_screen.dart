import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
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
  bool _loading = true;
  String? _error;
  List<LibraryVideo> _history = [];
  List<LibraryVideo> _liked = [];
  int _tab = 0;
  int? _rating;

  @override
  void initState() {
    super.initState();
    _content = ContentService(widget.auth);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final history = await _content.history();
      final liked = await _content.liked(rating: _rating);
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryPink),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _load,
                child: Text(AppStrings.t('common.retry')),
              ),
            ],
          ),
        ),
      );
    }
    final items = _tab == 0 ? _history : _liked;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                AppStrings.t('library.title'),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          TabBar(
            onTap: (value) => setState(() => _tab = value),
            tabs: [
              Tab(text: AppStrings.t('library.history')),
              Tab(text: AppStrings.t('library.liked')),
            ],
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
                        label: Text(
                          score == null
                              ? AppStrings.t('library.allRatings')
                              : AppStrings.format('library.ratingStars', {
                                  'count': AppStrings.number(score),
                                }),
                        ),
                        selected: _rating == score,
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
                        const SizedBox(height: 140),
                        Center(
                          child: Icon(
                            Icons.video_library_outlined,
                            size: 52,
                            color: AppColors.textSecondaryFor(context),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(child: Text(AppStrings.t('library.empty'))),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: items.length,
                      itemBuilder: (_, index) => VideoCardTile(
                        video: items[index],
                        progress: _tab == 0 ? items[index].progress : null,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
