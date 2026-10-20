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
  });
  final void Function(String query, Map<String, String> values) onChanged;
  final Map<String, List<String>> options;
  final String initialQuery;
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
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _query,
          decoration: InputDecoration(
            labelText: AppStrings.t('parity.search'),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: AppStrings.t('parity.reset'),
              icon: const Icon(Icons.clear),
              onPressed: () {
                _query.clear();
                _emit();
              },
            ),
          ),
          onSubmitted: (_) => _emit(),
          onChanged: (_) {
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
                      child: SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          initialValue: _values[entry.key] ?? entry.value.first,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: AppStrings.t('parity.${entry.key}'),
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
