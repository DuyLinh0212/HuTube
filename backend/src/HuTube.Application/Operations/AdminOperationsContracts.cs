namespace HuTube.Application.Operations;

public sealed record AdminSystemSignal(
    string Key,
    string Category,
    string Severity,
    string Title,
    string Description,
    long CurrentValue,
    string Unit,
    long Threshold,
    string? ActionUrl,
    bool IsTriggered);

public sealed record AdminSystemRuntimeSetting(string Name, string Value, string Source);

public sealed record AdminSystemOverviewResponse(
    DateTimeOffset SampledAt,
    int ActiveAlertCount,
    int CriticalAlertCount,
    IReadOnlyList<AdminSystemSignal> Signals,
    IReadOnlyList<AdminSystemRuntimeSetting> RuntimeSettings);

public sealed record AdminSystemMetric(long Total, long InPeriod);
public sealed record AdminSystemRevenueMetric(decimal Total, long TransactionsTotal, decimal InPeriod, long TransactionsInPeriod);
public sealed record AdminSystemReportDay(DateOnly Date, long NewUsers, long NewVideos, long Views, long Comments, decimal Revenue);
public sealed record AdminSystemReportSlice(string Key, long Count);

public sealed record AdminSystemReportResponse(
    DateTimeOffset GeneratedAt,
    int Days,
    AdminSystemMetric Users,
    AdminSystemMetric VerifiedUsers,
    AdminSystemMetric Videos,
    AdminSystemMetric PublishedVideos,
    AdminSystemMetric Channels,
    AdminSystemMetric Views,
    AdminSystemMetric Comments,
    AdminSystemMetric Likes,
    AdminSystemMetric Subscribers,
    AdminSystemMetric Reports,
    AdminSystemMetric PendingReports,
    AdminSystemMetric PendingReviews,
    AdminSystemMetric PendingAppeals,
    AdminSystemMetric ActiveSessions,
    AdminSystemMetric Shares,
    AdminSystemRevenueMetric Revenue,
    IReadOnlyList<AdminSystemReportDay> Daily,
    IReadOnlyList<AdminSystemReportSlice> VideoStatuses,
    IReadOnlyList<AdminSystemReportSlice> ReportStatuses,
    IReadOnlyList<AdminSystemReportSlice> PaymentMethods);

public sealed record AdminAuditLogItem(
    Guid AuditLogId,
    Guid? ActorUserId,
    string? ActorName,
    string? ActorEmail,
    string Action,
    string? ResourceType,
    Guid? ResourceId,
    string? Reason,
    string? IpAddress,
    string? UserAgent,
    DateTimeOffset CreatedAt);

public sealed record AdminAuditLogPage(
    int Page,
    int PageSize,
    long Total,
    long EventsLast24Hours,
    long ActiveAdministratorsLast24Hours,
    long LoginsLast24Hours,
    IReadOnlyList<string> Actions,
    IReadOnlyList<AdminSystemRuntimeSetting> RuntimeSettings,
    IReadOnlyList<AdminAuditLogItem> Items);
