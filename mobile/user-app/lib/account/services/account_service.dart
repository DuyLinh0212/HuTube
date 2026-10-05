import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../models/account_models.dart';
import 'package:image_picker/image_picker.dart';

class AccountService {
  AccountService(this.auth);
  final AuthController auth;

  Future<UserProfile> getProfile() async {
    final res = await auth.protected('GET', '/account/profile');
    return UserProfile.fromJson(res);
  }

  Future<UserProfile> updateProfile({
    required String displayName,
    String? bio,
    String? country,
  }) async {
    final res = await auth.protected(
      'PATCH',
      '/account/profile',
      body: {'displayName': displayName.trim(), 'bio': bio?.trim()},
    );
    if (country != null && country.trim().isNotEmpty) {
      final preferences = await getPreferences();
      await updatePreferences(preferences.copyWith(location: country.trim()));
    }
    // Update local user if displayName changed
    if (auth.user != null) {
      auth.user!['displayName'] = res['displayName'];
    }
    return UserProfile.fromJson(res);
  }

  Future<UserProfile> uploadAvatar(XFile image) async {
    final mime = image.mimeType ?? _imageMime(image.name);
    const allowed = {'image/jpeg', 'image/png', 'image/webp', 'image/gif'};
    if (!allowed.contains(mime)) {
      throw ApiFailure(
        400,
        'INVALID_FILE_TYPE',
        AppStrings.t('common.imageTypesAvatar'),
      );
    }
    final bytes = await image.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      throw ApiFailure(
        400,
        'FILE_TOO_LARGE',
        AppStrings.format('common.imageMaxSize', {'size': 5}),
      );
    }
    final response = await auth.protectedUpload(
      '/account/avatar',
      UploadPayload(
        bytes: bytes,
        fileName: image.name.trim().isEmpty ? 'avatar.jpg' : image.name,
        contentType: mime,
      ),
    );
    final profile = UserProfile.fromJson(response);
    if (auth.user != null) auth.user!['avatarUrl'] = profile.avatarUrl;
    return profile;
  }

  String _imageMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'application/octet-stream';
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    await auth.protected(
      'POST',
      '/account/change-password',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
  }

  Future<NotificationSettingModel> getNotificationSettings() async {
    final res = await auth.protected('GET', '/account/notifications');
    return NotificationSettingModel.fromJson(res);
  }

  Future<NotificationSettingModel> updateNotificationSettings(
    NotificationSettingModel settings,
  ) async {
    final res = await auth.protected(
      'PUT',
      '/account/notifications',
      body: settings.toJson(),
    );
    return NotificationSettingModel.fromJson(res);
  }

  Future<UserPreferencesModel> getPreferences() async {
    final res = await auth.protected('GET', '/account/settings');
    return UserPreferencesModel.fromJson(res);
  }

  Future<UserPreferencesModel> updatePreferences(
    UserPreferencesModel preferences,
  ) async {
    final res = await auth.protected(
      'PUT',
      '/account/settings',
      body: preferences.toJson(),
    );
    return UserPreferencesModel.fromJson(res);
  }

  Future<List<Map<String, dynamic>>> getSessions() async {
    final list = await auth.protectedList('/auth/sessions');
    return list.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> getLoginHistory({
    int page = 1,
    int pageSize = 20,
  }) => auth.protected(
    'GET',
    '/auth/login-history?page=$page&pageSize=$pageSize',
  );

  Future<void> revokeSession(String sessionId) async {
    await auth.protected('DELETE', '/auth/sessions/$sessionId');
  }

  Future<void> revokeOtherSessions() async {
    await auth.protected('POST', '/auth/logout-others');
  }

  Future<void> revokeAllSessions() async {
    await auth.protected('POST', '/auth/logout-all');
  }
}
