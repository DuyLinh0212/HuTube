import '../../../auth.dart';
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
