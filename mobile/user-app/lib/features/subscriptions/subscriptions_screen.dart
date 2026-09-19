import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';

/// The subscriptions endpoint is not part of the current mobile API surface.
/// Keep the destination useful and honest until that contract exists.
class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
    children: [
      Text(
        AppStrings.t('nav.subscriptions'),
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -.5,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        'Theo dõi những kênh bạn yêu thích ở một nơi.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 20),
      HuTubeSurface(
        color: AppColors.violetContainerFor(context),
        border: BorderSide(color: AppColors.violet.withValues(alpha: .12)),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.violet.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.violet,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Khi bạn theo dõi kênh, video mới sẽ xuất hiện tại đây.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
      HuTubeStateView(
        icon: Icons.subscriptions_outlined,
        title: 'Chưa có kênh nào để hiển thị',
        message: auth.authenticated
            ? 'Khám phá nội dung mới và theo dõi kênh bạn muốn xem thường xuyên.'
            : 'Đăng nhập để lưu các kênh bạn yêu thích và nhận cập nhật mới.',
        actionLabel: auth.authenticated
            ? 'Khám phá ngay'
            : AppStrings.t('common.signIn'),
        onAction: () => context.go(auth.authenticated ? '/explore' : '/auth'),
        accent: AppColors.violet,
      ),
    ],
  );
}
