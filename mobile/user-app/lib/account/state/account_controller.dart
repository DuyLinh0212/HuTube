import 'package:flutter/foundation.dart';
import '../../core/errors/app_error.dart';
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
      errorMessage = e.message;
    } catch (_) {
      errorMessage = 'Không thể tải thông tin hồ sơ.';
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
      successMessage = 'Cập nhật hồ sơ thành công.';
      return true;
    } on AppError catch (e) {
      errorMessage = e.message;
      return false;
    } catch (_) {
      errorMessage = 'Cập nhật hồ sơ thất bại.';
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
      successMessage = 'Đổi mật khẩu thành công.';
      return true;
    } on AppError catch (e) {
      errorMessage = e.message;
      return false;
    } catch (_) {
      errorMessage = 'Đổi mật khẩu thất bại.';
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
      errorMessage = e.message;
    } catch (_) {
      errorMessage = 'Không thể tải cài đặt thông báo.';
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
      successMessage = 'Đã lưu cài đặt thông báo.';
      return true;
    } on AppError catch (e) {
      errorMessage = e.message;
      return false;
    } catch (_) {
      errorMessage = 'Lưu cài đặt thông báo thất bại.';
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
      errorMessage = e.message;
    } catch (_) {
      errorMessage = 'Không thể tải tùy chọn phát và hiển thị.';
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
      successMessage = 'Đã lưu tùy chọn người dùng.';
      return true;
    } on AppError catch (e) {
      errorMessage = e.message;
      return false;
    } catch (_) {
      errorMessage = 'Lưu tùy chọn thất bại.';
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
      errorMessage = e.message;
    } catch (_) {
      errorMessage = 'Không thể tải danh sách phiên đăng nhập.';
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
      successMessage = 'Đã thu hồi phiên đăng nhập.';
      return true;
    } on AppError catch (e) {
      errorMessage = e.message;
      return false;
    } catch (_) {
      errorMessage = 'Thu hồi phiên đăng nhập thất bại.';
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
      successMessage = 'Đã đăng xuất khỏi các thiết bị khác.';
      return true;
    } on AppError catch (e) {
      errorMessage = e.message;
      return false;
    } catch (_) {
      errorMessage = 'Đăng xuất thiết bị khác thất bại.';
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }
}
