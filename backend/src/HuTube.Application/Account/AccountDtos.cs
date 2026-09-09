namespace HuTube.Application.Account;

public sealed record UserProfileDto(
    Guid UserId,
    string Username,
    string Email,
    string DisplayName,
    string? AvatarUrl,
    string? Bio,
    bool EmailVerified,
    DateTimeOffset CreatedAt
);

public sealed record UpdateProfileRequest(
    string? DisplayName,
    string? Bio,
    string? AvatarUrl
);

public sealed record ChangePasswordRequest(
    string CurrentPassword,
    string NewPassword
);

public sealed record NotificationSettingsDto(
    bool InAppEnabled,
    bool EmailEnabled,
    bool NewVideoEnabled,
    bool CommentReplyEnabled,
    bool ReportResultEnabled,
    bool ModerationEnabled,
    bool PlanEnabled,
    bool RecommendationEnabled,
    bool MentionEnabled,
    bool ChannelActivityEnabled,
    bool PaymentEnabled
);

public sealed record UpdateNotificationSettingsRequest(
    bool InAppEnabled,
    bool EmailEnabled,
    bool NewVideoEnabled,
    bool CommentReplyEnabled,
    bool ReportResultEnabled,
    bool ModerationEnabled,
    bool PlanEnabled,
    bool RecommendationEnabled,
    bool MentionEnabled,
    bool ChannelActivityEnabled,
    bool PaymentEnabled
);

public sealed record UserPreferencesDto(
    string Language,
    string Theme,
    bool KeepSubscriptionsPrivate,
    bool KeepPlaylistsPrivate,
    string? Location
);

public sealed record UpdateUserPreferencesRequest(
    string? Language,
    string? Theme,
    bool? KeepSubscriptionsPrivate,
    bool? KeepPlaylistsPrivate,
    string? Location
);
