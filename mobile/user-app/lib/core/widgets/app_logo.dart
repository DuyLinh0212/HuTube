import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class HuTubeLogo extends StatelessWidget {
  const HuTubeLogo({super.key, this.size = 32, this.showWordmark = true});
  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          'assets/logo-mark.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
        if (showWordmark) ...[
          const SizedBox(width: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Hu',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.68,
                    color: Theme.of(context).colorScheme.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
                TextSpan(
                  text: 'Tube',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.68,
                    color: AppColors.primaryPink,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
