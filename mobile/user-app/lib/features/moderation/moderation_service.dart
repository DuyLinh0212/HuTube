import '../../auth.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/localization/app_strings.dart';

class ModerationService {
  ModerationService(this.auth);
  final AuthController auth;

  String evidenceMime(XFile file) {
    final name = file.name.toLowerCase();
    if (name.endsWith('.pdf')) return 'application/pdf';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    throw ApiFailure(
      400,
      'EVIDENCE_INVALID',
      AppStrings.t('moderation.evidenceInvalid'),
    );
  }

  Future<void> validateEvidence(XFile file) async {
    evidenceMime(file);
    final length = await file.length();
    if (length == 0 || length > 10 * 1024 * 1024) {
      throw ApiFailure(
        400,
        'EVIDENCE_INVALID',
        AppStrings.t('moderation.evidenceInvalid'),
      );
    }
  }

  Future<void> uploadEvidence(String appealId, XFile file) async {
    await validateEvidence(file);
    await auth.protectedUpload(
      '/appeals/${Uri.encodeComponent(appealId)}/evidence',
      UploadPayload(
        bytes: await file.readAsBytes(),
        fileName: file.name,
        contentType: evidenceMime(file),
      ),
    );
  }

  Future<BinaryPayload> evidence(String appealId) => auth.protectedBinary(
    '/appeals/${Uri.encodeComponent(appealId)}/evidence',
  );

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
