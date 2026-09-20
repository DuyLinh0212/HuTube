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
    this.inAppEnabled = true,
    this.emailEnabled = true,
    this.newVideoEnabled = true,
    this.commentReplyEnabled = true,
    this.reportResultEnabled = true,
    this.moderationEnabled = true,
    this.planEnabled = true,
    this.recommendationEnabled = true,
    this.mentionEnabled = true,
    this.channelActivityEnabled = true,
    this.paymentEnabled = true,
  });

  final bool inAppEnabled;
  final bool emailEnabled;
  final bool newVideoEnabled;
  final bool commentReplyEnabled;
  final bool reportResultEnabled;
  final bool moderationEnabled;
  final bool planEnabled;
  final bool recommendationEnabled;
  final bool mentionEnabled;
  final bool channelActivityEnabled;
  final bool paymentEnabled;

  // Compatibility getters keep the existing settings screen readable while
  // the wire format now matches the backend contract exactly.
  bool get notifyNewVideos => newVideoEnabled;
  bool get notifyComments => commentReplyEnabled;
  bool get notifySubscriptions => channelActivityEnabled;
  bool get notifyMarketing => emailEnabled;

  factory NotificationSettingModel.fromJson(Map<String, dynamic> json) {
    return NotificationSettingModel(
      inAppEnabled: json['inAppEnabled'] as bool? ?? true,
      emailEnabled: json['emailEnabled'] as bool? ?? json['notifyMarketing'] as bool? ?? false,
      newVideoEnabled: json['newVideoEnabled'] as bool? ?? json['notifyNewVideos'] as bool? ?? true,
      commentReplyEnabled: json['commentReplyEnabled'] as bool? ?? json['notifyComments'] as bool? ?? true,
      reportResultEnabled: json['reportResultEnabled'] as bool? ?? true,
      moderationEnabled: json['moderationEnabled'] as bool? ?? true,
      planEnabled: json['planEnabled'] as bool? ?? true,
      recommendationEnabled: json['recommendationEnabled'] as bool? ?? true,
      mentionEnabled: json['mentionEnabled'] as bool? ?? true,
      channelActivityEnabled: json['channelActivityEnabled'] as bool? ?? json['notifySubscriptions'] as bool? ?? true,
      paymentEnabled: json['paymentEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'inAppEnabled': inAppEnabled,
    'emailEnabled': emailEnabled,
    'newVideoEnabled': newVideoEnabled,
    'commentReplyEnabled': commentReplyEnabled,
    'reportResultEnabled': reportResultEnabled,
    'moderationEnabled': moderationEnabled,
    'planEnabled': planEnabled,
    'recommendationEnabled': recommendationEnabled,
    'mentionEnabled': mentionEnabled,
    'channelActivityEnabled': channelActivityEnabled,
    'paymentEnabled': paymentEnabled,
  };

  NotificationSettingModel copyWith({
    bool? inAppEnabled,
    bool? emailEnabled,
    bool? newVideoEnabled,
    bool? commentReplyEnabled,
    bool? reportResultEnabled,
    bool? moderationEnabled,
    bool? planEnabled,
    bool? recommendationEnabled,
    bool? mentionEnabled,
    bool? channelActivityEnabled,
    bool? paymentEnabled,
    bool? notifyNewVideos,
    bool? notifyComments,
    bool? notifySubscriptions,
    bool? notifyMarketing,
  }) {
    return NotificationSettingModel(
      inAppEnabled: inAppEnabled ?? this.inAppEnabled,
      emailEnabled: emailEnabled ?? notifyMarketing ?? this.emailEnabled,
      newVideoEnabled: newVideoEnabled ?? notifyNewVideos ?? this.newVideoEnabled,
      commentReplyEnabled: commentReplyEnabled ?? notifyComments ?? this.commentReplyEnabled,
      reportResultEnabled: reportResultEnabled ?? this.reportResultEnabled,
      moderationEnabled: moderationEnabled ?? this.moderationEnabled,
      planEnabled: planEnabled ?? this.planEnabled,
      recommendationEnabled: recommendationEnabled ?? this.recommendationEnabled,
      mentionEnabled: mentionEnabled ?? this.mentionEnabled,
      channelActivityEnabled: channelActivityEnabled ?? notifySubscriptions ?? this.channelActivityEnabled,
      paymentEnabled: paymentEnabled ?? this.paymentEnabled,
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
      defaultPlaybackQuality:
          json['defaultPlaybackQuality'] as String? ?? 'auto',
      autoplayNext: json['autoplayNext'] as bool? ?? true,
      keepSubscriptionsPrivate:
          json['keepSubscriptionsPrivate'] as bool? ?? false,
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
      defaultPlaybackQuality:
          defaultPlaybackQuality ?? this.defaultPlaybackQuality,
      autoplayNext: autoplayNext ?? this.autoplayNext,
      keepSubscriptionsPrivate:
          keepSubscriptionsPrivate ?? this.keepSubscriptionsPrivate,
      keepPlaylistsPrivate: keepPlaylistsPrivate ?? this.keepPlaylistsPrivate,
    );
  }
}
