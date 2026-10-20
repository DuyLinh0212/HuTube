import 'package:flutter/material.dart';

import '../localization/app_strings.dart';

/// Owns the input until the dialog's closing animation has finished.
class TextEntryDialog extends StatefulWidget {
  const TextEntryDialog({
    super.key,
    required this.title,
    required this.submitLabel,
    this.initialValue = '',
    this.hint,
    this.maxLength = 2000,
  });

  final String title;
  final String submitLabel;
  final String initialValue;
  final String? hint;
  final int maxLength;

  @override
  State<TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<TextEntryDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.title),
    content: TextField(
      key: const ValueKey('text-entry-input'),
      controller: _controller,
      autofocus: true,
      minLines: 2,
      maxLines: 5,
      maxLength: widget.maxLength,
      decoration: InputDecoration(hintText: widget.hint),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(AppStrings.t('common.cancel')),
      ),
      FilledButton(
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _controller.text.trim()),
        child: Text(widget.submitLabel),
      ),
    ],
  );
}
