import 'package:flutter/material.dart';
import '../localization/app_strings.dart';

class ConfirmationDialog extends StatelessWidget {
  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.destructive = false,
    this.icon = Icons.help_outline_rounded,
  });
  final String title, message, confirmLabel;
  final bool destructive;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return AlertDialog(
      scrollable: true,
      icon: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: destructive
                ? colors.errorContainer
                : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            icon,
            color: destructive
                ? colors.onErrorContainer
                : colors.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(title),
      content: Text(message),
      actionsOverflowButtonSpacing: 12,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(AppStrings.t('common.cancel')),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
