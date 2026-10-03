import 'dart:async';

import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../network/api_client.dart';
import '../network/network_status.dart';

class NetworkFallbackOverlay extends StatelessWidget {
  const NetworkFallbackOverlay({
    super.key,
    required this.child,
    required this.api,
  });

  final Widget child;
  final ApiClient api;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: NetworkStatus.instance,
    builder: (context, _) => Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (NetworkStatus.instance.showFallback)
          Positioned.fill(
            child: _NetworkFallbackScreen(api: api),
          ),
      ],
    ),
  );
}

class _NetworkFallbackScreen extends StatelessWidget {
  const _NetworkFallbackScreen({required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final status = NetworkStatus.instance;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 36,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .08),
                      blurRadius: 36,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Icon(
                        Icons.wifi_off_rounded,
                        size: 42,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 25),
                    Text(
                      'HuTube',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      AppStrings.t('network.title'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppStrings.t('network.description'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 26),
                    FilledButton.icon(
                      onPressed: status.checking
                          ? null
                          : () => unawaited(api.checkConnection()),
                      icon: status.checking
                          ? SizedBox.square(
                              dimension: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.onPrimary,
                              ),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: Text(
                        AppStrings.t(
                          status.checking ? 'network.checking' : 'common.retry',
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(156, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: status.continueOffline,
                      child: Text(AppStrings.t('network.continueOffline')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
