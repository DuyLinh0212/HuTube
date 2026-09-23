import '../../auth.dart';

class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.visibility,
    required this.itemCount,
    this.description,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String visibility;
  final int itemCount;
  final String? description;
  final DateTime? updatedAt;

  factory PlaylistSummary.fromJson(Map<String, dynamic> json) =>
      PlaylistSummary(
        id: '${json['playlistId'] ?? ''}',
        name: '${json['name'] ?? ''}',
        visibility: '${json['visibility'] ?? 'private'}',
        itemCount: json['itemCount'] is num
            ? (json['itemCount'] as num).toInt()
            : 0,
        description: json['description'] as String?,
        updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
      );
}

class PlaylistItem {
  const PlaylistItem({
    required this.videoId,
    required this.title,
    required this.thumbnailUrl,
    required this.duration,
    required this.available,
  });

  final String videoId;
  final String? title;
  final String? thumbnailUrl;
  final int duration;
  final bool available;

  factory PlaylistItem.fromJson(Map<String, dynamic> json) => PlaylistItem(
    videoId: '${json['videoId'] ?? ''}',
    title: json['title'] as String?,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    duration: json['duration'] is num ? (json['duration'] as num).toInt() : 0,
    available: json['available'] == true,
  );
}

class PlaylistDetail {
  const PlaylistDetail({
    required this.id,
    required this.name,
    required this.visibility,
    required this.items,
    this.description,
  });

  final String id;
  final String name;
  final String visibility;
  final List<PlaylistItem> items;
  final String? description;

  factory PlaylistDetail.fromJson(Map<String, dynamic> json) => PlaylistDetail(
    id: '${json['playlistId'] ?? ''}',
    name: '${json['name'] ?? ''}',
    visibility: '${json['visibility'] ?? 'private'}',
    description: json['description'] as String?,
    items: (json['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => PlaylistItem.fromJson(Map<String, dynamic>.from(item)))
        .toList(),
  );
}

class PlaylistService {
  PlaylistService(this.auth);
  final AuthController auth;

  Future<List<PlaylistSummary>> mine() async =>
      (await auth.protectedList('/playlists'))
          .whereType<Map>()
          .map(
            (item) => PlaylistSummary.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();

  Future<List<PlaylistSummary>> publicByChannel(String channelId) async =>
      (await auth.api.requestList(
            'GET',
            '/playlists/channel/${Uri.encodeComponent(channelId)}',
          ))
          .whereType<Map>()
          .map(
            (item) => PlaylistSummary.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();

  Future<List<PlaylistSummary>> channelMine(String channelId) async =>
      (await auth.protectedList(
            '/playlists/channel/${Uri.encodeComponent(channelId)}/mine',
          ))
          .whereType<Map>()
          .map(
            (item) => PlaylistSummary.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();

  Future<PlaylistDetail> get(String id) async => PlaylistDetail.fromJson(
    auth.authenticated
        ? await auth.protected('GET', '/playlists/${Uri.encodeComponent(id)}')
        : await auth.api.request(
            'GET',
            '/playlists/${Uri.encodeComponent(id)}',
          ),
  );

  Future<PlaylistDetail> create({
    required String name,
    String? description,
    String visibility = 'private',
  }) async => PlaylistDetail.fromJson(
    await auth.protected(
      'POST',
      '/playlists',
      body: {
        'name': name.trim(),
        'description': description?.trim(),
        'visibility': visibility,
      },
    ),
  );

  Future<PlaylistDetail> update(
    String id, {
    required String name,
    String? description,
    required String visibility,
  }) async => PlaylistDetail.fromJson(
    await auth.protected(
      'PATCH',
      '/playlists/${Uri.encodeComponent(id)}',
      body: {
        'name': name.trim(),
        'description': description?.trim(),
        'visibility': visibility,
      },
    ),
  );

  Future<void> delete(String id) async {
    await auth.protected('DELETE', '/playlists/${Uri.encodeComponent(id)}');
  }

  Future<PlaylistDetail> saveVideo(String videoId) async =>
      PlaylistDetail.fromJson(
        await auth.protected(
          'POST',
          '/playlists/save',
          body: {'videoId': videoId},
        ),
      );

  Future<PlaylistDetail> addVideo(String playlistId, String videoId) async =>
      PlaylistDetail.fromJson(
        await auth.protected(
          'POST',
          '/playlists/${Uri.encodeComponent(playlistId)}/videos',
          body: {'videoId': videoId},
        ),
      );

  Future<void> removeVideo(String playlistId, String videoId) async {
    await auth.protected(
      'DELETE',
      '/playlists/${Uri.encodeComponent(playlistId)}/videos/${Uri.encodeComponent(videoId)}',
    );
  }

  Future<PlaylistDetail> reorder(
    String playlistId,
    List<String> videoIds,
  ) async => PlaylistDetail.fromJson(
    await auth.protected(
      'PUT',
      '/playlists/${Uri.encodeComponent(playlistId)}/order',
      body: {'videoIds': videoIds},
    ),
  );
}
