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
  });

  final int views;
  final int likes;
  final int dislikes;
  final int comments;
  final double? averageRating;
  final int ratingCount;

  factory VideoStats.fromJson(Map<String, dynamic> json) => VideoStats(
    views: asInt(json['views']),
    likes: asInt(json['likes']),
    dislikes: asInt(json['dislikes']),
    comments: asInt(json['comments']),
    averageRating: (json['averageRating'] as num?)?.toDouble(),
    ratingCount: asInt(json['ratingCount']),
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
  });

  final String? description;
  final String videoUrl;
  final List<String> tags;
  final List<VideoChapter> chapters;
  final VideoStats stats;
  final ViewerState viewerState;
  final String moderationStatus;
  final String processingStatus;

  factory VideoDetail.fromJson(Map<String, dynamic> json) => VideoDetail(
    id: '${json['videoId'] ?? ''}',
    channelId: '${json['channelId'] ?? ''}',
    channelName: '${json['channelName'] ?? ''}',
    channelHandle: '${json['channelHandle'] ?? ''}',
    title: '${json['title'] ?? ''}',
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
  });

  final double progress;
  final int? myRating;

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
  );
}
