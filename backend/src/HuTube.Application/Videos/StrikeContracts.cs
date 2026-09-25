namespace HuTube.Application.Videos;

// ================= STRIKE CONTRACTS =================

public sealed record ChannelStrikeDto(
    Guid StrikeId,
    Guid ChannelId,
    string? ChannelName,
    Guid UserId,
    int StrikeNumber,
    string Severity,
    string? PolicyCode,
    string Reason,
    string? InternalNote,
    string Status,
    DateTimeOffset ExpiresAt,
    DateTimeOffset CreatedAt,
    DateTimeOffset? RevokedAt,
    Guid? RevokedByUserId,
    string? RevocationReason,
    string? ChannelHandle = null,
    string? ChannelStatus = null
);

public sealed record CreateStrikeRequest(
    Guid ChannelId,
    string? PolicyCode,
    string Severity,
    string Reason,
    string? InternalNote
);

public sealed record RevokeStrikeRequest(
    string Reason
);

public sealed record ChannelStrikeStatusResponse(
    Guid ChannelId,
    int ActiveStrikesCount,
    bool HasWarning,
    bool IsSuspended,
    DateTimeOffset? UploadRestrictedUntil,
    IReadOnlyList<ChannelStrikeDto> Strikes,
    string? UploadRestrictionReason = null,
    bool AppealEligible = false
);

// ================= REPORT CONTRACTS =================

public sealed record ReportDto(
    Guid ReportId,
    Guid UserId,
    string? ReporterName,
    string TargetType,
    Guid TargetId,
    string? TargetTitle,
    Guid ViolationTypeId,
    string? ViolationTypeCode,
    string? ViolationTypeName,
    string Description,
    string Status,
    Guid? ReviewerId,
    string? ReviewerName,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    string? TargetUrl = null,
    string? TargetThumbnailUrl = null,
    string? TargetChannelName = null,
    string? TargetChannelHandle = null,
    string? ContextText = null,
    string? Disposition = null,
    bool AbuseFlag = false
);

public sealed record CreateContentReportRequest(
    string TargetType, // video, comment, channel
    Guid TargetId,
    Guid ViolationTypeId,
    string Description,
    string? IdempotencyKey = null
);

public sealed record ResolveReportRequest(
    string Decision, // dismiss, warn, strike, hide, remove, lock_channel, escalate
    string? Reason,
    string? InternalNote,
    string? PolicyCode
);

public sealed record ReportResolutionResponse(
    Guid ReportId,
    string Status,
    string Decision,
    string Message
);

public sealed record ReportViolationCount(string? Code, string? Name, int Count);
public sealed record ReportCaseSummary(
    Guid CaseId,
    string TargetType,
    Guid TargetId,
    string? TargetTitle,
    string? TargetUrl,
    string? TargetThumbnailUrl,
    string? TargetChannelName,
    string? TargetChannelHandle,
    string Status,
    int ReportCount,
    int ReporterCount,
    int UnclassifiedCount,
    IReadOnlyList<ReportViolationCount> ViolationCounts,
    Guid? ReviewerId,
    string? ReviewerName,
    DateTimeOffset SubmittedAt,
    DateTimeOffset UpdatedAt
);
public sealed record ReportCaseReportDetail(
    Guid ReportId,
    Guid UserId,
    string? ReporterName,
    Guid ViolationTypeId,
    string? ViolationTypeCode,
    string? ViolationTypeName,
    string Description,
    string Status,
    string? Disposition,
    string? DispositionReason,
    Guid? DispositionByUserId,
    DateTimeOffset? DispositionAt,
    bool AbuseFlag,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt
);
public sealed record ReportCaseDetail(ReportCaseSummary Case, IReadOnlyList<ReportCaseReportDetail> Reports);
public sealed record UpdateReportDispositionsRequest(IReadOnlyList<Guid> ReportIds, string Disposition, string Reason);
public sealed record ResolveReportCaseRequest(
    string Decision, // dismiss, warn, age_restrict, recommendation_restricted, hide, remove, upload_restriction, strike, lock_channel, escalate
    string Reason,
    string? InternalNote,
    string? PolicyCode,
    int? RestrictionDays = null);

// ================= APPEAL CONTRACTS =================

public sealed record AppealDto(
    Guid AppealId,
    Guid UserId,
    string? UserName,
    string TargetType, // video, channel, comment, strike
    Guid TargetId,
    string? TargetTitle,
    int AppealNumber,
    Guid? ReviewerId,
    string? ReviewerName,
    string Reason,
    string Status,
    string? ReviewNote,
    string? EvidenceUrl,
    string? EvidenceNote,
    Guid? ModerationCaseId,
    Guid? StrikeId,
    DateTimeOffset CreatedAt,
    DateTimeOffset? ResolvedAt
);

public sealed record CreateAppealRequest(
    string TargetType, // video, channel, comment, strike
    Guid TargetId,
    string Reason,
    string? EvidenceUrl,
    string? EvidenceNote,
    Guid? ModerationCaseId,
    Guid? StrikeId
);

public sealed record ResolveAppealRequest(
    string Decision, // approve, reject, escalate
    string? ReviewNote
);

public sealed record AppealResolutionResponse(
    Guid AppealId,
    string Status,
    string Decision,
    string Message
);

public sealed record AppealEvidenceUploadResponse(Guid AppealId, string EvidenceUrl);

// ================= CHANNEL LOCK CONTRACTS =================

public sealed record LockChannelRequest(
    string Reason
);

public sealed record UnlockChannelRequest(
    string Reason
);

