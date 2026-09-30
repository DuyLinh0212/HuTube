import 'dart:math';

import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../channel/models/channel_models.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../content/content_models.dart';
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
  String _period = '28d';
  bool _loading = true;
  String? _error;
  List<VideoDetail> _allVideos = const [];

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
      final result = await service.managedVideos(widget.channel.id);
      if (mounted) {
        setState(() {
          _allVideos = result.items;
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

  List<VideoDetail> get _filteredVideos {
    if (_period == 'all') return _allVideos;
    final now = DateTime.now();
    final days = switch (_period) {
      '7d' => 7,
      '90d' => 90,
      _ => 28,
    };
    final threshold = now.subtract(Duration(days: days));
    return _allVideos.where((v) {
      final pub = v.publishedAt;
      return pub == null || pub.isAfter(threshold);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Số liệu phân tích kênh'),
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
                  title: _error!,
                  message: AppStrings.t('common.networkError'),
                  actionLabel: AppStrings.t('common.retry'),
                  onAction: _load,
                  accent: AppColors.violet,
                )
              : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final videos = _filteredVideos;
    final totalViews = videos.fold<int>(0, (sum, v) => sum + v.stats.views);
    final totalLikes = videos.fold<int>(0, (sum, v) => sum + v.stats.likes);
    final totalComments = videos.fold<int>(0, (sum, v) => sum + v.stats.comments);
    final totalWatchSeconds = videos.fold<int>(
      0,
      (sum, v) => sum + (v.stats.views * v.duration),
    );
    final watchHours = (totalWatchSeconds / 3600).toStringAsFixed(1);

    final sortedVideos = List<VideoDetail>.of(videos)
      ..sort((a, b) => b.stats.views.compareTo(a.stats.views));
    final topVideos = sortedVideos.take(5).toList();

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.violet,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // Period Selector Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPeriodChip('7d', '7 ngày qua'),
                const SizedBox(width: 8),
                _buildPeriodChip('28d', '28 ngày qua'),
                const SizedBox(width: 8),
                _buildPeriodChip('90d', '90 ngày qua'),
                const SizedBox(width: 8),
                _buildPeriodChip('all', 'Toàn thời gian'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Overview Metric Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _AnalyticsCard(
                    width: itemWidth,
                    customIcon: AppIcons.statistics,
                    title: 'Lượt xem',
                    value: AppStrings.number(totalViews),
                    subtitle: 'Tổng lượt xem video',
                    gradient: const [Color(0xFF6B21A8), Color(0xFF4C1D95)],
                  ),
                  _AnalyticsCard(
                    width: itemWidth,
                    customIcon: AppIcons.history,
                    title: 'Thời gian xem',
                    value: '$watchHours h',
                    subtitle: 'Tổng giờ khán giả đã xem',
                    gradient: const [Color(0xFF0F766E), Color(0xFF115E59)],
                  ),
                  _AnalyticsCard(
                    width: itemWidth,
                    customIcon: AppIcons.favorite,
                    title: 'Lượt thích',
                    value: AppStrings.number(totalLikes),
                    subtitle: 'Tương tác yêu thích',
                    gradient: const [Color(0xFFBE185D), Color(0xFF9D174D)],
                  ),
                  _AnalyticsCard(
                    width: itemWidth,
                    icon: Icons.forum_outlined,
                    title: 'Bình luận',
                    value: AppStrings.number(totalComments),
                    subtitle: 'Phản hồi từ khán giả',
                    gradient: const [Color(0xFF1E40AF), Color(0xFF1E3A8A)],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // Subscriber summary card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: .2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.violet.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.people_alt_outlined, color: AppColors.violet),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Người đăng ký kênh',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppStrings.number(widget.channel.subscriberCount),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppColors.violet,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.trending_up_rounded, color: Colors.green, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Đang tăng',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Trend Chart Section
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Xu hướng lượt xem',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${videos.length} video',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Biểu đồ phân bố lượt xem giữa các video trong kỳ',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: videos.isEmpty
                        ? Center(
                            child: Text(
                              AppStrings.t('ui.noData'),
                              style: const TextStyle(color: Colors.grey),
                            ),
                          )
                        : CustomPaint(
                            painter: _TrendChartPainter(
                              values: videos.map((v) => v.stats.views.toDouble()).toList(),
                              accentColor: AppColors.violet,
                              isDark: Theme.of(context).brightness == Brightness.dark,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Top Performing Videos Section
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hiệu quả theo video',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Top 5 video có lượt xem cao nhất trong giai đoạn đã chọn',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (topVideos.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          AppStrings.t('ui.noData'),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ...topVideos.asMap().entries.map((entry) {
                      final rank = entry.key + 1;
                      final video = entry.value;
                      final maxViews = topVideos.first.stats.views;
                      final ratio = maxViews > 0
                          ? (video.stats.views / maxViews).clamp(0.05, 1.0)
                          : 0.05;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: rank == 1
                                        ? const Color(0xFFEAB308)
                                        : rank == 2
                                            ? const Color(0xFF94A3B8)
                                            : rank == 3
                                                ? const Color(0xFFB45309)
                                                : Colors.grey.withValues(alpha: .3),
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '$rank',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    video.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  AppStrings.format('watch.views', {
                                    'count': AppStrings.number(video.stats.views),
                                  }),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 6,
                                backgroundColor: Theme.of(context)
                                    .dividerColor
                                    .withValues(alpha: .15),
                                valueColor: const AlwaysStoppedAnimation(AppColors.violet),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(String id, String label) {
    final selected = _period == id;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.violet.withValues(alpha: .2),
      labelStyle: TextStyle(
        color: selected ? AppColors.violet : null,
        fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
        fontSize: 12,
      ),
      onSelected: (val) {
        if (val) setState(() => _period = id);
      },
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({
    required this.width,
    this.customIcon,
    this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.gradient,
  });

  final double width;
  final String? customIcon;
  final IconData? icon;
  final String title;
  final String value;
  final String subtitle;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withValues(alpha: .3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .85),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (customIcon != null)
                AppIcons.asset(
                  customIcon!,
                  size: 18,
                  color: Colors.white.withValues(alpha: .9),
                )
              else if (icon != null)
                Icon(
                  icon,
                  size: 18,
                  color: Colors.white.withValues(alpha: .9),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .65),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  const _TrendChartPainter({
    required this.values,
    required this.accentColor,
    required this.isDark,
  });

  final List<double> values;
  final Color accentColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final maxVal = values.reduce(max);
    final minVal = values.reduce(min);
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    // Draw horizontal grid lines
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: .07)
      ..strokeWidth = 1;

    for (var i = 0; i <= 3; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final points = <Offset>[];
    final stepX = values.length == 1 ? size.width / 2 : size.width / (values.length - 1);

    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? size.width / 2 : i * stepX;
      final normalized = (values[i] - minVal) / range;
      final y = size.height - (normalized * (size.height - 24)) - 12;
      points.add(Offset(x, y));
    }

    if (points.length == 1) {
      final point = points.first;
      canvas.drawCircle(point, 6, Paint()..color = accentColor);
      return;
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final cX = (prev.dx + curr.dx) / 2;
      path.cubicTo(cX, prev.dy, cX, curr.dy, curr.dx, curr.dy);
    }

    // Fill under curve
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          accentColor.withValues(alpha: .35),
          accentColor.withValues(alpha: .0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    // Draw curve line
    final linePaint = Paint()
      ..color = accentColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);

    // Draw dots on points
    final dotPaint = Paint()..color = accentColor;
    final dotInnerPaint = Paint()..color = isDark ? const Color(0xFF1E1B2E) : Colors.white;

    for (final pt in points) {
      canvas.drawCircle(pt, 4.5, dotPaint);
      canvas.drawCircle(pt, 2.5, dotInnerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.accentColor != accentColor;
}
