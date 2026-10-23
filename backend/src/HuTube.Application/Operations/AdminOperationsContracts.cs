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

public sealed record AdminApiTrafficBucket(
    DateTimeOffset BucketStart,
    bool IsObserved,
    long? Requests,
    long? ClientErrors,
    long? ServerErrors);

public sealed record AdminApiTrafficOverview(
    DateTimeOffset CollectedSince,
    long RequestsThisMinute,
    long RequestsLast15Minutes,
    long ClientErrorsLast15Minutes,
    long ServerErrorsLast15Minutes,
    long RateLimitedLast15Minutes,
    double ClientErrorRateLast15Minutes,
    double ServerErrorRateLast15Minutes,
    double? AverageLatencyMsLast15Minutes,
    double? P95LatencyMsLast15Minutes,
    IReadOnlyList<AdminApiTrafficBucket> Hourly);

public sealed record AdminSystemLiveMetrics(
    long ActiveSessions,
    long PendingPayments,
    long ExpiredPendingPayments,
    long FailedPaymentsLast24Hours,
    long VideosProcessing,
    long FailedVideosLast24Hours,
    long RenditionsProcessing,
    long FailedRenditionsLast24Hours,
    long PendingVideoReviews,
    int ActiveSignalRConnections);

public sealed record AdminSystemServiceStatus(
    string Key,
    string Status,
    string Detail,
    double? ResponseTimeMs);

public sealed record AdminR2StorageUsage(
    string Status,
    string BucketName,
    long? TotalSizeBytes,
    long? PayloadSizeBytes,
    long? MetadataSizeBytes,
    long? ObjectCount,
    long? PendingUploadCount,
    DateTimeOffset? SampledAt,
    string Detail);

public sealed record AdminNeonUsage(
    string Status,
    long? DatabaseSizeBytes,
    int? ActiveConnections,
    int? ConnectionLimit,
    double? ComputeUnitHoursThisMonth,
    string Detail);

public sealed record AdminRedisUsage(
    string Status,
    string DatabaseName,
    long? CurrentStorageBytes,
    long? StorageLimitBytes,
    long? MonthlyRequests,
    long? RequestLimit,
    string Plan,
    string Detail);

public sealed record AdminEc2MemoryUsage(
    string Status,
    long? TotalBytes,
    long? UsedBytes,
    long? AvailableBytes,
    int? UsedPercent,
    DateTimeOffset? SampledAt,
    string Detail);

public sealed record AdminSystemActivity(
    DateTimeOffset OccurredAt,
    string Category,
    string Status,
    string Title,
    string Detail,
    Guid? ResourceId);

public sealed record AdminSystemOverviewResponse(
    DateTimeOffset SampledAt,
    int ActiveAlertCount,
    int CriticalAlertCount,
    IReadOnlyList<AdminSystemSignal> Signals,
    IReadOnlyList<AdminSystemRuntimeSetting> RuntimeSettings,
    AdminApiTrafficOverview ApiTraffic,
    AdminSystemLiveMetrics LiveMetrics,
    IReadOnlyList<AdminSystemServiceStatus> Services,
    AdminR2StorageUsage R2StorageUsage,
    AdminNeonUsage NeonUsage,
    AdminRedisUsage RedisUsage,
    AdminEc2MemoryUsage Ec2Memory,
    IReadOnlyList<AdminSystemActivity> RecentActivity,
    IReadOnlyList<AdminSystemActivity> IncidentHistory);

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
