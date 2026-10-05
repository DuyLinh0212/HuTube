import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../channel/models/channel_models.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../content/content_models.dart';
import 'video_upload_screen.dart';
import 'creator_service.dart';

class CreatorAnalyticsScreen extends StatefulWidget {
  const CreatorAnalyticsScreen({
    super.key,
    required this.auth,
    required this.channel,
  });

  final AuthController auth;
  final ChannelDetail channel;

  @override
  State<CreatorAnalyticsScreen> createState() => _CreatorAnalyticsScreenState();
}

class _CreatorAnalyticsScreenState extends State<CreatorAnalyticsScreen> {
  bool _loading = true;
  String? _error;
  String _selectedVideoId = 'all';
  List<VideoDetail> _videos = const [];

  VideoDetail? get _selectedVideo =>
      _videos.where((video) => video.id == _selectedVideoId).firstOrNull;

  bool get _isAllVideos => _selectedVideoId == 'all' || _selectedVideo == null;

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
      final result = await loadAllPages(
        (page) => CreatorService(
          widget.auth,
        ).managedVideos(widget.channel.id, page: page),
      );
      if (!mounted) return;
      setState(() {
        _videos = result.items;
        if (_selectedVideoId != 'all' &&
            !_videos.any((video) => video.id == _selectedVideoId)) {
          _selectedVideoId = 'all';
        }
        _loading = false;
      });
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

  List<_Metric> _metrics() {
    final selected = _selectedVideo;
    final totalViews = _videos.fold<int>(
      0,
      (sum, video) => sum + video.stats.views,
    );
    final totalLikes = _videos.fold<int>(
      0,
      (sum, video) => sum + video.stats.likes,
    );
    final totalComments = _videos.fold<int>(
      0,
      (sum, video) => sum + video.stats.comments,
    );
    final totalWatchSeconds = _videos.fold<int>(
      0,
      (sum, video) => sum + video.stats.watchSeconds,
    );
    final ratedVideos = _videos.where(
      (video) =>
          video.stats.averageRating != null && video.stats.ratingCount > 0,
    );
    final totalRatings = ratedVideos.fold<double>(
      0,
      (sum, video) =>
          sum + video.stats.averageRating! * video.stats.ratingCount,
    );
    final ratingCount = ratedVideos.fold<int>(
      0,
      (sum, video) => sum + video.stats.ratingCount,
    );
    final averageDuration = selected != null
        ? selected.stats.views == 0
              ? 0.0
              : selected.stats.watchSeconds / selected.stats.views
        : totalViews == 0
        ? 0.0
        : totalWatchSeconds / totalViews;
    final averageRating = selected != null
        ? selected.stats.averageRating ?? 0
        : ratingCount == 0
        ? 0.0
        : totalRatings / ratingCount;
    final maxViews = _videos.fold<int>(
      0,
      (max, video) => math.max(max, video.stats.views),
    );
    final maxLikes = _videos.fold<int>(
      0,
      (max, video) => math.max(max, video.stats.likes),
    );
    final maxComments = _videos.fold<int>(
      0,
      (max, video) => math.max(max, video.stats.comments),
    );
    final maxDuration = _videos.fold<double>(
      0,
      (max, video) => math.max(
        max,
        video.stats.views == 0
            ? 0
            : video.stats.watchSeconds / video.stats.views,
      ),
    );
    final values = <String, double>{
      'views':
          selected?.stats.views.toDouble() ??
          (_videos.isEmpty ? 0 : totalViews / _videos.length),
      'likes':
          selected?.stats.likes.toDouble() ??
          (_videos.isEmpty ? 0 : totalLikes / _videos.length),
      'comments':
          selected?.stats.comments.toDouble() ??
          (_videos.isEmpty ? 0 : totalComments / _videos.length),
      'watchDuration': averageDuration,
      'rating': averageRating,
    };
    final maxima = <String, double>{
      'views': maxViews.toDouble(),
      'likes': maxLikes.toDouble(),
      'comments': maxComments.toDouble(),
      'watchDuration': maxDuration,
      'rating': 5,
    };
    final labels = <String>[
      AppStrings.t(
        _isAllVideos ? 'analytics.averageViews' : 'creator.metricViews',
      ),
      AppStrings.t(_isAllVideos ? 'analytics.averageLikes' : 'analytics.likes'),
      AppStrings.t(
        _isAllVideos ? 'analytics.averageComments' : 'analytics.comments',
      ),
      AppStrings.t('analytics.averageViewDuration'),
      AppStrings.t('analytics.averageRating'),
    ];
    final displays = <String>[
      AppStrings.number(values['views']!),
      AppStrings.number(values['likes']!),
      AppStrings.number(values['comments']!),
      _formatDuration(averageDuration),
      selected != null && selected.stats.ratingCount == 0 ||
              selected == null && ratingCount == 0
          ? AppStrings.t('analytics.noRating')
          : '${averageRating.toStringAsFixed(2)} / 5',
    ];
    final ratios = values.keys.map((key) {
      final max = maxima[key] ?? 0;
      return max == 0 ? 0.0 : (values[key]! / max).clamp(0.0, 1.0);
    }).toList();
    return List.generate(
      values.length,
      (index) => _Metric(
        key: values.keys.elementAt(index),
        label: labels[index],
        display: displays[index],
        ratio: ratios[index],
      ),
    );
  }

