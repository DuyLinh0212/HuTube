namespace HuTube.Domain.Videos;

public static class AppealStatuses
{
    public const string Pending = "pending";
    public const string Reviewing = "reviewing";
    public const string Approved = "approved";
    public const string Rejected = "rejected";
    public const string Cancelled = "cancelled";
}

public static class AppealTargetTypes
{
    public const string Video = "video";
    public const string Channel = "channel";
    public const string Comment = "comment";
    public const string Strike = "strike";
}

public sealed class Appeal
{
    public Guid AppealId { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public Guid? ResolutionId { get; set; }
    public string TargetType { get; set; } = AppealTargetTypes.Video;
    public Guid TargetId { get; set; }
    public int AppealNumber { get; set; } = 1;
    public Guid? ReviewerId { get; set; }
    public string Reason { get; set; } = "";
    public string Status { get; set; } = AppealStatuses.Pending;
    public string? ReviewNote { get; set; }
    public string? EvidenceUrl { get; set; }
    public string? EvidenceNote { get; set; }
    public Guid? ModerationCaseId { get; set; }
    public Guid? StrikeId { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? ResolvedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}
