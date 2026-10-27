import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import 'confirmation_dialog.dart';

class UnsavedChangesGuard extends StatefulWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.dirty,
    required this.busy,
    required this.child,
  });
  final bool dirty;
  final bool busy;
  final Widget child;
  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard> {
  bool _allowPop = false;
  bool _asking = false;
  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: _allowPop || (!widget.dirty && !widget.busy),
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || widget.busy || _asking) return;
      _asking = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (_) => ConfirmationDialog(
          title: AppStrings.t('form.discardTitle'),
          message: AppStrings.t('form.discardMessage'),
          confirmLabel: AppStrings.t('form.discard'),
          destructive: true,
          icon: Icons.edit_off_outlined,
        ),
      );
      _asking = false;
      if (!mounted || discard != true) return;
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (context.mounted) Navigator.of(context).pop(result);
    },
    child: widget.child,
  );
}
