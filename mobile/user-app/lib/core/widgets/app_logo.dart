import 'package:flutter/material.dart';

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
                    color: const Color(0xFF111827),
                    letterSpacing: -0.5,
                  ),
                ),
                TextSpan(
                  text: 'Tube',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.68,
                    color: const Color(0xFFFF2B66),
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
