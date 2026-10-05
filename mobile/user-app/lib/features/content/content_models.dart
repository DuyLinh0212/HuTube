/// Consume the server's bounded pages without silently truncating a collection.
Future<PageResult<T>> loadAllPages<T>(
  Future<PageResult<T>> Function(int) fetch,
) async {
  final items = <T>[];
  var number = 1;
  while (true) {
    final page = await fetch(number);
    items.addAll(page.items);
    if (!page.hasMore || page.items.isEmpty) break;
    number = page.page + 1;
  }
  return PageResult(
    items: items,
    page: 1,
    pageSize: items.isEmpty ? 1 : items.length,
    total: items.length,
  );
}

class PageResult<T> {
  const PageResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final int total;

  bool get hasMore => page * pageSize < total;
}

int asInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

class Category {
  const Category({required this.id, required this.name, required this.slug});

  final String id;
  final String name;
  final String slug;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: '${json['categoryId'] ?? ''}',
    name: '${json['name'] ?? ''}',
    slug: '${json['slug'] ?? ''}',
  );
}

class CategoryRankingGroup {
  const CategoryRankingGroup({
    required this.id,
    required this.name,
    required this.slug,
    required this.videos,
  });

  final String id;
  final String name;
  final String slug;
  final List<VideoCard> videos;

