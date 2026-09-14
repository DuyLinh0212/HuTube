namespace HuTube.Domain.Videos;

public sealed record VideoChapter(int StartSeconds, string Title);

public sealed class VideoValidationException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}

public static class VideoRules
{
    public static readonly string[] Visibilities = ["public", "unlisted", "private"];
    public static readonly string[] Reactions = ["like", "dislike"];
    public static readonly string[] Qualities = ["144p", "240p", "360p", "480p", "720p", "1080p", "1440p", "2160p"];
    private static readonly HashSet<string> VideoTypes = new(StringComparer.OrdinalIgnoreCase)
        { "video/mp4", "video/webm", "video/quicktime", "video/x-matroska" };

    public static void ValidateUpload(string contentType, long fileSize, long maxUploadSize)
    {
        if (!VideoTypes.Contains(contentType))
            throw new VideoValidationException("INVALID_VIDEO_TYPE", "Chỉ hỗ trợ MP4, WebM, MOV hoặc MKV.");
        if (fileSize <= 0) throw new VideoValidationException("EMPTY_VIDEO", "File video không được để trống.");
        if (fileSize > maxUploadSize) throw new VideoValidationException("FILE_TOO_LARGE", "Video vượt quá dung lượng gói cho phép.");
    }

    public static void ValidateVisibility(string? visibility)
    {
        if (!Visibilities.Contains(visibility, StringComparer.OrdinalIgnoreCase))
            throw new VideoValidationException("INVALID_VISIBILITY", "Chế độ hiển thị không hợp lệ.");
    }

    public static IReadOnlyList<VideoChapter> ValidateChapters(IEnumerable<VideoChapter>? chapters, int duration)
    {
        var result = (chapters ?? []).Select(x => new VideoChapter(x.StartSeconds, x.Title.Trim())).ToArray();
        if (result.Length > 100) throw new VideoValidationException("TOO_MANY_CHAPTERS", "Video có tối đa 100 chương.");
        var previous = -1;
        foreach (var chapter in result)
        {
            if (chapter.StartSeconds < 0 || chapter.StartSeconds >= duration || chapter.StartSeconds <= previous || chapter.Title.Length is < 1 or > 100)
                throw new VideoValidationException("INVALID_CHAPTERS", "Mốc chương phải tăng dần, nằm trong video và có tiêu đề hợp lệ.");
            previous = chapter.StartSeconds;
        }
        return result;
    }

    public static decimal CalculateProgress(int watchedSeconds, int durationSeconds)
    {
        if (durationSeconds <= 0) throw new VideoValidationException("INVALID_DURATION", "Thời lượng video không hợp lệ.");
        return Math.Round(Math.Clamp(watchedSeconds * 100m / durationSeconds, 0, 100), 2);
    }

    public static string ValidateComment(string? content)
    {
        var value = content?.Trim() ?? "";
        if (value.Length is < 3 or > 5000)
            throw new VideoValidationException("INVALID_COMMENT", "Bình luận cần từ 3 đến 5.000 ký tự.");
        return value;
    }

    public static void ValidateReaction(string? reaction)
    {
        if (!Reactions.Contains(reaction, StringComparer.OrdinalIgnoreCase))
            throw new VideoValidationException("INVALID_REACTION", "Cảm xúc phải là like hoặc dislike.");
    }

    public static void ValidateRating(int score)
    {
        if (score is < 1 or > 5) throw new VideoValidationException("INVALID_RATING", "Điểm đánh giá phải từ 1 đến 5.");
    }

    public static int QualityHeight(string? quality) => quality?.ToLowerInvariant() switch
    {
        "144p" => 144, "240p" => 240, "360p" => 360, "480p" => 480,
        "720p" => 720, "1080p" => 1080, "1440p" => 1440, "2160p" => 2160,
        _ => 0
    };

    public static IReadOnlyList<string> LowerQualities(string sourceQuality)
    {
        var sourceHeight = QualityHeight(sourceQuality);
        if (sourceHeight == 0) throw new VideoValidationException("INVALID_VIDEO_QUALITY", "Chất lượng video không hợp lệ.");
        return new[] { "2160p", "1440p", "1080p", "720p", "480p", "360p" }
            .Where(quality => QualityHeight(quality) < sourceHeight)
            .ToArray();
    }
}

