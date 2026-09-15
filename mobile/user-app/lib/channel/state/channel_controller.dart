import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/errors/app_error.dart';
import '../../core/localization/app_strings.dart';
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
      errorMessage = _error(e, 'channel.notFound');
    } catch (_) {
      errorMessage = AppStrings.t('channel.notFound');
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
      errorMessage = _error(e, 'channel.notFound');
    } catch (_) {
      errorMessage = AppStrings.t('channel.notFound');
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
      successMessage = AppStrings.t('channel.created');
      return channel;
    } on AppError catch (e) {
      errorMessage = _error(e, 'channel.createError');
      return null;
    } catch (_) {
      errorMessage = AppStrings.t('channel.createError');
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
      successMessage = AppStrings.t('channel.updateSuccess');
      return updated;
    } on AppError catch (e) {
      errorMessage = _error(e, 'channel.updateError');
      return null;
    } catch (_) {
      errorMessage = AppStrings.t('channel.updateError');
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
      successMessage = AppStrings.t('channel.avatarUpdated');
      return updated;
    } on AppError catch (e) {
      errorMessage = _error(e, 'channel.imageError');
      return null;
    } catch (_) {
      errorMessage = AppStrings.t('channel.imageError');
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
      successMessage = AppStrings.t('channel.bannerUpdated');
      return updated;
    } on AppError catch (e) {
      errorMessage = _error(e, 'channel.imageError');
      return null;
    } catch (_) {
      errorMessage = AppStrings.t('channel.imageError');
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
      successMessage = AppStrings.t('channel.deleteSuccess');
      return true;
    } on AppError catch (e) {
      errorMessage = _error(e, 'channel.deleteError');
      return false;
    } catch (_) {
      errorMessage = AppStrings.t('channel.deleteError');
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
    } catch (_) {
    } finally {
      loadingMembers = false;
      notifyListeners();
    }
  }

  Future<void> loadInvitations(String channelId) async {
    loadingInvitations = true;
    notifyListeners();
    try {
      pendingInvitations = await service.getPendingInvitations(channelId);
    } catch (_) {
    } finally {
      loadingInvitations = false;
      notifyListeners();
    }
  }

  Future<void> loadMyInvitations() async {
    loadingInvitations = true;
    notifyListeners();
    try {
      myInvitations = await service.getMyInvitations();
    } catch (_) {
    } finally {
      loadingInvitations = false;
      notifyListeners();
    }
  }

  String _error(AppError error, String fallback) {
    return AppStrings.apiError(error, fallback: fallback);
  }
}
