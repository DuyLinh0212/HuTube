namespace HuTube.Domain.Videos;

public static class StrikeSeverities
{
    public const string Low = "low";
    public const string Medium = "medium";
    public const string High = "high";
    public const string Critical = "critical";
}

public static class StrikeStatuses
{
    public const string Active = "active";
    public const string Expired = "expired";
    public const string Revoked = "revoked";
}

public sealed class ChannelStrike
{
    public Guid StrikeId { get; set; } = Guid.NewGuid();
    public Guid ChannelId { get; set; }
    public Guid UserId { get; set; }
    public int StrikeNumber { get; set; } = 1;
    public string Severity { get; set; } = StrikeSeverities.High;
    public string? PolicyCode { get; set; }
    public string Reason { get; set; } = "";
    public string? InternalNote { get; set; }
    public string Status { get; set; } = StrikeStatuses.Active;
    public DateTimeOffset ExpiresAt { get; set; } = DateTimeOffset.UtcNow.AddDays(90);
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? UploadRestrictedUntil { get; set; }
    public DateTimeOffset? RevokedAt { get; set; }
    public Guid? RevokedByUserId { get; set; }
    public string? RevocationReason { get; set; }
    public Guid? SourceModerationCaseId { get; set; }
    public Guid? SourceReportId { get; set; }

    public bool IsActive(DateTimeOffset now) =>
        Status == StrikeStatuses.Active && ExpiresAt > now;
}
