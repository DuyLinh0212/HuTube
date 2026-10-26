import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/media/picture_in_picture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<Object?> incoming(String method, [Object? arguments]) async {
    final response = Completer<Object?>();
    await messenger.handlePlatformMessage(
      'hutube/picture_in_picture',
      codec.encodeMethodCall(MethodCall(method, arguments)),
      (reply) =>
          response.complete(reply == null ? null : codec.decodeEnvelope(reply)),
    );
    return response.future;
  }

  test(
    'native PiP lifecycle hides overlays before preparation and restores on exit',
    () async {
      final owner = Object();
      AppPictureInPicture.bind(owner, () async {
        expect(AppPictureInPicture.active.value, isTrue);
        return true;
      });
      addTearDown(() => AppPictureInPicture.unbind(owner));
      expect(await incoming('prepare'), isTrue);
      expect(AppPictureInPicture.active.value, isTrue);
      await incoming('modeChanged', false);
      expect(AppPictureInPicture.active.value, isFalse);
      await incoming('modeChanged', true);
      expect(AppPictureInPicture.active.value, isTrue);
    },
  );

  test(
    'failed preparation and stale owner cleanup do not leave PiP active',
    () async {
      final oldOwner = Object();
      final currentOwner = Object();
      AppPictureInPicture.bind(oldOwner, () async => true);
      AppPictureInPicture.bind(currentOwner, () async => false);
      AppPictureInPicture.unbind(oldOwner);
      expect(await incoming('prepare'), isFalse);
      expect(AppPictureInPicture.active.value, isFalse);
      AppPictureInPicture.unbind(currentOwner);
    },
  );
  test(
    'PiP fallback survives a watch route and throwing preparation restores overlays',
    () async {
      final mini = Object();
      final watch = Object();
      var fallbackCalls = 0;
      AppPictureInPicture.bindFallback(mini, () async {
        fallbackCalls++;
        return true;
      });
      AppPictureInPicture.bind(
        watch,
        () async => throw StateError('Preparation failed'),
      );
      expect(await incoming('prepare'), false);
      expect(AppPictureInPicture.active.value, false);
      expect(fallbackCalls, 0);
      AppPictureInPicture.unbind(watch);
      expect(await incoming('prepare'), true);
      expect(fallbackCalls, 1);
      AppPictureInPicture.unbind(mini);
      expect(AppPictureInPicture.active.value, false);
    },
  );
}
