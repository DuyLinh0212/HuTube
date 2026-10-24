import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';

enum FeedbackSurveyPhase { closed, invitation, plea, waiting, thanks }

class FeedbackSurveyView {
  const FeedbackSurveyView(
    this.phase, {
    this.opening = false,
    this.openFailed = false,
  });

  final FeedbackSurveyPhase phase;
  final bool opening;
  final bool openFailed;
}

class FeedbackSurveyDialog extends StatelessWidget {
  const FeedbackSurveyDialog({
    super.key,
    required this.view,
    required this.onOpenForm,
    required this.onClose,
  });

  final FeedbackSurveyView view;
  final VoidCallback onOpenForm;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (view.phase == FeedbackSurveyPhase.closed) {
      return const SizedBox.shrink();
    }
    final plea = view.phase == FeedbackSurveyPhase.plea;
    final waiting = view.phase == FeedbackSurveyPhase.waiting;
    final thanks = view.phase == FeedbackSurveyPhase.thanks;
    final titleKey = switch (view.phase) {
      FeedbackSurveyPhase.plea => 'survey.pleaTitle',
      FeedbackSurveyPhase.waiting => 'survey.waitingTitle',
      FeedbackSurveyPhase.thanks => 'survey.thanksTitle',
      _ => 'survey.invitationTitle',
    };
    final descriptionKey = switch (view.phase) {
      FeedbackSurveyPhase.plea => 'survey.pleaDescription',
      FeedbackSurveyPhase.waiting => 'survey.waitingDescription',
      FeedbackSurveyPhase.thanks => 'survey.thanksDescription',
      _ => 'survey.invitationDescription',
    };
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      constraints: BoxConstraints(maxWidth: plea ? 360 : 420),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: AppStrings.t('survey.close'),
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            if (plea)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/feedback/pleading-cat.webp',
                    width: 200,
                    height: 200,
                    fit: BoxFit.contain,
                    semanticLabel: AppStrings.t('survey.imageTitle'),
                  ),
                ),
              )
            else
              Icon(
                thanks
                    ? Icons.check_circle_outline_rounded
                    : waiting
                    ? Icons.open_in_new_rounded
                    : Icons.favorite_outline_rounded,
                size: 52,
                color: AppColors.primaryDark,
              ),
            const SizedBox(height: 20),
            Semantics(
              header: true,
              child: Text(
                AppStrings.t(titleKey),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.t(descriptionKey),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
            if (view.phase == FeedbackSurveyPhase.invitation) ...[
              const SizedBox(height: 12),
              Text(
                AppStrings.t('survey.duration'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (waiting) ...[
              const SizedBox(height: 12),
              Text(
                AppStrings.t('survey.autoSync'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
            ],
            if (view.openFailed) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  AppStrings.t('survey.openError'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onPressed: view.opening
                  ? null
                  : thanks
                  ? onClose
                  : onOpenForm,
              icon: Icon(
                thanks ? Icons.check_rounded : Icons.open_in_new_rounded,
                size: 18,
              ),
              label: Text(
                AppStrings.t(
                  view.opening
                      ? 'common.loading'
                      : thanks
                      ? 'survey.continue'
                      : waiting
                      ? 'survey.reopen'
                      : 'survey.doSurvey',
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (!thanks) ...[
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: onClose,
                child: Text(
                  AppStrings.t(
                    plea
                        ? 'survey.later'
                        : waiting
                        ? 'survey.continue'
                        : 'survey.maybeLater',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
