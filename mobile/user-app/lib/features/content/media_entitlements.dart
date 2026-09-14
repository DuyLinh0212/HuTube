import '../../auth.dart';

/// Media capabilities granted by the signed-in account's active plan.
///
/// The client never assumes a paid capability when the plan snapshot cannot
/// be loaded. This prevents a stale UI from enabling background playback or
/// Picture-in-Picture for an account that no longer has that entitlement.
class MediaEntitlements {
  const MediaEntitlements({
    this.backgroundPlayback = false,
    this.pictureInPicture = false,
  });

  const MediaEntitlements.none()
    : backgroundPlayback = false,
      pictureInPicture = false;

  final bool backgroundPlayback;
  final bool pictureInPicture;

  factory MediaEntitlements.fromPayload(Map<String, dynamic> payload) {
    final rawFeatures = payload['features'];
    final features = rawFeatures is Map
        ? rawFeatures.map((key, value) => MapEntry('$key', value))
        : const <String, dynamic>{};
    return MediaEntitlements(
      backgroundPlayback: features['background_play'] == true,
      pictureInPicture: features['pip'] == true,
    );
  }

  static Future<MediaEntitlements> load(AuthController auth) async {
    if (!auth.authenticated) return const MediaEntitlements.none();
    try {
      final payload = await auth.protected('GET', '/plans/my-plan');
      return MediaEntitlements.fromPayload(payload);
    } catch (_) {
      return const MediaEntitlements.none();
    }
  }
}
