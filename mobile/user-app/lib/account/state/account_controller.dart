import 'package:flutter/foundation.dart';
import '../../core/errors/app_error.dart';
import '../../core/localization/app_strings.dart';
import '../models/account_models.dart';
import '../services/account_service.dart';

class AccountController extends ChangeNotifier {
  AccountController(this.service);
  final AccountService service;

  UserProfile? profile;
  NotificationSettingModel? notificationSettings;
  UserPreferencesModel? preferences;
  List<Map<String, dynamic>> sessions = [];

  bool loadingProfile = false;
  bool loadingNotifications = false;
  bool loadingPreferences = false;
  bool loadingSessions = false;
  bool submitting = false;

  String? errorMessage;
  String? successMessage;

  void clearMessages() {
    errorMessage = null;
    successMessage = null;
    notifyListeners();
  }

  Future<void> loadProfile() async {
    loadingProfile = true;
    errorMessage = null;
    notifyListeners();
    try {
      profile = await service.getProfile();
    } on AppError catch (e) {
      errorMessage = _error(e, 'account.profileLoadError');
    } catch (_) {
      errorMessage = AppStrings.t('account.profileLoadError');
    } finally {
      loadingProfile = false;
      notifyListeners();
    }
  }

  Future<bool> updateProfile({
    required String displayName,
    String? bio,
    String? country,
  }) async {
    submitting = true;
    errorMessage = null;
    successMessage = null;
    notifyListeners();
    try {
      profile = await service.updateProfile(
        displayName: displayName,
        bio: bio,
        country: country,
      );
      successMessage = AppStrings.t('profile.updated');
      return true;
    } on AppError catch (e) {
      errorMessage = _error(e, 'editProfile.saveError');
      return false;
    } catch (_) {
      errorMessage = AppStrings.t('editProfile.saveError');
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    submitting = true;
    errorMessage = null;
    successMessage = null;
    notifyListeners();
    try {
      await service.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
        confirmPassword: confirmPassword,
      );
      successMessage = AppStrings.t('password.updated');
      return true;
    } on AppError catch (e) {
      errorMessage = _error(e, 'password.error');
      return false;
    } catch (_) {
      errorMessage = AppStrings.t('password.error');
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<void> loadNotificationSettings() async {
    loadingNotifications = true;
    errorMessage = null;
    notifyListeners();
    try {
      notificationSettings = await service.getNotificationSettings();
    } on AppError catch (e) {
      errorMessage = _error(e, 'notif.loadError');
    } catch (_) {
      errorMessage = AppStrings.t('notif.loadError');
    } finally {
      loadingNotifications = false;
      notifyListeners();
    }
  }

  Future<bool> updateNotificationSettings(
    NotificationSettingModel settings,
  ) async {
    submitting = true;
    errorMessage = null;
    successMessage = null;
    notifyListeners();
    try {
      notificationSettings = await service.updateNotificationSettings(settings);
      successMessage = AppStrings.t('notifications.settingsSaved');
      return true;
    } on AppError catch (e) {
      errorMessage = _error(e, 'notif.saveError');
      return false;
    } catch (_) {
      errorMessage = AppStrings.t('notif.saveError');
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<void> loadPreferences() async {
    loadingPreferences = true;
    errorMessage = null;
    notifyListeners();
    try {
      preferences = await service.getPreferences();
    } on AppError catch (e) {
      errorMessage = _error(e, 'prefs.loadError');
    } catch (_) {
      errorMessage = AppStrings.t('prefs.loadError');
    } finally {
      loadingPreferences = false;
      notifyListeners();
    }
  }

  Future<bool> updatePreferences(UserPreferencesModel prefs) async {
    submitting = true;
    errorMessage = null;
    successMessage = null;
    notifyListeners();
    try {
      preferences = await service.updatePreferences(prefs);
      successMessage = AppStrings.t('prefs.saved');
      return true;
    } on AppError catch (e) {
      errorMessage = _error(e, 'prefs.saveError');
      return false;
    } catch (_) {
      errorMessage = AppStrings.t('prefs.saveError');
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<void> loadSessions() async {
    loadingSessions = true;
    errorMessage = null;
    notifyListeners();
    try {
      sessions = await service.getSessions();
    } on AppError catch (e) {
      errorMessage = _error(e, 'profile.sessionsEmpty');
    } catch (_) {
      errorMessage = AppStrings.t('profile.sessionsEmpty');
    } finally {
      loadingSessions = false;
      notifyListeners();
    }
  }

  Future<bool> revokeSession(String sessionId) async {
    submitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      await service.revokeSession(sessionId);
      sessions.removeWhere((s) => s['sessionId'] == sessionId);
      successMessage = AppStrings.t('profile.sessionRevoked');
      return true;
    } on AppError catch (e) {
      errorMessage = _error(e, 'profile.sessionRevokeError');
      return false;
    } catch (_) {
      errorMessage = AppStrings.t('profile.sessionRevokeError');
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<bool> revokeOtherSessions() async {
    submitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      await service.revokeOtherSessions();
      sessions.removeWhere((s) => s['isCurrent'] != true);
      successMessage = AppStrings.t('auth.otherDevicesLoggedOut');
      return true;
    } on AppError catch (e) {
      errorMessage = _error(e, 'profile.otherDevicesLogoutError');
      return false;
    } catch (_) {
      errorMessage = AppStrings.t('profile.otherDevicesLogoutError');
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  String _error(AppError error, String fallback) {
    return AppStrings.apiError(error, fallback: fallback);
  }
}