public sealed class Plan
{
    public Guid PlanId { get; set; }
    public string Code { get; set; } = "free";
    public string Name { get; set; } = "Miễn phí";
    public string? Description { get; set; }
    public decimal Price { get; set; }
    public int DurationDays { get; set; }
    public long StorageLimit { get; set; }
    public long MaxUploadSize { get; set; }
    public int MaxVideoDuration { get; set; }
    public int MaxMembers { get; set; } = 1;
    public string Status { get; set; } = "active";
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public string? MaxVideoQuality { get; set; }
    public string? MaxDownloadQuality { get; set; } = "720p";
    public string Features { get; set; } = "{}";
    public int DisplayOrder { get; set; }
}

public sealed class Category
{
    public Guid CategoryId { get; set; }
    public string Name { get; set; } = "";
    public string Slug { get; set; } = "";
    public string? Description { get; set; }
    public string Status { get; set; } = "active";
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}

public sealed class Video
{
    public Guid VideoId { get; set; } = Guid.NewGuid();
    public Guid ChannelId { get; set; }
    public Guid? CategoryId { get; set; }
    public string Title { get; set; } = "";
    public string? Description { get; set; }
    public string VideoUrl { get; set; } = "";
    public string? ThumbnailUrl { get; set; }
    public int Duration { get; set; }
    public long FileSize { get; set; }
    public string Visibility { get; set; } = "private";
    public string Status { get; set; } = "processing";
    public DateTimeOffset? PublishedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public string? LanguageCode { get; set; }
    public bool AgeRestricted { get; set; }
    public string ModerationStatus { get; set; } = "not_submitted";
    public DateTimeOffset? ScheduledAt { get; set; }
    public string? IdempotencyKey { get; set; }
    public string Metadata { get; set; } = "{}";
}

public sealed class VideoRendition
{
    public Guid VideoRenditionId { get; set; } = Guid.NewGuid();
    public Guid VideoId { get; set; }
    public string QualityLabel { get; set; } = "";
    public int Width { get; set; }
    public int Height { get; set; }
    public int? BitrateKbps { get; set; }
    public string? Codec { get; set; }
    public string FileUrl { get; set; } = "";
    public long FileSize { get; set; }
    public string Status { get; set; } = "ready";
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}

public sealed class Tag { public Guid TagId { get; set; } = Guid.NewGuid(); public string Name { get; set; } = ""; public DateTimeOffset CreatedAt { get; set; } }
public sealed class VideoTag { public Guid VideoTagId { get; set; } = Guid.NewGuid(); public Guid VideoId { get; set; } public Guid TagId { get; set; } public DateTimeOffset CreatedAt { get; set; } }
public sealed class ViewingHistory { public Guid ViewingHistoryId { get; set; } = Guid.NewGuid(); public Guid UserId { get; set; } public Guid VideoId { get; set; } public DateTimeOffset ViewedAt { get; set; } public int WatchDuration { get; set; } public decimal Progress { get; set; } }
public sealed class ShareHistory { public Guid ShareHistoryId { get; set; } = Guid.NewGuid(); public Guid UserId { get; set; } public Guid VideoId { get; set; } public string ShareMethod { get; set; } = "copy_link"; public DateTimeOffset SharedAt { get; set; } }
public sealed class VideoReaction { public Guid VideoReactionId { get; set; } = Guid.NewGuid(); public Guid UserId { get; set; } public Guid VideoId { get; set; } public string Type { get; set; } = "like"; public DateTimeOffset CreatedAt { get; set; } public DateTimeOffset UpdatedAt { get; set; } }
public sealed class VideoRating { public Guid VideoRatingId { get; set; } = Guid.NewGuid(); public Guid UserId { get; set; } public Guid VideoId { get; set; } public short Score { get; set; } public DateTimeOffset EvaluatedAt { get; set; } public DateTimeOffset UpdatedAt { get; set; } }

