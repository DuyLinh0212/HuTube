import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';

class VideoDescription extends StatefulWidget {
  const VideoDescription({
    super.key,
    required this.text,
    required this.duration,
    required this.onSeek,
  });

  final String text;
  final int duration;
  final ValueChanged<Duration> onSeek;

  @override
  State<VideoDescription> createState() => _VideoDescriptionState();
}

class _DescriptionPart {
  const _DescriptionPart(this.text, {this.url, this.seconds});
  final String text;
  final Uri? url;
  final int? seconds;
}

class _VideoDescriptionState extends State<VideoDescription> {
  bool _expanded = false;
  final _parts = <_DescriptionPart>[];
  final _recognizers = <int, TapGestureRecognizer>{};

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant VideoDescription oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.duration != widget.duration) {
      _parse();
    }
  }

  void _parse() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
    _parts.clear();
    _expanded = false;
    final pattern = RegExp(
      r'https?://[^\s<>]+|www\.[^\s<>]+|(?<![\w:])(?:\d{1,3}:)?\d{1,3}:[0-5]\d(?![\w:])',
      caseSensitive: false,
    );
    var cursor = 0;
    for (final match in pattern.allMatches(widget.text)) {
      if (match.start > cursor) {
        _parts.add(
          _DescriptionPart(widget.text.substring(cursor, match.start)),
        );
      }
      final value = match.group(0)!;
      if (RegExp(r'^(https?://|www\.)', caseSensitive: false).hasMatch(value)) {
        var link = value.replaceFirst(RegExp(r'[.,!?;:]+$'), '');
        while (link.endsWith(')') &&
            ')'.allMatches(link).length > '('.allMatches(link).length) {
          link = link.substring(0, link.length - 1);
        }
        final uri = Uri.tryParse(
          link.toLowerCase().startsWith('www.') ? 'https://$link' : link,
        );
        _parts.add(
          _DescriptionPart(
            link,
            url:
                uri != null &&
                    uri.hasAuthority &&
                    uri.host.isNotEmpty &&
                    ['http', 'https'].contains(uri.scheme)
                ? uri
                : null,
          ),
        );
        if (link.length < value.length) {
          _parts.add(_DescriptionPart(value.substring(link.length)));
        }
      } else {
        final units = value.split(':').map(int.parse).toList();
        final seconds = units.fold<int>(0, (total, unit) => total * 60 + unit);
        final valid =
            (units.length == 2 || units[1] < 60) &&
            (widget.duration <= 0 || seconds <= widget.duration);
        _parts.add(_DescriptionPart(value, seconds: valid ? seconds : null));
      }
      cursor = match.end;
    }
    if (cursor < widget.text.length) {
      _parts.add(_DescriptionPart(widget.text.substring(cursor)));
    }
    for (var index = 0; index < _parts.length; index++) {
      final part = _parts[index];
      if (part.url != null || part.seconds != null) {
        _recognizers[index] = TapGestureRecognizer()
          ..onTap = () {
            if (part.seconds != null) {
              widget.onSeek(Duration(seconds: part.seconds!));
            } else {
              unawaited(_openLink(part.url!));
            }
          };
      }
    }
  }

  Future<void> _openLink(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      /* Show the same feedback for unavailable external apps. */
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.t('common.error'))));
    }
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.copyWith(height: 1.5);
    final linkColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.primaryHover
        : AppColors.primaryDark;
    final span = TextSpan(
      style: style,
      children: [
        for (var index = 0; index < _parts.length; index++)
          TextSpan(
            text: _parts[index].text,
            style: _recognizers.containsKey(index)
                ? TextStyle(
                    color: linkColor,
                    decoration: TextDecoration.underline,
                  )
                : null,
            recognizer: _recognizers[index],
          ),
      ],
    );
    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: span,
            maxLines: 3,
            ellipsis: '…',
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            locale: Localizations.maybeLocaleOf(context),
          )..layout(maxWidth: constraints.maxWidth);
          final overflows = painter.didExceedMaxLines;
          painter.dispose();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text.rich(
                span,
                maxLines: _expanded ? null : 3,
                overflow: _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
              ),
              if (overflows)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Semantics(
                    expanded: _expanded,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textPrimaryFor(context),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        minimumSize: const Size(48, 44),
                        alignment: AlignmentDirectional.centerStart,
                      ),
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(
                        AppStrings.t(
                          _expanded
                              ? 'watch.descriptionLess'
                              : 'watch.descriptionMore',
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
