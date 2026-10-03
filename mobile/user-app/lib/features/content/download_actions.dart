/// Actions supported by the API; local transfer state is managed separately.
List<String> remoteDownloadActions(String status) =>
    switch (status.toLowerCase()) {
      'ready' => const ['download', 'cancel', 'delete'],
      'pending' || 'processing' => const ['pause', 'cancel', 'delete'],
      'cancelled' => const ['resume', 'retry', 'delete'],
      'failed' => const ['retry', 'cancel', 'delete'],
      _ => const ['delete'],
    };
