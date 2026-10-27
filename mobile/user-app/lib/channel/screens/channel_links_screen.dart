import 'dart:convert';
import 'package:flutter/material.dart';
import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/hutube_widgets.dart';
import '../../core/widgets/unsaved_changes_guard.dart';
import '../models/channel_models.dart';
import '../models/channel_links.dart';
import '../services/channel_service.dart';

class ChannelLinksScreen extends StatefulWidget {
  const ChannelLinksScreen({
    super.key,
    required this.auth,
    required this.channel,
  });
  final AuthController auth;
  final ChannelDetail channel;
  @override
  State<ChannelLinksScreen> createState() => _ChannelLinksScreenState();
}

class _LinkDraft {
  _LinkDraft(Map<String, String> value)
    : platform = value['platform'] ?? 'other',
      title = TextEditingController(text: value['title']),
      url = TextEditingController(text: value['url']);
  final key = UniqueKey();
  String platform;
  final TextEditingController title, url;
  Map<String, String> get value => {
    'platform': platform,
    'title': title.text.trim(),
    'url': url.text.trim(),
  };
  void dispose() {
    title.dispose();
    url.dispose();
  }
}

class _ChannelLinksScreenState extends State<ChannelLinksScreen> {
  final _form = GlobalKey<FormState>();
  final List<_LinkDraft> _links = [];
  Map<String, dynamic> _settings = {};
  String _original = '[]';
  bool _loading = true, _busy = false, _saved = false;
  String? _error;
  late final _session = widget.auth.sessionGeneration;
  late ChannelDetail _channel = widget.channel;
  bool get _dirty =>
      !_saved && jsonEncode(_links.map((l) => l.value).toList()) != _original;
  bool get _current => mounted && _session == widget.auth.sessionGeneration;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final channel = await ChannelService(
        widget.auth,
      ).getChannelById(_channel.id, refresh: true);
      if (!_current) return;
      final raw = jsonDecode(channel.settings ?? '{}');
      setState(() {
        _channel = channel;
        _settings = raw is Map ? Map<String, dynamic>.from(raw) : {};
        for (final item in _links) {
          item.dispose();
        }
        _links.clear();
        _links.addAll(
          channelLinks(channel.settings, validOnly: false).map(_LinkDraft.new),
        );
        _original = jsonEncode(_links.map((l) => l.value).toList());
        _loading = false;
      });
    } catch (_) {
      if (_current) {
        setState(() {
          _loading = false;
          _error = AppStrings.t('channel.loadError');
        });
      }
    }
  }

  @override
  void dispose() {
    for (final link in _links) {
      link.dispose();
    }
    super.dispose();
  }

  void _move(int index, int to) =>
      setState(() => _links.insert(to, _links.removeAt(index)));
  Future<void> _save() async {
    if (_busy ||
        !_current ||
        !_channel.can('channel.edit_profile') ||
        !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Re-read immediately before merging so unrelated channel settings survive.
      final latest = await ChannelService(
        widget.auth,
      ).getChannelById(_channel.id, refresh: true);
      if (!_current) return;
      final decoded = jsonDecode(latest.settings ?? '{}');
      final settings = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : _settings;
      settings['links'] = _links.map((l) => l.value).toList();
      await ChannelService(widget.auth).updateChannel(
        latest.id,
        name: latest.name,
        description: latest.description,
        settings: jsonEncode(settings),
      );
      if (!_current) return;
      setState(() {
        _saved = true;
        _busy = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, true);
    } on ApiFailure catch (e) {
      if (_current) {
        setState(
          () =>
              _error = AppStrings.apiError(e, fallback: 'channel.updateError'),
        );
      }
    } catch (_) {
      if (_current) {
        setState(() => _error = AppStrings.t('channel.updateError'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
    dirty: _dirty,
    busy: _busy,
    child: Scaffold(
      appBar: AppBar(title: Text(AppStrings.t('channel.socialLinks'))),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              key: const ValueKey('links-save'),
              onPressed:
                  _loading ||
                      _busy ||
                      !_dirty ||
                      !_channel.can('channel.edit_profile')
                  ? null
                  : _save,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                AppStrings.t(_busy ? 'common.saving' : 'common.save'),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    _channel.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.t('channel.linksHint'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    ErrorBanner(message: _error!),
                    TextButton(
                      onPressed: _load,
                      child: Text(AppStrings.t('common.retry')),
                    ),
                  ],
                  for (var i = 0; i < _links.length; i++)
                    Padding(
                      key: _links[i].key,
                      padding: const EdgeInsets.only(bottom: 16),
                      child: HuTubeSurface(
                        padding: const EdgeInsets.all(16),
                        borderRadius: 18,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    AppStrings.format('channel.linkNumber', {
                                      'number': i + 1,
                                    }),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: AppStrings.t('channel.moveLinkUp'),
                                  onPressed: _busy || i == 0
                                      ? null
                                      : () => _move(i, i - 1),
                                  icon: const Icon(Icons.arrow_upward_rounded),
                                ),
                                IconButton(
                                  tooltip: AppStrings.t('channel.moveLinkDown'),
                                  onPressed: _busy || i == _links.length - 1
                                      ? null
                                      : () => _move(i, i + 1),
                                  icon: const Icon(
                                    Icons.arrow_downward_rounded,
                                  ),
                                ),
                                IconButton(
                                  tooltip: AppStrings.t('common.delete'),
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                          _links.removeAt(i).dispose();
                                        }),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue:
                                  const [
                                    'facebook',
                                    'instagram',
                                    'tiktok',
                                    'x',
                                    'other',
                                  ].contains(_links[i].platform)
                                  ? _links[i].platform
                                  : 'other',
                              decoration: InputDecoration(
                                labelText: AppStrings.t('channel.linkPlatform'),
                              ),
                              items:
                                  [
                                        'facebook',
                                        'instagram',
                                        'tiktok',
                                        'x',
                                        'other',
                                      ]
                                      .map(
                                        (p) => DropdownMenuItem(
                                          value: p,
                                          child: Text(_platform(p)),
                                        ),
                                      )
                                      .toList(),
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(
                                      () => _links[i].platform = value!,
                                    ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              key: ValueKey('link-title-$i'),
                              controller: _links[i].title,
                              enabled: !_busy,
                              maxLength: 60,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: AppStrings.t('channel.linkTitle'),
                                counterText: '',
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? AppStrings.t('channel.linkTitleRequired')
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              key: ValueKey('link-url-$i'),
                              controller: _links[i].url,
                              enabled: !_busy,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'URL',
                                hintText: 'https://',
                              ),
                              validator: (v) => isPublicWebLink(v ?? '')
                                  ? null
                                  : AppStrings.t('channel.linkUrlError'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed:
                        _busy ||
                            _links.length >= 14 ||
                            !_channel.can('channel.edit_profile')
                        ? null
                        : () => setState(() {
                            _links.add(
                              _LinkDraft({
                                'platform': 'other',
                                'title': '',
                                'url': '',
                              }),
                            );
                          }),
                    icon: const Icon(Icons.add_link_rounded),
                    label: Text(AppStrings.t('channel.addLink')),
                  ),
                ],
              ),
            ),
    ),
  );
  String _platform(String p) => switch (p) {
    'facebook' => 'Facebook',
    'instagram' => 'Instagram',
    'tiktok' => 'TikTok',
    'x' => 'X',
    _ => AppStrings.t('channel.otherLink'),
  };
}
