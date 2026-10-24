import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/widgets/modal_header.dart';
import '../../../core/widgets/scrollable_sheet.dart';

class RatingSheet extends StatefulWidget {
  const RatingSheet({super.key, this.currentRating});
  final int? currentRating;
  @override
  State<RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<RatingSheet> {
  late int _selected = widget.currentRating ?? 0;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScrollableSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ModalHeader(
            title: AppStrings.t('watch.ratingTitle'),
            subtitle: AppStrings.t('watch.ratingHint'),
            icon: Icons.star_outline_rounded,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 8,
              children: [
                for (var score = 1; score <= 5; score++)
                  Semantics(
                    selected: score == _selected,
                    child: IconButton(
                      tooltip: AppStrings.format('library.ratingStars', {
                        'count': AppStrings.number(score),
                      }),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selected = score);
                      },
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      icon: Icon(
                        score <= _selected
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 36,
                        color: score <= _selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _selected > 0 ? '$_selected / 5' : '— / 5',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: _selected == 0
                      ? null
                      : () => Navigator.pop(context, _selected),
                  child: Text(AppStrings.t('common.save')),
                ),
                if (widget.currentRating != null)
                  TextButton(
                    onPressed: () => Navigator.pop(context, 0),
                    child: Text(AppStrings.t('watch.removeRating')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
