import '../../../auth.dart';
import 'package:image_picker/image_picker.dart';
import '../models/channel_models.dart';

class ChannelService {
  ChannelService(this.auth);
  final AuthController auth;

  Future<ChannelDetail?> getMyChannel() async {
    try {
      final res = await auth.protected('GET', '/channels/me');
      return ChannelDetail.fromJson(res);
    } on ApiFailure catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<ChannelDetail> getChannel(String handleOrId) async {
    final clean = handleOrId.startsWith('@')
        ? handleOrId.substring(1)
        : handleOrId;
    final res = await auth.protected(
      'GET',
      '/channels/handle/${Uri.encodeComponent(clean)}',
    );
    return ChannelDetail.fromJson(res);
  }

  Future<bool> checkHandle(String handle) async {
    final clean = handle.startsWith('@') ? handle.substring(1) : handle;
    try {
      final res = await auth.api.request(
        'GET',
        '/channels/check-handle?handle=${Uri.encodeQueryComponent(clean)}',
      );
      return res['isAvailable'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<ChannelDetail> createChannel({
    required String name,
    required String handle,
    String? description,
  }) async {
    final clean = handle.startsWith('@') ? handle.substring(1) : handle;
    final res = await auth.protected(
      'POST',
      '/channels',
      body: {
        'name': name.trim(),
        'handle': clean.trim(),
        'description': description?.trim(),
      },
    );
    return ChannelDetail.fromJson(res);
  }

  Future<ChannelDetail> updateChannel(
    String id, {
    required String name,
    String? description,
  }) async {
    final res = await auth.protected(
      'PATCH',
      '/channels/${Uri.encodeComponent(id)}',
      body: {'name': name.trim(), 'description': description?.trim()},
    );
    return ChannelDetail.fromJson(res);
  }

  Future<ChannelDetail> uploadAvatar(String channelId, XFile file) =>
      _uploadImage(channelId, file, avatar: true);

  Future<ChannelDetail> uploadBanner(String channelId, XFile file) =>
      _uploadImage(channelId, file, avatar: false);

  Future<ChannelDetail> _uploadImage(
    String channelId,
    XFile file, {
    required bool avatar,
  }) async {
    final contentType = file.mimeType ?? _contentTypeFromName(file.name);
    if (!_allowedImageTypes.contains(contentType) ||
        (!avatar && contentType == 'image/gif')) {
      throw ApiFailure(
        400,
        'INVALID_FILE_TYPE',
        avatar
            ? 'Ảnh đại diện chỉ hỗ trợ JPG, PNG, WEBP hoặc GIF.'
            : 'Ảnh bìa chỉ hỗ trợ JPG, PNG hoặc WEBP.',
      );
    }
    final bytes = await file.readAsBytes();
    final maximumBytes = avatar ? 5 * 1024 * 1024 : 10 * 1024 * 1024;
    if (bytes.length > maximumBytes) {
      throw ApiFailure(
        400,
        'FILE_TOO_LARGE',
        'Kích thước ảnh tối đa là ${maximumBytes ~/ 1024 ~/ 1024}MB.',
      );
    }
    final response = await auth.protectedUpload(
      '/channels/${Uri.encodeComponent(channelId)}/${avatar ? 'avatar' : 'banner'}',
      UploadPayload(
        bytes: bytes,
        fileName: file.name.trim().isEmpty
            ? (avatar ? 'channel-avatar.jpg' : 'channel-banner.jpg')
            : file.name,
        contentType: contentType,
      ),
    );
    return ChannelDetail.fromJson(response);
  }

  static const _allowedImageTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
  };

  static String _contentTypeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'application/octet-stream';
  }

  Future<void> deleteChannel(String id) async {
    await auth.protected('DELETE', '/channels/${Uri.encodeComponent(id)}');
  }

  Future<List<ChannelRole>> getRoles() async {
    final items = await auth.protectedList('/channels/roles');
    return items
        .whereType<Map<String, dynamic>>()
        .map(ChannelRole.fromJson)
        .toList();
  }

  Future<List<ChannelMember>> getMembers(String channelId) async {
    final items = await auth.protectedList('/channels/$channelId/members');
    return items
        .whereType<Map<String, dynamic>>()
        .map(ChannelMember.fromJson)
        .toList();
  }

  Future<List<ChannelInvitation>> getPendingInvitations(
    String channelId,
  ) async {
    final items = await auth.protectedList('/channels/$channelId/invitations');
    return items
        .whereType<Map<String, dynamic>>()
        .map(ChannelInvitation.fromJson)
        .toList();
  }

  Future<List<ChannelInvitation>> getMyInvitations() async {
    final items = await auth.protectedList('/channels/invitations/me');
    return items
        .whereType<Map<String, dynamic>>()
        .map(ChannelInvitation.fromJson)
        .toList();
  }

  Future<void> inviteMember(
    String channelId,
    String email,
    String roleCode,
  ) async {
    await auth.protected(
      'POST',
      '/channels/$channelId/members/invite',
      body: {'email': email.trim(), 'roleCode': roleCode},
    );
  }

  Future<void> acceptInvitation(String invitationId) async {
    await auth.protected('POST', '/channels/invitations/$invitationId/accept');
  }

  Future<void> declineInvitation(String invitationId) async {
    await auth.protected('POST', '/channels/invitations/$invitationId/decline');
  }

  Future<void> revokeInvitation(String channelId, String invitationId) async {
    await auth.protected(
      'DELETE',
      '/channels/$channelId/invitations/$invitationId',
    );
  }

  Future<void> changeMemberRole(
    String channelId,
    String userId,
    String roleCode,
  ) async {
    await auth.protected(
      'PATCH',
      '/channels/$channelId/members/$userId/role',
      body: {'roleCode': roleCode},
    );
  }

  Future<void> removeMember(String channelId, String userId) async {
    await auth.protected('DELETE', '/channels/$channelId/members/$userId');
  }
}
