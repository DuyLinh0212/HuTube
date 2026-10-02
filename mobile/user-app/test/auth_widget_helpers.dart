import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/localization/app_strings.dart';

Future<void> openSignInFromHome(WidgetTester tester) async {
  await tester.tap(find.byTooltip(AppStrings.t('common.signIn')));
  await tester.pumpAndSettle();
}
