import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth.dart';
import '../core/localization/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_logo.dart';
import '../core/widgets/hutube_widgets.dart';
import '../features/content/mini_player.dart';
import '../features/content/playback_session.dart';

class MobileScaffold extends StatelessWidget {
  const MobileScaffold({
    super.key,
    required this.auth,
    required this.playback,
    required this.location,
    required this.child,
  });

  final AuthController auth;
  final PlaybackSession playback;
  final String location;
  final Widget child;

  int get _selectedIndex {
    if (location.startsWith('/explore')) return 1;
    if (location.startsWith('/subscriptions')) return 3;
    if (location.startsWith('/account')) return 4;
    return 0;
  }

  void _select(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
      case 1:
        context.go('/explore');
      case 2:
        _showCreateSheet(context);
      case 3:
        context.go('/subscriptions');
      case 4:
        auth.authenticated ? context.go('/account') : context.go('/auth');
    }
  }

  void _showCreateSheet(BuildContext context) {
    if (!auth.authenticated) {
      context.go('/auth');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tạo nội dung',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                'Chọn cách bạn muốn bắt đầu trên HuTube.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _CreateAction(
                icon: Icons.cloud_upload_outlined,
                color: AppColors.primary,
                title: 'Đăng video',
                description: 'Chia sẻ video mới với cộng đồng.',
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.go('/creator');
                },
              ),
              _CreateAction(
                icon: Icons.playlist_add_rounded,
                color: AppColors.violet,
                title: 'Tạo playlist',
                description: 'Gom video vào bộ sưu tập riêng của bạn.',
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.go('/playlists');
                },
              ),
              _CreateAction(
                icon: Icons.storefront_outlined,
                color: AppColors.success,
                title: 'Tạo kênh',
                description: 'Thiết lập không gian riêng cho nội dung của bạn.',
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.go('/account');
                },
              ),
            ],
          ),
        ),
      ),
    );
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
        leadingWidth: wide ? 56 : 52,
        leading: Builder(
          builder: (drawerContext) => IconButton(
            tooltip: AppStrings.t('common.menu'),
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(drawerContext).openDrawer(),
          ),
        ),
        title: isDetail
            ? Text(AppStrings.t('app.viewVideo'))
            : const HuTubeLogo(size: 25),
        actions: [
          if (!isDetail)
            IconButton(
              tooltip: AppStrings.t('common.search'),
              onPressed: () => context.push('/search'),
              icon: const Icon(Icons.search_rounded),
            ),
          if (!isDetail)
            IconButton(
              tooltip: 'HuAI',
              onPressed: () => context.push('/huai'),
              icon: const Icon(Icons.auto_awesome_rounded),
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
              icon: HuTubeAvatar(
                label: initial,
                radius: 15,
                backgroundColor: AppColors.primary.withValues(alpha: .12),
              ),
            ),
          ),
        ],
      ),
      drawer: _Drawer(auth: auth),
      body: SafeArea(
        top: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            MiniPlayer(session: playback),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (value) => _select(context, value),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home_rounded),
                  label: AppStrings.t('nav.home'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.explore_outlined),
                  selectedIcon: const Icon(Icons.explore_rounded),
                  label: AppStrings.t('nav.explore'),
                ),
                const NavigationDestination(
                  icon: _CreateNavIcon(),
                  selectedIcon: _CreateNavIcon(selected: true),
                  label: 'Tạo',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.subscriptions_outlined),
                  selectedIcon: const Icon(Icons.subscriptions_rounded),
                  label: AppStrings.t('nav.subscriptions'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.person_outline_rounded),
                  selectedIcon: const Icon(Icons.person_rounded),
                  label: AppStrings.t('app.navYou'),
                ),
              ],
            ),
    );
  }
}

class _CreateNavIcon extends StatelessWidget {
  const _CreateNavIcon({this.selected = false});
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 32,
    decoration: BoxDecoration(
      color: selected ? AppColors.primaryDark : AppColors.primary,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.add_rounded, color: Colors.white, size: 23),
  );
}

class _CreateAction extends StatelessWidget {
  const _CreateAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 3),
    leading: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    subtitle: Text(description),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
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
          _item(
            context,
            Icons.subscriptions_outlined,
            AppStrings.t('nav.subscriptions'),
            '/subscriptions',
          ),
          _item(context, Icons.auto_awesome_outlined, 'HuAI', '/huai'),
          _item(
            context,
            Icons.playlist_play_outlined,
            'Playlist',
            '/playlists',
            protected: true,
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
          _item(
            context,
            Icons.report_gmailerrorred_outlined,
            'Báo cáo & kháng nghị',
            '/moderation',
            protected: true,
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
        fontWeight: FontWeight.w900,
        letterSpacing: 1.1,
      ),
    ),
  );
}
