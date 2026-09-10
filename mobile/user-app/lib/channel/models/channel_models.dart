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
      id: json['channelId'] as String? ?? json['id'] as String? ?? '',
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
    this.myRole,
    this.permissions = const [],
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
  final String? myRole;
  final List<String> permissions;

  factory ChannelDetail.fromJson(Map<String, dynamic> json) {
    return ChannelDetail(
      id: json['channelId'] as String? ?? json['id'] as String? ?? '',
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
      myRole: json['myRole'] as String?,
      permissions: (json['permissions'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
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
    'myRole': myRole,
    'permissions': permissions,
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
      myRole: myRole,
      permissions: permissions,
    );
  }
}

class ChannelRole {
  const ChannelRole({
    required this.code,
    required this.name,
    required this.description,
  });
  final String code;
  final String name;
  final String description;

  factory ChannelRole.fromJson(Map<String, dynamic> json) => ChannelRole(
    code: json['code'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
  );
}

class ChannelMember {
  const ChannelMember({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.roleCode,
    this.avatarUrl,
  });
  final String userId;
  final String displayName;
  final String email;
  final String roleCode;
  final String? avatarUrl;

  factory ChannelMember.fromJson(Map<String, dynamic> json) => ChannelMember(
    userId: json['userId'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    email: json['email'] as String? ?? '',
    roleCode: json['roleCode'] as String? ?? 'viewer',
    avatarUrl: json['avatarUrl'] as String?,
  );
}

class ChannelInvitation {
  const ChannelInvitation({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.channelHandle,
    required this.roleCode,
    required this.expiresAt,
    this.invitedEmail,
  });
  final String id;
  final String channelId;
  final String channelName;
  final String channelHandle;
  final String roleCode;
  final String expiresAt;
  final String? invitedEmail;

  factory ChannelInvitation.fromJson(Map<String, dynamic> json) =>
      ChannelInvitation(
        id: json['channelInvitationId'] as String? ?? '',
        channelId: json['channelId'] as String? ?? '',
        channelName: json['channelName'] as String? ?? '',
        channelHandle: json['channelHandle'] as String? ?? '',
        roleCode: json['roleCode'] as String? ?? 'viewer',
        expiresAt: json['expiresAt'] as String? ?? '',
        invitedEmail: json['invitedEmail'] as String?,
      );
}

class HandleAvailability {
  const HandleAvailability({
    required this.handle,
    required this.isAvailable,
    this.reason,
  });

  final String handle;
  final bool isAvailable;
  final String? reason;

  factory HandleAvailability.fromJson(Map<String, dynamic> json) =>
      HandleAvailability(
        handle: json['handle'] as String? ?? '',
        isAvailable: json['isAvailable'] as bool? ?? false,
        reason: json['reason'] as String?,
      );
}
