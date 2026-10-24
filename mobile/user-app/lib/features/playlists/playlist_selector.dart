import 'package:flutter/material.dart';
import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import 'playlist_service.dart';

class PlaylistSelector extends StatefulWidget {
  const PlaylistSelector({
    super.key,
    required this.auth,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });
  final AuthController auth;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;
  @override
  State<PlaylistSelector> createState() => _PlaylistSelectorState();
}

class _PlaylistSelectorState extends State<PlaylistSelector> {
  List<PlaylistSummary> _items = [];
  bool _loading = true;
  bool _error = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = widget.auth.sessionGeneration;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final items = await PlaylistService(widget.auth).mine();
      if (mounted && session == widget.auth.sessionGeneration) {
        setState(() => _items = items);
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(AppStrings.t('parity.playlist')),
    subtitle: Text('${widget.selected.length}'),
    children: [
      if (_loading)
        const LinearProgressIndicator()
      else if (_error)
        TextButton(onPressed: _load, child: Text(AppStrings.t('common.retry')))
      else if (_items.isEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(AppStrings.t('playlists.emptyTitle')),
        )
      else
        for (final item in _items)
          CheckboxListTile(
            value: widget.selected.contains(item.id),
            title: Text(item.name),
            onChanged: !widget.enabled
                ? null
                : (checked) {
                    final values = Set<String>.of(widget.selected);
                    if (checked == true) {
                      values.add(item.id);
                    } else {
                      values.remove(item.id);
                    }
                    widget.onChanged(values);
                  },
          ),
    ],
  );
}
