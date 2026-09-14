import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/content/media_entitlements.dart';

void main() {
  test('reads background and PiP permissions from the plan feature map', () {
    final entitlements = MediaEntitlements.fromPayload({
      'features': {'background_play': true, 'pip': true},
    });

    expect(entitlements.backgroundPlayback, isTrue);
    expect(entitlements.pictureInPicture, isTrue);
  });

  test(
    'defaults to disabled media capabilities for missing or invalid data',
    () {
      expect(
        MediaEntitlements.fromPayload(const {}).backgroundPlayback,
        isFalse,
      );
      expect(
        MediaEntitlements.fromPayload({
          'features': 'not-a-map',
        }).pictureInPicture,
        isFalse,
      );
    },
  );
}
