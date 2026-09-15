import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth.dart';
import '../core/localization/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_logo.dart';

class MobileScaffold extends StatelessWidget {
  const MobileScaffold({
    super.key,
    required this.auth,
    required this.location,
    required this.child,
  });

  final AuthController auth;
  final String location;
  final Widget child;

  int get _selectedIndex {
    if (location.startsWith('/explore')) return 1;
    if (location.startsWith('/library')) return 2;
    if (location.startsWith('/account')) return 3;
    return 0;
  }

  void _select(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
      case 1:
        context.go('/explore');
      case 2:
        auth.authenticated ? context.go('/library') : context.go('/auth');
      case 3:
        auth.authenticated ? context.go('/account') : context.go('/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final isDetail = location.startsWith('/watch/');
    final rawName = (auth.user?['displayName'] as String?) ?? 'H';
    final initial = rawName.isEmpty
        ? 'H'
        : rawName.substring(0, 1).toUpperCase();
    return Scaffold(
      appBar: AppBar(
        leadingWidth: wide ? 168 : 60,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: wide
              ? const Align(
                  alignment: Alignment.centerLeft,
                  child: HuTubeLogo(size: 28),
                )
              : Builder(
                  builder: (drawerContext) => IconButton(
                    tooltip: AppStrings.t('common.menu'),
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: () => Scaffold.of(drawerContext).openDrawer(),
                  ),
                ),
        ),
        title: isDetail
            ? Text(AppStrings.t('app.viewVideo'))
            : const SizedBox.shrink(),
        actions: [
          IconButton(
            tooltip: AppStrings.t('common.policy'),
            onPressed: () => context.push('/policies'),
            icon: const Icon(Icons.shield_outlined),
          ),
          if (auth.authenticated)
            IconButton(
              tooltip: AppStrings.t('common.notifications'),
              onPressed: () => context.push('/notifications'),
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: auth.authenticated
                  ? AppStrings.t('common.account')
                  : AppStrings.t('common.signIn'),
              onPressed: () =>
                  context.go(auth.authenticated ? '/account' : '/auth'),
              icon: CircleAvatar(
                radius: 15,
                backgroundColor: AppColors.primaryPink.withValues(alpha: .15),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: AppColors.primaryPink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: _Drawer(auth: auth),
      body: SafeArea(top: false, child: child),
      floatingActionButton: auth.authenticated && !isDetail
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/creator'),
              icon: const Icon(Icons.add_rounded),
              label: Text(AppStrings.t('common.create')),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (value) => _select(context, value),
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: AppStrings.t('nav.home'),
                ),
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore_rounded),
                  label: AppStrings.t('nav.explore'),
                ),
                NavigationDestination(
                  icon: Icon(Icons.video_library_outlined),
                  selectedIcon: Icon(Icons.video_library_rounded),
                  label: AppStrings.t('nav.library'),
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: AppStrings.t('app.navYou'),
                ),
              ],
            ),
    );
  }
}

class _Drawer extends StatelessWidget {
  const _Drawer({required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) => Drawer(
    child: SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 22, 16, 14),
            child: HuTubeLogo(size: 30),
          ),
          _item(
            context,
            Icons.home_outlined,
            AppStrings.t('nav.home'),
            '/home',
          ),
          _item(
            context,
            Icons.explore_outlined,
            AppStrings.t('nav.explore'),
            '/explore',
          ),
          _SectionLabel(AppStrings.t('app.librarySection')),
          _item(
            context,
            Icons.history_rounded,
            '${AppStrings.t('library.history')} & ${AppStrings.t('library.liked')}',
            '/library',
            protected: true,
          ),
          _item(
            context,
            Icons.download_outlined,
            AppStrings.t('downloads.title'),
            '/downloads',
            protected: true,
          ),
          _SectionLabel(AppStrings.t('app.otherSection')),
          _item(
            context,
            Icons.workspace_premium_outlined,
            AppStrings.t('plans.title'),
            '/plans',
          ),
          _item(
            context,
            Icons.gavel_outlined,
            AppStrings.t('policies.title'),
            '/policies',
          ),
          if (auth.authenticated) ...[
            _item(
              context,
              Icons.dashboard_outlined,
              AppStrings.t('creator.title'),
              '/creator',
              protected: true,
            ),
            _item(
              context,
              Icons.notifications_outlined,
              AppStrings.t('common.notifications'),
              '/notifications',
              protected: true,
            ),
          ],
        ],
      ),
    ),
  );

  Widget _item(
    BuildContext context,
    IconData icon,
    String label,
    String route, {
    bool protected = false,
  }) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    minLeadingWidth: 26,
    onTap: () {
      Navigator.of(context).pop();
      context.go(protected && !auth.authenticated ? '/auth' : route);
    },
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 20, 16, 6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    ),
  );
}
