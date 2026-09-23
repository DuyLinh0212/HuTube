import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../plans_screen.dart';

class MobilePlansScreen extends StatelessWidget {
  const MobilePlansScreen({
    super.key,
    required this.auth,
    this.invitationId,
    this.invitationToken,
  });
  final AuthController auth;
  final String? invitationId;
  final String? invitationToken;

  @override
  Widget build(BuildContext context) => PlansScreen(
    auth: auth,
    invitationId: invitationId,
    invitationToken: invitationToken,
  );
}
