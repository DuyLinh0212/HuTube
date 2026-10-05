import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../state/account_controller.dart';
import '../widgets/session_card.dart';

class ActiveSessionsScreen extends StatelessWidget {
  const ActiveSessionsScreen({
    super.key,
    required this.controller,
    required this.onLogoutAll,
    required this.onLogout,
  });

  final AccountController controller;
  final Future<void> Function() onLogoutAll;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.t('account.sessionsHeading'))),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => RefreshIndicator(
            color: AppColors.primaryPink,
            onRefresh: controller.loadSessions,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  AppStrings.t('profile.sessionsDescription'),
                  style: TextStyle(
                    color: AppColors.textSecondaryFor(context),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStrings.t('profile.sessionsHeading'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: AppStrings.t('profile.refreshDevices'),
                      onPressed: controller.loadingSessions
                          ? null
                          : controller.loadSessions,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                if (controller.loadingSessions)
                  const LinearProgressIndicator(color: AppColors.primaryPink),
                if (controller.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      controller.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (controller.successMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      controller.successMessage!,
                      style: TextStyle(
                        color: AppColors.textSecondaryFor(context),
                      ),
                    ),
                  ),
                if (!controller.loadingSessions && controller.sessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(AppStrings.t('profile.sessionsEmpty')),
                  )
                else if (controller.sessions.isNotEmpty)
                  ...controller.sessions.map(
                    (session) => SessionCard(
                      session: session,
                      onRevoke: () => controller.revokeSession(
                        session['sessionId'] as String? ?? '',
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: controller.submitting
                      ? null
                      : controller.revokeOtherSessions,
                  child: Text(AppStrings.t('profile.logoutOthers')),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: controller.submitting ? null : onLogoutAll,
                  child: Text(AppStrings.t('profile.logoutAll')),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: controller.submitting ? null : onLogout,
                  child: Text(AppStrings.t('profile.logout')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