  List<VideoDetail> get _topVideos {
    final videos = List<VideoDetail>.of(_videos)
      ..sort((left, right) {
        final byViews = right.stats.views.compareTo(left.stats.views);
        if (byViews != 0) return byViews;
        final byLikes = right.stats.likes.compareTo(left.stats.likes);
        return byLikes != 0 ? byLikes : left.title.compareTo(right.title);
      });
    return videos.take(5).toList();
  }

  static String _formatDuration(double seconds) {
    if (!seconds.isFinite || seconds <= 0) return '0:00';
    final total = seconds.round();
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final remainder = total % 60;
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}'
        : '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  Future<void> _uploadFirstVideo() async {
    final uploaded = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            VideoUploadScreen(auth: widget.auth, channel: widget.channel),
      ),
    );
    if (uploaded == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.t('creator.analytics')),
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
              icon: Icons.analytics_outlined,
              title: AppStrings.t('analytics.loadError'),
              message: _error!,
              actionLabel: AppStrings.t('common.retry'),
              onAction: _load,
              accent: AppColors.violet,
            )
          : _videos.isEmpty
          ? _emptyState()
          : _buildDashboard(context),
    );
  }

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.analytics_outlined,
            size: 46,
            color: AppColors.violet,
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.t('analytics.noVideos'),
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.t('analytics.noVideosDescription'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _uploadFirstVideo,
            icon: const Icon(Icons.upload_rounded),
            label: Text(AppStrings.t('creator.upload')),
          ),
        ],
      ),
    ),
  );

  Widget _buildDashboard(BuildContext context) {
    final metrics = _metrics();
    final selected = _selectedVideo;
    final top = _topVideos;
    final maxViews = top.isEmpty ? 0 : top.first.stats.views;
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.violet,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _isAllVideos ? 'all' : _selectedVideoId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: AppStrings.t('analytics.videoFilter'),
            ),
            items: [
              DropdownMenuItem(
                value: 'all',
                child: Text(AppStrings.t('analytics.allVideos')),
              ),
              ..._videos.map(
                (video) => DropdownMenuItem(
                  value: video.id,
                  child: Text(
                    video.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _selectedVideoId = value);
            },
          ),
          const SizedBox(height: 8),
          Text(
            _isAllVideos
                ? AppStrings.format('analytics.allAverageNote', {
                    'count': AppStrings.number(_videos.length),
                  })
                : AppStrings.t('analytics.selectedNote'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 10.0;
              final width = (constraints.maxWidth - spacing) / 2;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: metrics.asMap().entries.map((entry) {
                  final index = entry.key;
                  final metric = entry.value;
                  return _MetricCard(
                    width: index == 4 ? constraints.maxWidth : width,
                    metric: metric,
                    accent: index == 4
                        ? AppColors.violet
                        : _metricColors[index],
                    hint: index == 3
                        ? AppStrings.t('analytics.watchDurationHint')
                        : index == 4
                        ? AppStrings.t('analytics.ratingHint')
                        : _isAllVideos
                        ? AppStrings.t('analytics.perVideoHint')
                        : selected?.title ?? '',
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 16),
          _Panel(
            title: AppStrings.t('analytics.radarTitle'),
            subtitle: AppStrings.t('analytics.radarDescription'),
            trailing: _LegendLabel(
              label: AppStrings.t(
                _isAllVideos
                    ? 'analytics.channelAverage'
                    : 'analytics.selectedVideo',
              ),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 280,
                  child: CustomPaint(
                    painter: _RadarPainter(
                      ratios: metrics.map((metric) => metric.ratio).toList(),
                      labels: [
                        AppStrings.t('analytics.axisViews'),
                        AppStrings.t('analytics.axisLikes'),
                        AppStrings.t('analytics.axisComments'),
                        AppStrings.t('analytics.axisDuration'),
                        AppStrings.t('analytics.axisRating'),
                      ],
                      accent: AppColors.violet,
                      isDark: Theme.of(context).brightness == Brightness.dark,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                Text(
                  AppStrings.t('analytics.radarScaleNote'),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_isAllVideos)
            _Panel(
              title: AppStrings.t('analytics.topVideos'),
              subtitle: AppStrings.t('analytics.topVideosDescription'),
              trailing: _CountBadge(label: '${top.length} / ${_videos.length}'),
              child: Column(
                children: [
                  ...top.asMap().entries.map((entry) {
                    final video = entry.value;
                    final ratio = maxViews == 0
                        ? 0.0
                        : (video.stats.views / maxViews).clamp(0.0, 1.0);
                    return _TopVideoRow(
                      rank: entry.key + 1,
                      video: video,
                      ratio: ratio,
                      onTap: () => setState(() => _selectedVideoId = video.id),
                    );
                  }),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      AppStrings.t('analytics.topFiveLimit'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            )
          else if (selected != null)
            _Panel(
              title: AppStrings.t('analytics.videoSummary'),
              subtitle: AppStrings.t('analytics.selectedNote'),
              trailing: _CountBadge(label: AppStrings.t('analytics.oneVideo')),
              child: Column(
                children: [
                  _SelectedVideoSummary(
                    video: selected,
                    averageDuration: metrics[3].display,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _selectedVideoId = 'all'),
                      child: Text(AppStrings.t('analytics.backToAll')),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

const _metricColors = <Color>[
  Color(0xFF633CCB),
  Color(0xFF147F76),
  Color(0xFFB83D72),
  Color(0xFF2867AA),
  Color(0xFF633CCB),
];

class _Metric {
  const _Metric({
    required this.key,
    required this.label,
    required this.display,
    required this.ratio,
  });

  final String key;
  final String label;
  final String display;
  final double ratio;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.metric,
    required this.accent,
    required this.hint,
  });

  final double width;
  final _Metric metric;
  final Color accent;
  final String hint;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    constraints: const BoxConstraints(minHeight: 116),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceFor(context),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: AppColors.borderFor(context)),
      gradient: metric.key == 'rating'
          ? LinearGradient(
              colors: [
                AppColors.surfaceFor(context),
                accent.withValues(alpha: .08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          metric.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text(
          metric.display,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surfaceFor(context),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.borderFor(context)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.violetContainerFor(context),
      border: Border.all(color: AppColors.borderFor(context)),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelSmall),
  );
}

class _LegendLabel extends StatelessWidget {
  const _LegendLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: AppColors.violet,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _TopVideoRow extends StatelessWidget {
  const _TopVideoRow({
    required this.rank,
    required this.video,
    required this.ratio,
    required this.onTap,
  });

  final int rank;
  final VideoDetail video;
  final double ratio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 25,
            child: Text(
              rank.toString().padLeft(2, '0'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.violet,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: SizedBox(
              width: 76,
              height: 44,
              child: video.thumbnailUrl == null
                  ? const ColoredBox(
                      color: Color(0xFFECEAF5),
                      child: Icon(Icons.play_arrow_rounded),
                    )
                  : Image.network(video.thumbnailUrl!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${AppStrings.number(video.stats.views)} ${AppStrings.t('analytics.views')} · ${AppStrings.number(video.stats.likes)} ${AppStrings.t('analytics.likes')} · ${AppStrings.number(video.stats.comments)} ${AppStrings.t('analytics.comments')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 4,
                    backgroundColor: AppColors.borderFor(context),
                    valueColor: const AlwaysStoppedAnimation(AppColors.violet),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, size: 19),
        ],
      ),
    ),
  );
}

class _SelectedVideoSummary extends StatelessWidget {
  const _SelectedVideoSummary({
    required this.video,
    required this.averageDuration,
  });

  final VideoDetail video;
  final String averageDuration;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 122,
          height: 80,
          child: video.thumbnailUrl == null
              ? const ColoredBox(
                  color: Color(0xFFECEAF5),
                  child: Icon(Icons.play_arrow_rounded),
                )
              : Image.network(video.thumbnailUrl!, fit: BoxFit.cover),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              video.title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '${AppStrings.number(video.stats.views)} ${AppStrings.t('analytics.views')} · ${AppStrings.number(video.stats.likes)} ${AppStrings.t('analytics.likes')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 3),
            Text(
              '${AppStrings.number(video.stats.comments)} ${AppStrings.t('analytics.comments')} · ${video.stats.averageRating?.toStringAsFixed(2) ?? AppStrings.t('analytics.noRating')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${AppStrings.t('analytics.averageViewDuration')}: $averageDuration',
              style: const TextStyle(
                color: AppColors.violet,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({
    required this.ratios,
    required this.labels,
    required this.accent,
    required this.isDark,
  });

  final List<double> ratios;
  final List<String> labels;
  final Color accent;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    const sides = 5;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width * .29, size.height * .31);
    final stroke = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: .12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    List<Offset> vertices(double scale) => List.generate(sides, (index) {
      final angle = -math.pi / 2 + index * 2 * math.pi / sides;
      return Offset(
        center.dx + math.cos(angle) * radius * scale,
        center.dy + math.sin(angle) * radius * scale,
      );
    });
    for (final scale in [0.25, 0.5, 0.75, 1.0]) {
      final points = vertices(scale);
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(path, stroke);
    }
    final outer = vertices(1);
    for (var index = 0; index < sides; index++) {
      canvas.drawLine(center, outer[index], stroke);
    }
    final data = List.generate(sides, (index) {
      final angle = -math.pi / 2 + index * 2 * math.pi / sides;
      final value = index < ratios.length ? ratios[index].clamp(0.0, 1.0) : 0.0;
      return Offset(
        center.dx + math.cos(angle) * radius * value,
        center.dy + math.sin(angle) * radius * value,
      );
    });
    final area = Path()..moveTo(data.first.dx, data.first.dy);
    for (final point in data.skip(1)) {
      area.lineTo(point.dx, point.dy);
    }
    area.close();
    canvas.drawPath(area, Paint()..color = accent.withValues(alpha: .18));
    canvas.drawPath(
      area,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
    for (final point in data) {
      canvas.drawCircle(point, 3.5, Paint()..color = accent);
    }
    for (var index = 0; index < sides; index++) {
      final angle = -math.pi / 2 + index * 2 * math.pi / sides;
      final position = Offset(
        center.dx + math.cos(angle) * (radius + 23),
        center.dy + math.sin(angle) * (radius + 23),
      );
      final label = TextPainter(
        text: TextSpan(
          text: labels[index],
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black54,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 92);
      final dx = math.cos(angle) < -.2
          ? position.dx - label.width
          : math.cos(angle) > .2
          ? position.dx
          : position.dx - label.width / 2;
      final dy = math.sin(angle) < -.4
          ? position.dy - label.height
          : math.sin(angle) > .4
          ? position.dy
          : position.dy - label.height / 2;
      label.paint(
        canvas,
        Offset(
          dx.clamp(0, size.width - label.width).toDouble(),
          dy.clamp(0, size.height - label.height).toDouble(),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.ratios != ratios ||
      oldDelegate.labels != labels ||
      oldDelegate.accent != accent ||
      oldDelegate.isDark != isDark;
}