public sealed class Comment
{
    public Guid CommentId { get; set; } = Guid.NewGuid(); public Guid UserId { get; set; } public Guid VideoId { get; set; }
    public Guid? ParentCommentId { get; set; } public string Content { get; set; } = ""; public string Status { get; set; } = "visible";
    public DateTimeOffset CreatedAt { get; set; } public DateTimeOffset UpdatedAt { get; set; }
}
public sealed class CommentReaction { public Guid CommentReactionId { get; set; } = Guid.NewGuid(); public Guid UserId { get; set; } public Guid CommentId { get; set; } public string Type { get; set; } = "like"; public DateTimeOffset CreatedAt { get; set; } public DateTimeOffset UpdatedAt { get; set; } }
public sealed class Policy
{
    public Guid PolicyId { get; set; } = Guid.NewGuid();
    public string Code { get; set; } = "";
    public string Name { get; set; } = "";
    public string Group { get; set; } = "content";
    public string Content { get; set; } = "";
    public string Severity { get; set; } = "medium";
    public string Version { get; set; } = "1.0";
    public string Status { get; set; } = "published";
    public DateTimeOffset EffectiveAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public static class PolicyCodes
{
    public const string SexualExplicit = "SEXUAL.EXPLICIT";
    public const string ViolenceGraphic = "VIOLENCE.GRAPHIC";
    public const string HateSpeech = "HATE.SPEECH";
    public const string HarassmentBullying = "HARASSMENT.BULLYING";
    public const string ChildSafety = "CHILD_SAFETY.VIOLATION";
    public const string DangerousContent = "DANGEROUS.CONTENT";
    public const string SpamMisleading = "SPAM.MISLEADING";
    public const string CopyrightUnauthorized = "COPYRIGHT.UNAUTHORIZED";
}

public sealed class Notification { public Guid NotificationId { get; set; } = Guid.NewGuid(); public Guid UserId { get; set; } public string Type { get; set; } = ""; public string Title { get; set; } = ""; public string Content { get; set; } = ""; public string? ActionUrl { get; set; } public bool IsRead { get; set; } public DateTimeOffset CreatedAt { get; set; } public DateTimeOffset? ReadAt { get; set; } public string? ResourceType { get; set; } public Guid? ResourceId { get; set; } }
public sealed class ViolationType { public Guid ViolationTypeId { get; set; } public string Code { get; set; } = ""; public string Name { get; set; } = ""; public string? Description { get; set; } public string Status { get; set; } = "active"; public DateTimeOffset CreatedAt { get; set; } public DateTimeOffset UpdatedAt { get; set; } }
public sealed class Report { public Guid ReportId { get; set; } = Guid.NewGuid(); public Guid UserId { get; set; } public Guid ViolationTypeId { get; set; } public Guid? VideoId { get; set; } public Guid? ChannelId { get; set; } public Guid? CommentId { get; set; } public string Description { get; set; } = ""; public string Status { get; set; } = "pending"; public DateTimeOffset CreatedAt { get; set; } public DateTimeOffset UpdatedAt { get; set; } }
public sealed class ModerationCase
{
    public Guid ModerationCaseId { get; set; } = Guid.NewGuid();
    public Guid? VideoId { get; set; }
    public Guid? ReportId { get; set; }
    public Guid? ReviewerId { get; set; }
    public string CaseType { get; set; } = "upload_review";
    public string Status { get; set; } = "pending";
    public string? Note { get; set; }
    public string? PolicyCode { get; set; }
    public string? PolicyVersion { get; set; }
    public string? Decision { get; set; }
    public string? InternalNote { get; set; }
    public string RiskLevel { get; set; } = "normal";
    public DateTimeOffset SubmittedAt { get; set; }
    public DateTimeOffset? ClaimedAt { get; set; }
    public DateTimeOffset? ResolvedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}
public sealed class CommentModerationAction { public Guid CommentModerationActionId { get; set; } = Guid.NewGuid(); public Guid CommentId { get; set; } public Guid ModeratorUserId { get; set; } public string ActionType { get; set; } = "hide"; public string? Reason { get; set; } public DateTimeOffset CreatedAt { get; set; } }

public sealed class VideoDownload
{
    public Guid VideoDownloadId { get; set; } = Guid.NewGuid(); public Guid UserId { get; set; } public Guid VideoId { get; set; }
    public string QualityLabel { get; set; } = ""; public string FileUrl { get; set; } = ""; public long FileSize { get; set; }
    public string Status { get; set; } = "ready"; public DateTimeOffset CreatedAt { get; set; } public DateTimeOffset UpdatedAt { get; set; }
}
