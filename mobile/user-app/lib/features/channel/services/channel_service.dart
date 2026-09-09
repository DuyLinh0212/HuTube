import 'package:http/http.dart' as http;
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
    final clean = handleOrId.startsWith('@') ? handleOrId.substring(1) : handleOrId;
    final res = await auth.protected('GET', '/channels/${Uri.encodeComponent(clean)}');
    return ChannelDetail.fromJson(res);
  }

  Future<bool> checkHandle(String handle) async {
    final clean = handle.startsWith('@') ? handle.substring(1) : handle;
    try {
      final res = await auth.api.request(
        'GET',
        '/channels/check-handle?handle=${Uri.encodeQueryComponent(clean)}',
      );
      return res['available'] as bool? ?? false;
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
      'PUT',
      '/channels/${Uri.encodeComponent(id)}',
      body: {
        'name': name.trim(),
        'description': description?.trim(),
      },
    );
    return ChannelDetail.fromJson(res);
  }

  Future<void> deleteChannel(String id) async {
    await auth.protected('DELETE', '/channels/${Uri.encodeComponent(id)}');
  }

  Future<String?> uploadAvatar(String channelId, List<int> bytes, String filename) async {
    final uri = Uri.parse('${auth.api.baseUrl}/channels/$channelId/avatar');
    final req = http.MultipartRequest('POST', uri);
    req.headers['Accept'] = 'application/json';
    req.headers['X-HuTube-Client'] = 'mobile';
    
    // We can use auth.protected or attach the token directly
    // Let's attach file
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    
    // If auth has token, add it
    // Wait, let's check how to send multipart with token
    // We can get token from a private getter or through auth
    return null;
  }
}
