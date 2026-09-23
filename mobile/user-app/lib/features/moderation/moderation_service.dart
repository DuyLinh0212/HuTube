import '../../auth.dart';

class ModerationService {
  ModerationService(this.auth);
  final AuthController auth;

  Future<List<Map<String, dynamic>>> violationTypes() async =>
      (await auth.api.requestList('GET', '/violation-types'))
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  Future<Map<String, dynamic>> createReport({
    required String targetType,
    required String targetId,
    required String violationTypeId,
    required String description,
  }) => auth.protected(
    'POST',
    '/reports',
    body: {
      'targetType': targetType,
      'targetId': targetId,
      'violationTypeId': violationTypeId,
      'description': description.trim(),
    },
  );

  Future<Map<String, dynamic>> reportVideo({
    required String videoId,
    required String violationTypeId,
    required String description,
  }) => auth.protected(
    'POST',
    '/videos/${Uri.encodeComponent(videoId)}/report',
    body: {
      'violationTypeId': violationTypeId,
      'description': description.trim(),
    },
  );

  Future<Map<String, dynamic>> reportChannel({
    required String channelId,
    required String violationTypeId,
    required String description,
  }) => auth.protected(
    'POST',
    '/channels/${Uri.encodeComponent(channelId)}/report',
    body: {
      'violationTypeId': violationTypeId,
      'description': description.trim(),
    },
  );

  Future<Map<String, dynamic>> reportComment({
    required String commentId,
    required String violationTypeId,
    required String description,
  }) => auth.protected(
    'POST',
    '/comments/${Uri.encodeComponent(commentId)}/report',
    body: {
      'violationTypeId': violationTypeId,
      'description': description.trim(),
    },
  );

  Future<List<Map<String, dynamic>>> myAppeals() async =>
      (await auth.protectedList('/appeals/my'))
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  Future<Map<String, dynamic>> createAppeal({
    required String targetType,
    required String targetId,
    required String reason,
    String? evidenceUrl,
    String? evidenceNote,
    String? moderationCaseId,
    String? strikeId,
  }) => auth.protected(
    'POST',
    '/appeals',
    body: {
      'targetType': targetType,
      'targetId': targetId,
      'reason': reason.trim(),
      'evidenceUrl': evidenceUrl?.trim(),
      'evidenceNote': evidenceNote?.trim(),
      'moderationCaseId': moderationCaseId,
      'strikeId': strikeId,
    },
  );

  Future<Map<String, dynamic>> channelStrikes(String channelId) => auth
      .protected('GET', '/channels/${Uri.encodeComponent(channelId)}/strikes');
}
