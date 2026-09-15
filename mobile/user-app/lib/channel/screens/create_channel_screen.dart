import 'dart:async';
import 'package:flutter/material.dart';
import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/error_banner.dart';
import '../services/channel_service.dart';
import 'channel_screen.dart';

class CreateChannelScreen extends StatefulWidget {
  const CreateChannelScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<CreateChannelScreen> createState() => _CreateChannelScreenState();
}

class _CreateChannelScreenState extends State<CreateChannelScreen> {
  final _nameController = TextEditingController();
  final _handleController = TextEditingController();
  final _descriptionController = TextEditingController();

  late final ChannelService _channelService;

  bool _busy = false;
  bool _checkingHandle = false;
  bool? _handleAvailable;
  String? _error;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _channelService = ChannelService(widget.auth);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _nameController.dispose();
    _handleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _onHandleChanged(String value) {
    _debounceTimer?.cancel();
    final clean = value.startsWith('@')
        ? value.substring(1).trim()
        : value.trim();

    if (clean.length < 3) {
      setState(() {
        _handleAvailable = null;
        _checkingHandle = false;
      });
      return;
    }

    setState(() {
      _checkingHandle = true;
      _handleAvailable = null;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      final available = await _channelService.checkHandle(clean);
      if (mounted) {
        setState(() {
          _handleAvailable = available;
          _checkingHandle = false;
        });
      }
    });
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    var handle = _handleController.text.trim();
    if (handle.startsWith('@')) handle = handle.substring(1);

    if (name.isEmpty) {
      setState(() => _error = AppStrings.t('channel.nameRequired'));
      return;
    }
    if (handle.length < 3 || handle.length > 50) {
      setState(() => _error = AppStrings.t('channel.handleInvalid'));
      return;
    }
    if (_handleAvailable == false) {
      setState(() => _error = AppStrings.t('channel.handleTaken'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final created = await _channelService.createChannel(
        name: name,
        handle: handle,
        description: _descriptionController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.t('channel.created')),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Replace with Channel view
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ChannelScreen(
              auth: widget.auth,
              channelOrHandle: created.handle,
            ),
          ),
        );
      }
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = AppStrings.apiError(e, fallback: 'channel.createError'),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppStrings.t('channel.createError'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.t('channel.createTitle')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Rule banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryPink.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.primaryPink.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: AppColors.primaryPink,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.t('channel.rulesTitle'),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryPink,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            AppStrings.t('channel.rulesDescription'),
                            style: TextStyle(
                              color: AppColors.textPrimaryFor(context),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: 16),
              ],

              Text(
                '${AppStrings.t('channel.createName')} *',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                enabled: !_busy,
                decoration: InputDecoration(
                  hintText: AppStrings.t('channel.createNameHint'),
                  prefixIcon: Icon(Icons.tv_outlined),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                '${AppStrings.t('channel.createHandle')} *',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _handleController,
                enabled: !_busy,
                onChanged: _onHandleChanged,
                decoration: InputDecoration(
                  hintText: AppStrings.t('channel.createHandleHint'),
                  prefixIcon: const Icon(Icons.alternate_email),
                  suffixIcon: _checkingHandle
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primaryPink,
                            ),
                          ),
                        )
                      : _handleAvailable == true
                      ? const Icon(Icons.check_circle, color: AppColors.success)
                      : _handleAvailable == false
                      ? Icon(Icons.cancel, color: AppColors.dangerFor(context))
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  _handleAvailable == true
                      ? AppStrings.t('channel.handleAvailable')
                      : _handleAvailable == false
                      ? AppStrings.t('channel.handleUnavailable')
                      : AppStrings.t('channel.handleDescription'),
                  style: TextStyle(
                    fontSize: 12,
                    color: _handleAvailable == true
                        ? AppColors.success
                        : _handleAvailable == false
                        ? AppColors.dangerFor(context)
                        : AppColors.textMutedFor(context),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                AppStrings.t('channel.createDescription'),
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descriptionController,
                enabled: !_busy,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: AppStrings.t('channel.descriptionHint'),
                ),
              ),
              const SizedBox(height: 32),

              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(AppStrings.t('channel.createAction')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
