import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import 'modal_header.dart';

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
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 16, bottom: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ModalHeader(title: widget.title, icon: Icons.edit_note_rounded),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                key: const ValueKey('text-entry-input'),
                controller: _controller,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                maxLength: widget.maxLength,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: OverflowBar(
                spacing: 12,
                overflowSpacing: 12,
                alignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
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
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
