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
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 12,
            right: 12,
            child: _NetworkFallbackBanner(api: api),
          ),
      ],
    ),
  );
}

class _NetworkFallbackBanner extends StatelessWidget {
  const _NetworkFallbackBanner({required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final status = NetworkStatus.instance;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: .18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(
            children: [
              Icon(Icons.wifi_off_rounded, size: 24, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppStrings.t('network.title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: status.checking
                    ? null
                    : () => unawaited(api.checkConnection()),
                child: Text(
                  AppStrings.t(
                    status.checking ? 'network.checking' : 'common.retry',
                  ),
                ),
              ),
              IconButton(
                tooltip: AppStrings.t('common.close'),
                onPressed: status.continueOffline,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
