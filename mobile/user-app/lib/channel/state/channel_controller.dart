import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/errors/app_error.dart';
import '../models/channel_models.dart';
import '../services/channel_service.dart';

class ChannelController extends ChangeNotifier {
  ChannelController(this.service);
  final ChannelService service;

  ChannelDetail? myChannel;
  ChannelDetail? viewingChannel;
  List<ChannelRole> roles = [];
  List<ChannelMember> members = [];
  List<ChannelInvitation> pendingInvitations = [];
  List<ChannelInvitation> myInvitations = [];

  bool loadingChannel = false;
  bool loadingMembers = false;
  bool loadingInvitations = false;
  bool submitting = false;

  String? errorMessage;
  String? successMessage;

  void clearMessages() {
    errorMessage = null;
    successMessage = null;
    notifyListeners();
  }

  Future<void> loadMyChannel() async {
    loadingChannel = true;
    errorMessage = null;
    notifyListeners();
    try {
      myChannel = await service.getMyChannel();
    } on AppError catch (e) {
      errorMessage = e.message;
    } catch (_) {
      errorMessage = 'Không thể tải thông tin kênh.';
    } finally {
      loadingChannel = false;
      notifyListeners();
    }
  }

  Future<void> loadChannel(String handleOrId) async {
    loadingChannel = true;
    errorMessage = null;
    notifyListeners();
    try {
      viewingChannel = await service.getChannel(handleOrId);
    } on AppError catch (e) {
      errorMessage = e.message;
    } catch (_) {
      errorMessage = 'Không thể tải thông tin kênh.';
    } finally {
      loadingChannel = false;
      notifyListeners();
    }
  }

  Future<ChannelDetail?> createChannel({
    required String name,
    required String handle,
    String? description,
  }) async {
    submitting = true;
    errorMessage = null;
    successMessage = null;
    notifyListeners();
    try {
      final channel = await service.createChannel(
        name: name,
        handle: handle,
        description: description,
      );
      myChannel = channel;
      successMessage = 'Tạo kênh thành công!';
      return channel;
    } on AppError catch (e) {
      errorMessage = e.message;
      return null;
    } catch (_) {
      errorMessage = 'Tạo kênh thất bại. Vui lòng thử lại.';
      return null;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<ChannelDetail?> updateChannel(
    String id, {
    required String name,
    String? description,
  }) async {
    submitting = true;
    errorMessage = null;
    successMessage = null;
    notifyListeners();
    try {
      final updated = await service.updateChannel(
        id,
        name: name,
        description: description,
      );
      if (myChannel?.id == id) myChannel = updated;
      if (viewingChannel?.id == id) viewingChannel = updated;
      successMessage = 'Cập nhật thông tin kênh thành công!';
      return updated;
    } on AppError catch (e) {
      errorMessage = e.message;
      return null;
    } catch (_) {
      errorMessage = 'Cập nhật kênh thất bại.';
      return null;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<ChannelDetail?> uploadAvatar(String channelId, XFile file) async {
    submitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      final updated = await service.uploadAvatar(channelId, file);
      if (myChannel?.id == channelId) myChannel = updated;
      if (viewingChannel?.id == channelId) viewingChannel = updated;
      successMessage = 'Đã cập nhật ảnh đại diện kênh.';
      return updated;
    } on AppError catch (e) {
      errorMessage = e.message;
      return null;
    } catch (_) {
      errorMessage = 'Tải ảnh đại diện thất bại.';
      return null;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<ChannelDetail?> uploadBanner(String channelId, XFile file) async {
    submitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      final updated = await service.uploadBanner(channelId, file);
      if (myChannel?.id == channelId) myChannel = updated;
      if (viewingChannel?.id == channelId) viewingChannel = updated;
      successMessage = 'Đã cập nhật ảnh bìa kênh.';
      return updated;
    } on AppError catch (e) {
      errorMessage = e.message;
      return null;
    } catch (_) {
      errorMessage = 'Tải ảnh bìa thất bại.';
      return null;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<bool> deleteChannel(String id) async {
    submitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      await service.deleteChannel(id);
      if (myChannel?.id == id) myChannel = null;
      if (viewingChannel?.id == id) viewingChannel = null;
      successMessage = 'Đã xóa kênh thành công.';
      return true;
    } on AppError catch (e) {
      errorMessage = e.message;
      return false;
    } catch (_) {
      errorMessage = 'Xóa kênh thất bại.';
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<void> loadRoles() async {
    try {
      roles = await service.getRoles();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadMembers(String channelId) async {
    loadingMembers = true;
    notifyListeners();
    try {
      members = await service.getMembers(channelId);
    } catch (_) {} finally {
      loadingMembers = false;
      notifyListeners();
    }
  }

  Future<void> loadInvitations(String channelId) async {
    loadingInvitations = true;
    notifyListeners();
    try {
      pendingInvitations = await service.getPendingInvitations(channelId);
    } catch (_) {} finally {
      loadingInvitations = false;
      notifyListeners();
    }
  }

  Future<void> loadMyInvitations() async {
    loadingInvitations = true;
    notifyListeners();
    try {
      myInvitations = await service.getMyInvitations();
    } catch (_) {} finally {
      loadingInvitations = false;
      notifyListeners();
    }
  }
}
