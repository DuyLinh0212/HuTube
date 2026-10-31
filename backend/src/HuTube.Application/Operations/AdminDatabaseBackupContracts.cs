namespace HuTube.Application.Operations;

public sealed record UpdateDatabaseBackupScheduleRequest(
    bool Enabled,
    string Frequency,
    int? DayOfWeek,
    string Time);

public sealed record DatabaseBackupScheduleResponse(
    bool Enabled,
    string Frequency,
    int? DayOfWeek,
    string Time,
    string TimeZoneId,
    DateTimeOffset? NextRunAt,
    DateTimeOffset? LastRunAt,
    DateTimeOffset UpdatedAt);

public sealed record DatabaseBackupRunResponse(
    Guid RunId,
    string Trigger,
    string Status,
    DateTimeOffset CreatedAt,
    DateTimeOffset? StartedAt,
    DateTimeOffset? CompletedAt,
    string? FileName,
    long? SizeBytes,
    string? ErrorMessage,
    bool CanDownload);

public sealed record AdminDatabaseBackupOverviewResponse(
    DatabaseBackupScheduleResponse Schedule,
    DatabaseBackupRunResponse? ActiveRun,
    IReadOnlyList<DatabaseBackupRunResponse> Runs,
    bool StorageConfigured);

public sealed record DatabaseBackupDownloadResponse(string Url);
