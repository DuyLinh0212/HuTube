import 'package:flutter/material.dart';
import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../plans/mobile_plans_screen.dart';

enum PlanMediaFeature { pip, background, download }

String mediaFeatureName(PlanMediaFeature feature) =>
    AppStrings.t(switch (feature) {
      PlanMediaFeature.pip => 'playback.pip',
      PlanMediaFeature.background => 'watch.background',
      PlanMediaFeature.download => 'watch.downloadAction',
    });
String mediaFeatureKey(PlanMediaFeature feature) => switch (feature) {
  PlanMediaFeature.pip => 'pip',
  PlanMediaFeature.background => 'background_play',
  PlanMediaFeature.download => 'download',
};

Future<void> openMediaPlans(BuildContext context, AuthController auth) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(AppStrings.t('settings.plans'))),
          body: MobilePlansScreen(auth: auth),
        ),
      ),
    );

Future<void> showMediaPlanRequirement(
  BuildContext context,
  AuthController auth,
  PlanMediaFeature feature,
) async {
  final view = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.workspace_premium_outlined),
      title: Text(AppStrings.t('media.planTitle')),
      content: Text(
        AppStrings.format('media.planRequired', {
          'feature': mediaFeatureName(feature),
        }),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(AppStrings.t('common.close')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(AppStrings.t('media.viewPlans')),
        ),
      ],
    ),
  );
  if (view == true && context.mounted) {
    await openMediaPlans(context, auth);
  }
}

/// Check the server grant before enabling a paid runtime feature. A failed lookup
/// is a retryable error, never evidence that the user needs to pay again.
Future<bool> requireMediaFeature(
  BuildContext context,
  AuthController auth,
  PlanMediaFeature feature,
) async {
  final session = auth.sessionGeneration;
  try {
    final payload = auth.authenticated
        ? await auth.protected('GET', '/plans/my-plan')
        : const <String, dynamic>{};
    if (!context.mounted || session != auth.sessionGeneration) return false;
    final features = payload['features'];
    if (features is Map && features[mediaFeatureKey(feature)] == true) {
      return true;
    }
    await showMediaPlanRequirement(context, auth, feature);
  } catch (_) {
    if (context.mounted && session == auth.sessionGeneration) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('media.checkFailed'))),
      );
    }
  }
  return false;
}
