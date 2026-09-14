import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../plans_screen.dart';

class MobilePlansScreen extends StatelessWidget {
  const MobilePlansScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  Widget build(BuildContext context) => PlansScreen(auth: auth);
}
