namespace HuTube.Application.Videos;

public sealed record ModerationQueueItemResponse(
    Guid ModerationCaseId,
    Guid VideoId,
    string Title,
    string? Description,
    string VideoUrl,
    string? ThumbnailUrl,
    int Duration,
    Guid ChannelId,
    string ChannelName,
    string? ChannelHandle,
    string? ChannelAvatarUrl,
    string? CategoryName,
    string CaseType,
    string Status,
    string RiskLevel,
    Guid? ReviewerId,
    string? ReviewerName,
    DateTimeOffset SubmittedAt,
    DateTimeOffset? ClaimedAt,
    string? Note,
    Guid? ClaimId = null,
    DateTimeOffset? ClaimExpiresAt = null
);

public sealed record ResolveModerationRequest(
    string Decision, // approve, age_restricted, recommendation_restricted, reject, escalate
    string? PolicyCode,
    string? Reason,
    string? InternalNote,
    Guid? ClaimId = null
);

public sealed record ClaimActionRequest(Guid? ClaimId = null);
public sealed record ClaimLeaseResponse(Guid? ClaimId, DateTimeOffset? ClaimExpiresAt);

public sealed record ModerationDecisionResponse(
    Guid ModerationCaseId,
    Guid VideoId,
    string Status,
    string Decision,
    string? PolicyCode,
    string Message
);
