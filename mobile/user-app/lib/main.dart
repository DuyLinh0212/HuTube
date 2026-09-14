import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';

import 'auth.dart';
import 'app/mobile_app.dart';

export 'app/mobile_app.dart' show HuTubeApp;
export 'core/widgets/app_logo.dart';
export 'core/widgets/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final links = AppLinks();
  runApp(
    HuTubeApp(
      auth: AuthController(ApiClient(), SecureTokenStore()),
      links: links.uriLinkStream,
    ),
  );
}
