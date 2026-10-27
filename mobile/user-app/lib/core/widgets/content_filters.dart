import 'dart:async';
import 'package:flutter/material.dart';
import '../localization/app_strings.dart';

/// Search stays mounted while the results are loading, retaining keyboard focus.
class ContentFilters extends StatefulWidget {
  const ContentFilters({
    super.key,
    required this.onChanged,
    this.options = const {},
    this.initialQuery = '',
    this.initialValues = const {},
    this.compact = false,
  });
  final void Function(String query, Map<String, String> values) onChanged;
  final Map<String, List<String>> options;
  final String initialQuery;
  final bool compact;
  final Map<String, String> initialValues;
  @override
  State<ContentFilters> createState() => _ContentFiltersState();
}

class _ContentFiltersState extends State<ContentFilters> {
  final _query = TextEditingController();
  final _values = <String, String>{};
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _query.text = widget.initialQuery;
    _values.addAll(widget.initialValues);
  }

  void _emit() {
    _timer?.cancel();
    widget.onChanged(_query.text.trim(), Map.of(_values));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _query,
          decoration: InputDecoration(
            hintText: AppStrings.t('parity.search'),
            isDense: widget.compact,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            filled: widget.compact,
            fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
            border: widget.compact
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  )
                : null,
            enabledBorder: widget.compact
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  )
                : null,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    tooltip: AppStrings.t('parity.reset'),
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _query.clear();
                      setState(() {});
                      _emit();
                    },
                  ),
          ),
          onSubmitted: (_) => _emit(),
          onChanged: (_) {
            setState(() {});
            _timer?.cancel();
            _timer = Timer(const Duration(milliseconds: 300), _emit);
          },
        ),
        if (widget.options.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in widget.options.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: widget.compact
                          ? PopupMenuButton<String>(
                              key: ValueKey('content-filter-${entry.key}'),
                              tooltip: AppStrings.t('parity.${entry.key}'),
                              initialValue:
                                  _values[entry.key] ?? entry.value.first,
                              onSelected: (value) {
                                setState(() => _values[entry.key] = value);
                                _emit();
                              },
                              itemBuilder: (_) => [
                                for (final value in entry.value)
                                  CheckedPopupMenuItem(
                                    value: value,
                                    checked:
                                        value ==
                                        (_values[entry.key] ??
                                            entry.value.first),
                                    child: Text(AppStrings.t('parity.$value')),
                                  ),
                              ],
                              child: Chip(
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      AppStrings.t(
                                        'parity.${_values[entry.key] ?? entry.value.first}',
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.expand_more_rounded,
                                      size: 16,
                                    ),
                                  ],
                                ),
                                avatar: Icon(
                                  entry.key == 'sort'
                                      ? Icons.sort_rounded
                                      : entry.key == 'dateRange'
                                      ? Icons.schedule_rounded
                                      : Icons.tune_rounded,
                                  size: 17,
                                ),
                                deleteIcon: const Icon(
                                  Icons.expand_more_rounded,
                                  size: 18,
                                ),
                                onDeleted: null,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            )
                          : SizedBox(
                              width: 180,
                              child: DropdownButtonFormField<String>(
                                initialValue:
                                    _values[entry.key] ?? entry.value.first,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: AppStrings.t(
                                    'parity.${entry.key}',
                                  ),
                                  isDense: true,
                                ),
                                items: entry.value
                                    .map(
                                      (v) => DropdownMenuItem(
                                        value: v,
                                        child: Text(
                                          AppStrings.t('parity.$v'),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    _values[entry.key] = v;
                                    _emit();
                                  }
                                },
                              ),
                            ),
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

String normalizeContentText(String text) {
  const groups = [
    'àáạảãâầấậẩẫăằắặẳẵ',
    'èéẹẻẽêềếệểễ',
    'ìíịỉĩ',
    'òóọỏõôồốộổỗơờớợởỡ',
    'ùúụủũưừứựửữ',
    'ỳýỵỷỹ',
    'đ',
  ];
  var value = text.toLowerCase();
  for (var i = 0; i < groups.length; i++) {
    value = value.replaceAll(RegExp('[${groups[i]}]'), 'aeiouyd'[i]);
  }
  return value.replaceAll(RegExp(r'[\u0300-\u036f]'), '');
}
