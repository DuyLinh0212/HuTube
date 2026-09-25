namespace HuTube.Application.Videos;

public sealed record AdminContentActionRequest(string Reason, bool NotifyOwner = true);
public sealed record AdminChannelListItem(Guid ChannelId, string Name, string Handle, Guid OwnerUserId, string OwnerName,
    string OwnerEmail, string Status, DateTimeOffset CreatedAt, int VideoCount, int SubscriberCount, int ActiveStrikeCount,
    long ViewCount = 0, string? StatusReason = null);
public sealed record AdminAuditItem(Guid AuditLogId, string Action, string? Reason, string? ActorName, DateTimeOffset CreatedAt);
public sealed record AdminChannelDetailResponse(AdminChannelListItem Channel, string? Description, string? ContactEmail,
    string? AvatarUrl, string? BannerUrl, string? WatermarkUrl, IReadOnlyList<AdminVideoListItem> Videos,
    IReadOnlyList<AdminAuditItem> History);
public sealed record AdminVideoListItem(
    Guid VideoId,
    Guid ChannelId,
    string ChannelName,
    string ChannelHandle,
    string? ChannelAvatarUrl,
    int ChannelSubscriberCount,
    string Title,
    string? ThumbnailUrl,
    int Duration,
    string DurationFormatted,
    Guid? CategoryId,
    string? CategoryName,
    string Visibility,
    string Status,
    string ModerationStatus,
    int ReportCount,
    bool AgeRestricted,
    DateTimeOffset CreatedAt,
    DateTimeOffset? PublishedAt,
    long Views);
public sealed record AdminVideoReportSummary(Guid ReportId, string ReporterName, string ReporterEmail,
    string ViolationCode, string ViolationName, string Description, string Status, DateTimeOffset CreatedAt);
public sealed record AdminVideoDetailResponse(AdminVideoListItem Video, string? Description, Guid? CategoryId,
    string? CategoryName, string VideoUrl, long FileSize, int Duration, IReadOnlyList<AdminAuditItem> History,
    IReadOnlyList<AdminVideoReportSummary> Reports);
public sealed record UpdateAdminVideoRequest(string? Title, string? Description, Guid? CategoryId, bool ClearCategory, string Reason);

public sealed record VideoDailyUploadStat(string Day, string Label, int Count, int HeightPercent);
public sealed record VideoWeeklyUploadsResponse(int Total, double GrowthPercentage, IReadOnlyList<VideoDailyUploadStat> Days);
public sealed record VideoStorageResponse(int Percentage, long UsedBytes, long TotalBytes, string UsedFormatted, string TotalFormatted, string WeeklyChangeFormatted, int TotalVideos, string TotalVideosFormatted);
public sealed record AdminVideoStatisticsResponse(VideoWeeklyUploadsResponse WeeklyUploads, VideoStorageResponse Storage);
