import 'dart:async';

import '../../auth.dart';
import 'content_models.dart';

class ContentService {
  ContentService(this.auth, {ApiClient? recommendationApi})
    : recommendationApi =
          recommendationApi ??
          ApiClient(
            client: auth.api.client,
            baseUrl: AppConfig.standard.recommendationBaseUrl,
            requestTimeout: const Duration(seconds: 105),
            // An inference outage is not evidence that the content API or the
            // phone is offline. Probe the core API before showing that banner.
            healthUrl:
                '${auth.api.baseUrl.replaceAll(RegExp(r'/+$'), '')}/system/config',
          );
  final AuthController auth;
  final ApiClient recommendationApi;

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
    Duration? recommendationBudget,
  }) async {
    // Send the user's access token directly to FastAPI. Token refresh continues
    // through the content API's existing session controller.
    final useRecommendations = !explore && auth.authenticated;
    final endpoint = _query(
      explore
          ? '/feed/explore'
          : useRecommendations
          ? '/feed/recommended'
          : '/feed/home',
      {
        'page': page,
        'pageSize': pageSize,
        if (!useRecommendations) 'sort': sort,
        if (explore) 'categoryId': categoryId,
        if (explore) 'tag': tag,
      },
    );
    final generation = auth.sessionGeneration;
    Map<String, dynamic> json;
    if (useRecommendations) {
      try {
        final request = auth.protected(
          'GET',
          endpoint,
          apiClient: recommendationApi,
        );
        json = await (recommendationBudget == null
            ? request
            : request.timeout(recommendationBudget));
      } on TimeoutException {
        if (generation != auth.sessionGeneration) rethrow;
        // Watch suggestions must not hold up the screen during inference/cold
        // starts. Resolve the catalogue without invoking inference again.
        json = await auth.protected(
          'POST',
          '/feed/resolve',
          body: {'videoIds': <String>[], 'page': page, 'pageSize': pageSize},
        );
      } on ApiFailure catch (error) {
        if (generation != auth.sessionGeneration ||
            (error.status != 0 && error.status < 500)) {
          rethrow;
        }
        // Resolve an empty ranking to serve the catalogue without invoking CF again.
        json = await auth.protected(
          'POST',
          '/feed/resolve',
          body: {'videoIds': <String>[], 'page': page, 'pageSize': pageSize},
        );
      }
    } else {
      json = await auth.api.request('GET', endpoint);
    }
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

  Future<List<VideoCard>> relatedVideos(VideoDetail video) async {
    List<VideoCard> unique(Iterable<VideoCard> items) {
      final seen = <String>{video.id};
      return items.where((item) => seen.add(item.id)).take(10).toList();
    }

    final tag = video.tags.isEmpty ? null : video.tags.first;
    if (video.categoryId == null && tag == null) {
      return unique(
        (await feed(
          explore: false,
          pageSize: 20,
          recommendationBudget: const Duration(milliseconds: 1200),
        )).items,
      );
    }
    final tagged = unique(
      (await searchVideos(
        query: '',
        categoryId: video.categoryId,
        tag: tag,
        sort: 'popular',
        pageSize: 20,
      )).items,
    );
    if (tag == null || video.categoryId == null || tagged.length >= 10) {
      return tagged;
    }
    try {
      final category = await searchVideos(
        query: '',
        categoryId: video.categoryId,
        sort: 'popular',
        pageSize: 20,
      );
      return unique([...tagged, ...category.items]);
    } catch (_) {
      if (tagged.isEmpty) rethrow;
      return tagged;
    }
  }

  Future<PageResult<VideoCard>> searchVideos({
    required String query,
    String? categoryId,
    String? tag,
    String? channelId,
    String? dateRange,
    String? duration,
    int page = 1,
    int pageSize = 20,
    String sort = 'relevance',
  }) async {
    final endpoint = _query('/videos/search', {
      'q': query.trim(),
      'tag': tag,
      'categoryId': categoryId,
      'channelId': channelId,
      'dateRange': dateRange,
      'duration': duration,
      'sort': sort,
      'page': page,
      'pageSize': pageSize,
    });
    final json = await auth.api.request('GET', endpoint);
    return _videoPage(json, page, pageSize);
  }

  Future<ExploreHub> exploreHub() async {
    final json = await auth.api.request('GET', '/feed/explore-hub');
    return ExploreHub.fromJson(json);
  }

  Future<PageResult<VideoCard>> subscriptionsFeed({
    int page = 1,
    int pageSize = 20,
  }) async {
    final endpoint = _query('/feed/subscriptions', {
      'page': page,
      'pageSize': pageSize,
    });
    final json = await auth.protected('GET', endpoint);
    return _videoPage(json, page, pageSize);
  }

  PageResult<VideoCard> _videoPage(
    Map<String, dynamic> json,
    int requestedPage,
    int requestedPageSize,
  ) => PageResult(
    items: (json['items'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => VideoCard.fromJson(Map<String, dynamic>.from(value)))
        .toList(),
    page: asInt(json['page']) == 0 ? requestedPage : asInt(json['page']),
    pageSize: asInt(json['pageSize']) == 0
        ? requestedPageSize
        : asInt(json['pageSize']),
    total: asInt(json['total']),
  );

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
    String sort = 'newest',
  }) async {
    final endpoint = _query(
      '/videos/${Uri.encodeComponent(videoId)}/comments',
      {'page': page, 'pageSize': 20, 'sort': sort},
    );
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

  Future<PageResult<CommentItem>> replies(
    String commentId, {
    int page = 1,
    int pageSize = 3,
  }) async {
    final endpoint =
        '/comments/${Uri.encodeComponent(commentId)}/replies?page=$page&pageSize=$pageSize';
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
      pageSize: asInt(json['pageSize']) == 0
          ? pageSize
          : asInt(json['pageSize']),
      total: asInt(json['total']),
    );
  }

  Future<void> progress(
    String videoId,
    int watchedSeconds, {
    bool saveHistory = true,
  }) async {
    await auth.protected(
      'PUT',
      '/videos/${Uri.encodeComponent(videoId)}/watch-progress',
      body: {'watchedSeconds': watchedSeconds, 'saveHistory': saveHistory},
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

  Future<CommentItem> updateComment(String id, String content) async =>
      CommentItem.fromJson(
        await auth.protected(
          'PATCH',
          '/comments/${Uri.encodeComponent(id)}',
          body: {'content': content.trim()},
        ),
      );

  Future<void> deleteComment(String id) async {
    await auth.protected('DELETE', '/comments/${Uri.encodeComponent(id)}');
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

  Future<CommentItem> setCommentCreatorState(
    String id, {
    required bool enabled,
    required bool pin,
  }) async => CommentItem.fromJson(
    await auth.protected(
      'PUT',
      '/comments/${Uri.encodeComponent(id)}/${pin ? 'pin' : 'creator-heart'}',
      body: {'enabled': enabled},
    ),
  );

  Future<CommentItem> setCommentVisibility(
    String id,
    bool hidden, {
    String? reason,
  }) async => CommentItem.fromJson(
    await auth.protected(
      'PUT',
      '/comments/${Uri.encodeComponent(id)}/visibility',
      // ignore: use_null_aware_elements
      body: {'hidden': hidden, if (reason != null) 'reason': reason},
    ),
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

  Future<List<Map<String, dynamic>>> downloads() async =>
      (await auth.protectedList('/downloads'))
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  Future<Map<String, dynamic>> updateDownload(
    String downloadId,
    String operation,
  ) => auth.protected(
    'POST',
    '/downloads/${Uri.encodeComponent(downloadId)}/$operation',
  );

  Future<void> deleteDownload(String downloadId) async {
    await auth.protected(
      'DELETE',
      '/downloads/${Uri.encodeComponent(downloadId)}',
    );
  }

  Future<void> deleteDownloads(List<String> downloadIds) async {
    await auth.protected('DELETE', '/downloads', body: {'ids': downloadIds});
  }

  Future<List<Map<String, dynamic>>> violationTypes() async =>
      (await auth.api.requestList('GET', '/violation-types'))
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  Future<Map<String, dynamic>> reportComment(
    String commentId,
    String violationTypeId,
    String description,
  ) => auth.protected(
    'POST',
    '/comments/${Uri.encodeComponent(commentId)}/report',
    body: {'violationTypeId': violationTypeId, 'description': description},
  );

  Future<PageResult<LibraryVideo>> history({
    int page = 1,
    String? query,
    String sort = 'newest',
    String dateRange = 'all',
  }) => _library(
    'history',
    page: page,
    fromHistory: true,
    query: query,
    sort: sort,
    dateRange: dateRange,
  );

  Future<PageResult<LibraryVideo>> liked({int page = 1, int? rating}) =>
      _library('liked', page: page, rating: rating);

  Future<PageResult<LibraryVideo>> _library(
    String kind, {
    required int page,
    int? rating,
    bool fromHistory = false,
    String? query,
    String? sort,
    String? dateRange,
  }) async {
    final path = _query('/library/$kind', {
      'page': page,
      'pageSize': 20,
      'rating': rating,
      'q': query,
      'sort': sort,
      'dateRange': dateRange,
    });
    final json = await auth.protected('GET', path);
    return PageResult(
      items: (json['items'] as List? ?? const []).whereType<Map>().map((value) {
        final row = Map<String, dynamic>.from(value);
        return fromHistory
            ? LibraryVideo.fromHistoryJson(row)
            : LibraryVideo.fromJson(row);
      }).toList(),
      page: asInt(json['page']) == 0 ? page : asInt(json['page']),
      pageSize: asInt(json['pageSize']) == 0 ? 20 : asInt(json['pageSize']),
      total: asInt(json['total']),
    );
  }
}
