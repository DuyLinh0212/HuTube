import '../../auth.dart';
import '../models/account_models.dart';

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
      'PUT',
      '/account/profile',
      body: {
        'displayName': displayName.trim(),
        'bio': bio?.trim(),
        'country': country?.trim(),
      },
    );
    // Update local user if displayName changed
    if (auth.user != null) {
      auth.user!['displayName'] = res['displayName'];
    }
    return UserProfile.fromJson(res);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    await auth.protected(
      'POST',
      '/account/change-password',
      body: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      },
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
