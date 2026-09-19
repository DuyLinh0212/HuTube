import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hutube_widgets.dart';

/// HuAI visual shell. The conversation API is not available in the current
/// mobile contract, so the composer stays clearly disabled instead of
/// presenting fabricated assistant messages.
class HuAiScreen extends StatelessWidget {
  const HuAiScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
    children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF28194B), AppColors.violet],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'HuAI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w900,
                letterSpacing: -.7,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Trợ lý thông minh cho hành trình xem và sáng tạo của bạn.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .76),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      HuTubeSectionHeader(
        title: 'Bạn có thể hỏi HuAI',
        subtitle: 'Các gợi ý sẽ sẵn sàng khi dịch vụ được kết nối.',
      ),
      const SizedBox(height: 12),
      _Suggestion(
        icon: Icons.explore_outlined,
        label: 'Gợi ý nội dung phù hợp với tôi',
        onTap: () => _notice(context),
      ),
      _Suggestion(
        icon: Icons.video_library_outlined,
        label: 'Giải thích cách dùng HuTube',
        onTap: () => _notice(context),
      ),
      _Suggestion(
        icon: Icons.lightbulb_outline_rounded,
        label: 'Gợi ý ý tưởng cho video mới',
        onTap: () => _notice(context),
      ),
      const SizedBox(height: 18),
      HuTubeStateView(
        icon: Icons.forum_outlined,
        title: auth.authenticated
            ? 'HuAI đang được chuẩn bị'
            : 'Đăng nhập để dùng HuAI',
        message:
            'Tính năng hội thoại chưa có API trong phiên bản mobile hiện tại.',
        compact: true,
        accent: AppColors.violet,
      ),
      const SizedBox(height: 8),
      TextField(
        enabled: false,
        decoration: InputDecoration(
          hintText: 'Nhắn tin với HuAI',
          prefixIcon: const Icon(Icons.chat_bubble_outline_rounded),
          suffixIcon: IconButton(
            onPressed: null,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ),
      ),
    ],
  );

  void _notice(BuildContext context) =>
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('HuAI sẽ hoạt động khi API hội thoại được kết nối.'),
        ),
      );
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: AppColors.violetContainerFor(context),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.violet.withValues(alpha: .14)),
    ),
    child: ListTile(
      leading: Icon(icon, color: AppColors.violet),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
      onTap: onTap,
    ),
  );
}
