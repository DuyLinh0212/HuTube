import '../../auth.dart';
import 'content_models.dart';

class ContentService {
  ContentService(this.auth);
  final AuthController auth;

  String _query(String path, Map<String, Object?> values) {
    final pairs = values.entries
        .where((entry) => entry.value != null && '${entry.value}'.isNotEmpty)
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent('${entry.value}')}',
        )
        .join('&');
    return pairs.isEmpty ? path : '$path?$pairs';
  }

  Future<PageResult<VideoCard>> feed({
    required bool explore,
    int page = 1,
    int pageSize = 20,
    String? categoryId,
    String? tag,
    String sort = 'newest',
  }) async {
    final endpoint = _query(explore ? '/feed/explore' : '/feed/home', {
      'page': page,
      'pageSize': pageSize,
      'sort': sort,
      if (explore) 'categoryId': categoryId,
      if (explore) 'tag': tag,
    });
    final json = await auth.api.request('GET', endpoint);
    return PageResult(
      items: (json['items'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => VideoCard.fromJson(Map<String, dynamic>.from(value)))
          .toList(),
      page: asInt(json['page']) == 0 ? page : asInt(json['page']),
      pageSize: asInt(json['pageSize']) == 0
          ? pageSize
          : asInt(json['pageSize']),
      total: asInt(json['total']),
    );
  }

  Future<List<Category>> categories() async {
    final json = await auth.api.requestList('GET', '/categories');
    return json
        .whereType<Map>()
        .map((value) => Category.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }

  Future<VideoDetail> detail(String videoId) async {
    final json = auth.authenticated
        ? await auth.protected('GET', '/videos/${Uri.encodeComponent(videoId)}')
        : await auth.api.request(
            'GET',
            '/videos/${Uri.encodeComponent(videoId)}',
          );
    return VideoDetail.fromJson(json);
  }

  Future<Playback> playback(String videoId) async {
    final json = auth.authenticated
        ? await auth.protected(
            'GET',
            '/videos/${Uri.encodeComponent(videoId)}/playback',
          )
        : await auth.api.request(
            'GET',
            '/videos/${Uri.encodeComponent(videoId)}/playback',
          );
    return Playback.fromJson(json);
  }

  Future<PageResult<CommentItem>> comments(
    String videoId, {
    int page = 1,
  }) async {
    final endpoint =
        '/videos/${Uri.encodeComponent(videoId)}/comments?page=$page&pageSize=20';
    final json = auth.authenticated
        ? await auth.protected('GET', endpoint)
        : await auth.api.request('GET', endpoint);
    return PageResult(
      items: (json['items'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) => CommentItem.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
      page: asInt(json['page']) == 0 ? page : asInt(json['page']),
      pageSize: asInt(json['pageSize']) == 0 ? 20 : asInt(json['pageSize']),
      total: asInt(json['total']),
    );
  }

  Future<PageResult<CommentItem>> replies(String commentId) async {
    final endpoint =
        '/comments/${Uri.encodeComponent(commentId)}/replies?page=1&pageSize=50';
    final json = auth.authenticated
        ? await auth.protected('GET', endpoint)
        : await auth.api.request('GET', endpoint);
    return PageResult(
      items: (json['items'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) => CommentItem.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
      page: asInt(json['page']) == 0 ? 1 : asInt(json['page']),
      pageSize: asInt(json['pageSize']) == 0 ? 50 : asInt(json['pageSize']),
      total: asInt(json['total']),
    );
  }

  Future<void> progress(String videoId, int watchedSeconds) async {
    await auth.protected(
      'PUT',
      '/videos/${Uri.encodeComponent(videoId)}/watch-progress',
      body: {'watchedSeconds': watchedSeconds, 'saveHistory': true},
    );
  }

  Future<Map<String, dynamic>> react(String videoId, String? type) =>
      type == null
      ? auth.protected(
          'DELETE',
          '/videos/${Uri.encodeComponent(videoId)}/reaction',
        )
      : auth.protected(
          'PUT',
          '/videos/${Uri.encodeComponent(videoId)}/reaction',
          body: {'type': type},
        );

  Future<Map<String, dynamic>> rate(String videoId, int? score) => score == null
      ? auth.protected(
          'DELETE',
          '/videos/${Uri.encodeComponent(videoId)}/rating',
        )
      : auth.protected(
          'PUT',
          '/videos/${Uri.encodeComponent(videoId)}/rating',
          body: {'score': score},
        );

  Future<void> share(String videoId) async {
    await auth.protected(
      'POST',
      '/videos/${Uri.encodeComponent(videoId)}/share',
      body: {'method': 'mobile'},
    );
  }

  Future<CommentItem> createComment(
    String videoId,
    String content, {
    String? parentCommentId,
  }) async {
    final json = await auth.protected(
      'POST',
      '/videos/${Uri.encodeComponent(videoId)}/comments',
      body: {'content': content, 'parentCommentId': parentCommentId},
    );
    return CommentItem.fromJson(json);
  }

  Future<Map<String, dynamic>> reactComment(String id, String? type) =>
      type == null
      ? auth.protected(
          'DELETE',
          '/comments/${Uri.encodeComponent(id)}/reaction',
        )
      : auth.protected(
          'PUT',
          '/comments/${Uri.encodeComponent(id)}/reaction',
          body: {'type': type},
        );

  Future<List<Rendition>> downloadOptions(String videoId) async {
    final items = await auth.protectedList(
      '/videos/${Uri.encodeComponent(videoId)}/download-options',
    );
    return items
        .whereType<Map>()
        .map((value) => Rendition.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }

  Future<Map<String, dynamic>> createDownload(String videoId, String quality) =>
      auth.protected(
        'POST',
        '/videos/${Uri.encodeComponent(videoId)}/downloads',
        body: {'quality': quality},
      );

  Future<PageResult<LibraryVideo>> history({int page = 1}) =>
      _library('history', page: page);
  Future<PageResult<LibraryVideo>> liked({int page = 1, int? rating}) =>
      _library('liked', page: page, rating: rating);

  Future<PageResult<LibraryVideo>> _library(
    String kind, {
    required int page,
    int? rating,
  }) async {
    final path = _query('/library/$kind', {
      'page': page,
      'pageSize': 20,
      'rating': rating,
    });
    final json = await auth.protected('GET', path);
    return PageResult(
      items: (json['items'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) => LibraryVideo.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
      page: asInt(json['page']) == 0 ? page : asInt(json['page']),
      pageSize: asInt(json['pageSize']) == 0 ? 20 : asInt(json['pageSize']),
      total: asInt(json['total']),
    );
  }
}
