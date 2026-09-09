class UserProfile {
  const UserProfile({
    required this.userId,
    required this.username,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.country,
    required this.emailVerified,
    required this.createdAt,
  });

  final String userId;
  final String username;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final String? country;
  final bool emailVerified;
  final String createdAt;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['userId'] as String? ?? '',
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      bio: json['bio'] as String?,
      country: json['country'] as String?,
      emailVerified: json['emailVerified'] as bool? ?? false,
      createdAt: json['createdAt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'username': username,
    'email': email,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'bio': bio,
    'country': country,
    'emailVerified': emailVerified,
    'createdAt': createdAt,
  };

  UserProfile copyWith({
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? country,
  }) {
    return UserProfile(
      userId: userId,
      username: username,
      email: email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      country: country ?? this.country,
      emailVerified: emailVerified,
      createdAt: createdAt,
    );
  }
}

class NotificationSettingModel {
  const NotificationSettingModel({
    this.notifyNewVideos = true,
    this.notifyComments = true,
    this.notifySubscriptions = true,
    this.notifyMarketing = false,
  });

  final bool notifyNewVideos;
  final bool notifyComments;
  final bool notifySubscriptions;
  final bool notifyMarketing;

  factory NotificationSettingModel.fromJson(Map<String, dynamic> json) {
    return NotificationSettingModel(
      notifyNewVideos: json['notifyNewVideos'] as bool? ?? true,
      notifyComments: json['notifyComments'] as bool? ?? true,
      notifySubscriptions: json['notifySubscriptions'] as bool? ?? true,
      notifyMarketing: json['notifyMarketing'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'notifyNewVideos': notifyNewVideos,
    'notifyComments': notifyComments,
    'notifySubscriptions': notifySubscriptions,
    'notifyMarketing': notifyMarketing,
  };

  NotificationSettingModel copyWith({
    bool? notifyNewVideos,
    bool? notifyComments,
    bool? notifySubscriptions,
    bool? notifyMarketing,
  }) {
    return NotificationSettingModel(
      notifyNewVideos: notifyNewVideos ?? this.notifyNewVideos,
      notifyComments: notifyComments ?? this.notifyComments,
      notifySubscriptions: notifySubscriptions ?? this.notifySubscriptions,
      notifyMarketing: notifyMarketing ?? this.notifyMarketing,
    );
  }
}

class UserPreferencesModel {
  const UserPreferencesModel({
    this.theme = 'system',
    this.defaultPlaybackQuality = 'auto',
    this.autoplayNext = true,
    this.keepSubscriptionsPrivate = false,
    this.keepPlaylistsPrivate = true,
  });

  final String theme;
  final String defaultPlaybackQuality;
  final bool autoplayNext;
  final bool keepSubscriptionsPrivate;
  final bool keepPlaylistsPrivate;

  factory UserPreferencesModel.fromJson(Map<String, dynamic> json) {
    return UserPreferencesModel(
      theme: json['theme'] as String? ?? 'system',
      defaultPlaybackQuality: json['defaultPlaybackQuality'] as String? ?? 'auto',
      autoplayNext: json['autoplayNext'] as bool? ?? true,
      keepSubscriptionsPrivate: json['keepSubscriptionsPrivate'] as bool? ?? false,
      keepPlaylistsPrivate: json['keepPlaylistsPrivate'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'theme': theme,
    'defaultPlaybackQuality': defaultPlaybackQuality,
    'autoplayNext': autoplayNext,
    'keepSubscriptionsPrivate': keepSubscriptionsPrivate,
    'keepPlaylistsPrivate': keepPlaylistsPrivate,
  };

  UserPreferencesModel copyWith({
    String? theme,
    String? defaultPlaybackQuality,
    bool? autoplayNext,
    bool? keepSubscriptionsPrivate,
    bool? keepPlaylistsPrivate,
  }) {
    return UserPreferencesModel(
      theme: theme ?? this.theme,
      defaultPlaybackQuality: defaultPlaybackQuality ?? this.defaultPlaybackQuality,
      autoplayNext: autoplayNext ?? this.autoplayNext,
      keepSubscriptionsPrivate: keepSubscriptionsPrivate ?? this.keepSubscriptionsPrivate,
      keepPlaylistsPrivate: keepPlaylistsPrivate ?? this.keepPlaylistsPrivate,
    );
  }
}
