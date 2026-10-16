import '../../auth.dart';

class FeedbackSurveyStatus {
  const FeedbackSurveyStatus({
    required this.enabled,
    required this.hasCompleted,
    this.formUri,
  });

  final bool enabled;
  final bool hasCompleted;
  final Uri? formUri;

  factory FeedbackSurveyStatus.fromJson(Map<String, dynamic> json) {
    final rawUrl = json['formUrl'];
    final uri = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    final valid =
        uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'docs.google.com' &&
        uri.userInfo.isEmpty &&
        !uri.hasPort &&
        uri.path ==
            '/forms/d/e/1FAIpQLSef9jF_PK4qnoEZjPjS7kq1Lk4iQbEtoSXxS8XMkoWcVcoecg/viewform';
    return FeedbackSurveyStatus(
      enabled: json['enabled'] == true,
      hasCompleted: json['hasCompleted'] == true,
      formUri: valid ? uri : null,
    );
  }
}

class FeedbackSurveyService {
  const FeedbackSurveyService(this.auth);

  final AuthController auth;

  Future<FeedbackSurveyStatus> getStatus() async =>
      FeedbackSurveyStatus.fromJson(
        await auth.protected('GET', '/feedback-survey'),
      );
}
