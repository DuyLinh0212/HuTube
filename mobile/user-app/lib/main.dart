import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'auth.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_shell.dart';

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

class HuTubeApp extends StatelessWidget {
  const HuTubeApp({super.key, required this.auth, this.links});
  final AuthController auth;
  final Stream<Uri>? links;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HuTube',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.theme,
    home: AppShell(auth: auth, links: links),
  );
}
