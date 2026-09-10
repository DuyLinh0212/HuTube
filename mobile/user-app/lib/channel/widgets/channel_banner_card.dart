import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../models/channel_models.dart';

class ChannelBannerCard extends StatelessWidget {
  const ChannelBannerCard({
    super.key,
    required this.channel,
    this.onEditBranding,
  });

  final ChannelDetail channel;
  final VoidCallback? onEditBranding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Banner image or gradient placeholder
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: AppColors.cardBorder,
            image: channel.bannerUrl != null
                ? DecorationImage(
                    image: NetworkImage(channel.bannerUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
            gradient: channel.bannerUrl == null
                ? const LinearGradient(
                    colors: [
                      Color(0xFF33101E),
                      Color(0xFF1E1020),
                      Color(0xFF10121E),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
          ),
          child: onEditBranding != null
              ? Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: IconButton.filledTonal(
                      icon: const Icon(Icons.camera_alt, size: 18),
                      onPressed: onEditBranding,
                      tooltip: 'Đổi ảnh bìa',
                    ),
                  ),
                )
              : null,
        ),

        // Channel Info Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: AppColors.primaryPink,
                backgroundImage: channel.avatarUrl != null
                    ? NetworkImage(channel.avatarUrl!)
                    : null,
                child: channel.avatarUrl == null
                    ? Text(
                        channel.name.isNotEmpty
                            ? channel.name[0].toUpperCase()
                            : 'C',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            channel.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.check_circle,
                          size: 16,
                          color: AppColors.primaryPink,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${channel.handle}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${channel.subscriberCount} người đăng ký · ${channel.videoCount} video',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
