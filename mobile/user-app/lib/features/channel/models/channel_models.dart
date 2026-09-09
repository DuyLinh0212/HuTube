class ChannelSummary {
  const ChannelSummary({
    required this.id,
    required this.name,
    required this.handle,
    this.avatarUrl,
    this.bannerUrl,
    required this.subscriberCount,
    required this.videoCount,
    this.isOwner = false,
  });

  final String id;
  final String name;
  final String handle;
  final String? avatarUrl;
  final String? bannerUrl;
  final int subscriberCount;
  final int videoCount;
  final bool isOwner;

  factory ChannelSummary.fromJson(Map<String, dynamic> json) {
    return ChannelSummary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      handle: json['handle'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      bannerUrl: json['bannerUrl'] as String?,
      subscriberCount: json['subscriberCount'] as int? ?? 0,
      videoCount: json['videoCount'] as int? ?? 0,
      isOwner: json['isOwner'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'handle': handle,
    'avatarUrl': avatarUrl,
    'bannerUrl': bannerUrl,
    'subscriberCount': subscriberCount,
    'videoCount': videoCount,
    'isOwner': isOwner,
  };
}

class ChannelDetail {
  const ChannelDetail({
    required this.id,
    required this.name,
    required this.handle,
    this.description,
    this.avatarUrl,
    this.bannerUrl,
    required this.subscriberCount,
    required this.videoCount,
    required this.viewCount,
    required this.isOwner,
    required this.isSubscribed,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String handle;
  final String? description;
  final String? avatarUrl;
  final String? bannerUrl;
  final int subscriberCount;
  final int videoCount;
  final int viewCount;
  final bool isOwner;
  final bool isSubscribed;
  final String createdAt;

  factory ChannelDetail.fromJson(Map<String, dynamic> json) {
    return ChannelDetail(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      handle: json['handle'] as String? ?? '',
      description: json['description'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      bannerUrl: json['bannerUrl'] as String?,
      subscriberCount: json['subscriberCount'] as int? ?? 0,
      videoCount: json['videoCount'] as int? ?? 0,
      viewCount: json['viewCount'] as int? ?? 0,
      isOwner: json['isOwner'] as bool? ?? false,
      isSubscribed: json['isSubscribed'] as bool? ?? false,
      createdAt: json['createdAt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'handle': handle,
    'description': description,
    'avatarUrl': avatarUrl,
    'bannerUrl': bannerUrl,
    'subscriberCount': subscriberCount,
    'videoCount': videoCount,
    'viewCount': viewCount,
    'isOwner': isOwner,
    'isSubscribed': isSubscribed,
    'createdAt': createdAt,
  };

  ChannelDetail copyWith({
    String? name,
    String? description,
    String? avatarUrl,
    String? bannerUrl,
    bool? isSubscribed,
    int? subscriberCount,
  }) {
    return ChannelDetail(
      id: id,
      name: name ?? this.name,
      handle: handle,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      subscriberCount: subscriberCount ?? this.subscriberCount,
      videoCount: videoCount,
      viewCount: viewCount,
      isOwner: isOwner,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      createdAt: createdAt,
    );
  }
}
