import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';

import 'auth.dart';
import 'app/mobile_app.dart';
import 'core/localization/app_strings.dart';
import 'core/theme/theme_notifier.dart';

export 'app/mobile_app.dart' show HuTubeApp;
export 'core/widgets/app_logo.dart';
export 'core/widgets/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([AppStrings.restore(), ThemeNotifier.restore()]);
  final links = AppLinks();
  runApp(
    HuTubeApp(
      auth: AuthController(ApiClient(), SecureTokenStore()),
      links: links.uriLinkStream,
    ),
  );
}
