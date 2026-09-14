import 'package:flutter/material.dart';

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.isError = true});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isError ? const Color(0xffffeae8) : const Color(0xfffff0f4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isError ? const Color(0xffffc8c4) : const Color(0xffffccd8),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError
                  ? const Color(0xff962c26)
                  : const Color(0xffc2185b),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isError
                      ? const Color(0xff962c26)
                      : const Color(0xffc2185b),
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
