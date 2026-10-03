import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/content/download_actions.dart';

void main() {
  test(
    'download actions follow every server status and deny revoked requests',
    () {
      expect(remoteDownloadActions('ready'), ['download', 'cancel', 'delete']);
      expect(remoteDownloadActions('pending'), ['pause', 'cancel', 'delete']);
      expect(remoteDownloadActions('processing'), [
        'pause',
        'cancel',
        'delete',
      ]);
      expect(remoteDownloadActions('cancelled'), ['resume', 'retry', 'delete']);
      expect(remoteDownloadActions('failed'), ['retry', 'cancel', 'delete']);
      expect(remoteDownloadActions('revoked'), ['delete']);
      expect(remoteDownloadActions('unrecognized'), ['delete']);
    },
  );
}