  factory CategoryRankingGroup.fromJson(Map<String, dynamic> json) =>
      CategoryRankingGroup(
        id: '${json['categoryId'] ?? ''}',
        name: '${json['categoryName'] ?? ''}',
        slug: '${json['slug'] ?? ''}',
        videos: (json['videos'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (value) => VideoCard.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList(),
      );
}

class FeaturedCreator {
  const FeaturedCreator({
    required this.id,
    required this.name,
    required this.handle,
    required this.avatarUrl,
    required this.subscriberCount,
    required this.verified,
  });

  final String id;
  final String name;
  final String handle;
  final String? avatarUrl;
  final int subscriberCount;
  final bool verified;

  factory FeaturedCreator.fromJson(Map<String, dynamic> json) =>
      FeaturedCreator(
        id: '${json['channelId'] ?? ''}',
        name: '${json['name'] ?? ''}',
        handle: '${json['handle'] ?? ''}',
        avatarUrl: json['avatarUrl'] as String?,
        subscriberCount: asInt(json['subscriberCount']),
        verified: json['verified'] == true,
      );
}

class ExploreHub {
  const ExploreHub({
    required this.rankings,
    required this.creators,
    required this.trending,
    required this.topVideos,
  });

  final List<CategoryRankingGroup> rankings;
  final List<FeaturedCreator> creators;
  final List<VideoCard> trending;
  final List<VideoCard> topVideos;

  factory ExploreHub.fromJson(Map<String, dynamic> json) => ExploreHub(
    rankings: (json['rankings'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              CategoryRankingGroup.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList(),
    creators: (json['creators'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => FeaturedCreator.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList(),
    trending: (json['trending'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => VideoCard.fromJson(Map<String, dynamic>.from(value)))
        .toList(),
    topVideos: (json['topVideos'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => VideoCard.fromJson(Map<String, dynamic>.from(value)))
        .toList(),
  );
}

class VideoCard {
  const VideoCard({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.channelHandle,
    required this.title,
    required this.thumbnailUrl,
    required this.duration,
    required this.visibility,
    required this.publishedAt,
    required this.views,
    this.isPromoted = false,
  });

  final String id;
  final String channelId;
  final String channelName;
  final String channelHandle;
  final String title;
  final String? thumbnailUrl;
  final int duration;
  final String visibility;
  final DateTime? publishedAt;
  final int views;
  final bool isPromoted;

  factory VideoCard.fromJson(Map<String, dynamic> json) => VideoCard(
    id: '${json['videoId'] ?? ''}',
    channelId: '${json['channelId'] ?? ''}',
    channelName: '${json['channelName'] ?? ''}',
    channelHandle: '${json['channelHandle'] ?? ''}',
    title: '${json['title'] ?? ''}',
    thumbnailUrl: json['thumbnailUrl'] as String?,
    duration: asInt(json['duration']),
    visibility: '${json['visibility'] ?? ''}',
    publishedAt: DateTime.tryParse('${json['publishedAt'] ?? ''}'),
    views: asInt(json['views']),
    isPromoted: json['isPromoted'] == true,
  );
}

class VideoStats {
  const VideoStats({
    required this.views,
    required this.likes,
    required this.dislikes,
    required this.comments,
    required this.averageRating,
    required this.ratingCount,
    this.watchSeconds = 0,
  });

  final int views;
  final int likes;
  final int dislikes;
  final int comments;
  final double? averageRating;
  final int ratingCount;
  final int watchSeconds;

  factory VideoStats.fromJson(Map<String, dynamic> json) => VideoStats(
    views: asInt(json['views']),
    likes: asInt(json['likes']),
    dislikes: asInt(json['dislikes']),
    comments: asInt(json['comments']),
    averageRating: (json['averageRating'] as num?)?.toDouble(),
    ratingCount: asInt(json['ratingCount']),
    watchSeconds: asInt(json['watchSeconds']),
  );
}

class VideoCardLink {
  const VideoCardLink({
    required this.videoId,
    required this.startSeconds,
    required this.title,
    this.thumbnailUrl,
  });

  final String videoId;
  final int startSeconds;
  final String title;
  final String? thumbnailUrl;

  factory VideoCardLink.fromJson(Map<String, dynamic> json) => VideoCardLink(
    videoId: '${json['videoId'] ?? ''}',
    startSeconds: asInt(json['startSeconds']),
    title: '${json['title'] ?? ''}',
    thumbnailUrl: json['thumbnailUrl'] as String?,
  );
}

class ViewerState {
  const ViewerState({this.reaction, this.rating, this.resumeAt = 0});
  final String? reaction;
  final int? rating;
  final int resumeAt;

  factory ViewerState.fromJson(Map<String, dynamic>? json) => ViewerState(
    reaction: json?['reaction'] as String?,
    rating: json?['rating'] as int?,
    resumeAt: asInt(json?['resumeAtSeconds']),
  );
}

class VideoChapter {
  const VideoChapter({required this.startSeconds, required this.title});
  final int startSeconds;
  final String title;

  factory VideoChapter.fromJson(Map<String, dynamic> json) => VideoChapter(
    startSeconds: asInt(json['startSeconds']),
    title: '${json['title'] ?? ''}',
  );
}

class VideoDetail extends VideoCard {
  const VideoDetail({
    required super.id,
    required super.channelId,
    required super.channelName,
    required super.channelHandle,
    required super.title,
    required super.thumbnailUrl,
    required super.duration,
    required super.visibility,
    required super.publishedAt,
    required super.views,
    required this.description,
    required this.videoUrl,
    required this.tags,
    required this.chapters,
    required this.stats,
    required this.viewerState,
    required this.moderationStatus,
    this.processingStatus = '',
    this.categoryId,
    this.promotionEnabled = false,
    this.videoCards = const [],
  });

  final String? description;
  final String videoUrl;
  final List<String> tags;
  final List<VideoChapter> chapters;
  final VideoStats stats;
  final ViewerState viewerState;
  final String moderationStatus;
  final String processingStatus;
  final String? categoryId;
  final bool promotionEnabled;
  final List<VideoCardLink> videoCards;

  factory VideoDetail.fromJson(Map<String, dynamic> json) => VideoDetail(
    id: '${json['videoId'] ?? ''}',
    channelId: '${json['channelId'] ?? ''}',
    channelName: '${json['channelName'] ?? ''}',
    channelHandle: '${json['channelHandle'] ?? ''}',
    title: '${json['title'] ?? ''}',
    categoryId: json['categoryId'] as String?,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    duration: asInt(json['duration']),
    visibility: '${json['visibility'] ?? ''}',
    publishedAt: DateTime.tryParse('${json['publishedAt'] ?? ''}'),
    views: asInt((json['stats'] as Map?)?['views']),
    description: json['description'] as String?,
    videoUrl: '${json['videoUrl'] ?? ''}',
    tags: (json['tags'] as List? ?? const []).map((value) => '$value').toList(),
    chapters: (json['chapters'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => VideoChapter.fromJson(Map<String, dynamic>.from(value)))
        .toList(),
    stats: VideoStats.fromJson(
      Map<String, dynamic>.from(json['stats'] as Map? ?? const {}),
    ),
    viewerState: ViewerState.fromJson(
      json['viewerState'] is Map
          ? Map<String, dynamic>.from(json['viewerState'] as Map)
          : null,
    ),
    moderationStatus: '${json['moderationStatus'] ?? ''}',
    processingStatus: '${json['status'] ?? ''}',
    promotionEnabled: json['promotionEnabled'] == true,
    videoCards: (json['videoCards'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => VideoCardLink.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList(),
  );
}

class Rendition {
  const Rendition({
    required this.quality,
    required this.width,
    required this.height,
    required this.fileSize,
    required this.url,
  });
  final String quality;
  final int width;
  final int height;
  final int fileSize;
  final String url;

  factory Rendition.fromJson(Map<String, dynamic> json) => Rendition(
    quality: '${json['quality'] ?? ''}',
    width: asInt(json['width']),
    height: asInt(json['height']),
    fileSize: asInt(json['fileSize']),
    url: '${json['url'] ?? ''}',
  );
}

class Playback {
  const Playback({required this.renditions, required this.resumeAt});
  final List<Rendition> renditions;
  final int resumeAt;

  factory Playback.fromJson(Map<String, dynamic> json) => Playback(
    renditions: (json['renditions'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => Rendition.fromJson(Map<String, dynamic>.from(value)))
        .toList(),
    resumeAt: asInt(json['resumeAtSeconds']),
  );
}

class CommentItem {
  const CommentItem({
    required this.id,
    required this.videoId,
    required this.displayName,
    required this.content,
    required this.createdAt,
    required this.likes,
    required this.dislikes,
    required this.myReaction,
    required this.replyCount,
    this.userId,
    this.status,
    this.videoTitle,
    this.isPinned = false,
    this.hasCreatorHeart = false,
  });

  final String id;
  final String videoId;
  final String displayName;
  final String content;
  final DateTime? createdAt;
  final int likes;
  final int dislikes;
  final String? myReaction;
  final int replyCount;
  final String? userId;
  final String? status;
  final String? videoTitle;
  final bool isPinned;
  final bool hasCreatorHeart;

  CommentItem copyWith({
    String? id,
    String? videoId,
    String? displayName,
    String? content,
    DateTime? createdAt,
    int? likes,
    int? dislikes,
    String? myReaction,
    int? replyCount,
    String? userId,
    String? status,
    String? videoTitle,
    bool? isPinned,
    bool? hasCreatorHeart,
  }) {
    return CommentItem(
      id: id ?? this.id,
      videoId: videoId ?? this.videoId,
      displayName: displayName ?? this.displayName,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      likes: likes ?? this.likes,
      dislikes: dislikes ?? this.dislikes,
      myReaction: myReaction ?? this.myReaction,
      replyCount: replyCount ?? this.replyCount,
      userId: userId ?? this.userId,
      status: status ?? this.status,
      videoTitle: videoTitle ?? this.videoTitle,
      isPinned: isPinned ?? this.isPinned,
      hasCreatorHeart: hasCreatorHeart ?? this.hasCreatorHeart,
    );
  }

  factory CommentItem.fromJson(Map<String, dynamic> json) => CommentItem(
    id: '${json['commentId'] ?? ''}',
    videoId: '${json['videoId'] ?? ''}',
    displayName: '${json['displayName'] ?? ''}',
    content: '${json['content'] ?? ''}',
    createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
    likes: asInt(json['likes']),
    dislikes: asInt(json['dislikes']),
    myReaction: json['myReaction'] as String?,
    replyCount: asInt(json['replyCount']),
    userId: json['userId'] as String?,
    status: json['status'] as String?,
    videoTitle: json['videoTitle'] as String?,
    isPinned: json['isPinned'] == true,
    hasCreatorHeart: json['hasCreatorHeart'] == true,
  );
}

class LibraryVideo extends VideoCard {
  const LibraryVideo({
    required super.id,
    required super.channelId,
    required super.channelName,
    required super.channelHandle,
    required super.title,
    required super.thumbnailUrl,
    required super.duration,
    required super.visibility,
    required super.publishedAt,
    required super.views,
    required this.progress,
    required this.myRating,
    this.activityAt,
  });

  final double progress;
  final int? myRating;
  final DateTime? activityAt;

  factory LibraryVideo.fromJson(Map<String, dynamic> json) => LibraryVideo(
    id: '${json['videoId'] ?? ''}',
    channelId: '${json['channelId'] ?? ''}',
    channelName: '${json['channelName'] ?? ''}',
    channelHandle: '${json['channelHandle'] ?? ''}',
    title: '${json['title'] ?? ''}',
    thumbnailUrl: json['thumbnailUrl'] as String?,
    duration: asInt(json['duration']),
    visibility: '${json['visibility'] ?? ''}',
    publishedAt: DateTime.tryParse('${json['publishedAt'] ?? ''}'),
    views: asInt(json['views']),
    progress: (json['progress'] as num?)?.toDouble() ?? 0,
    myRating: json['myRating'] as int?,
    activityAt: DateTime.tryParse('${json['activityAt'] ?? ''}'),
  );
}
