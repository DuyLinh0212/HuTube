namespace HuTube.Domain.Backups;

public sealed class DatabaseBackupSchedule
{
    public int Id { get; set; } = 1;
    public bool Enabled { get; set; }
    public string Frequency { get; set; } = "daily";
    public int? DayOfWeek { get; set; }
    public int Hour { get; set; } = 2;
    public int Minute { get; set; }
    public string TimeZoneId { get; set; } = "Asia/Ho_Chi_Minh";
    public DateTimeOffset? NextRunAt { get; set; }
    public DateTimeOffset? LastRunAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
    public Guid? UpdatedByUserId { get; set; }
}

public sealed class DatabaseBackupRun
{
    public Guid RunId { get; set; } = Guid.NewGuid();
    public string Trigger { get; set; } = "manual";
    public string Status { get; set; } = "queued";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? StartedAt { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
    public Guid? InitiatedByUserId { get; set; }
    public string? ObjectKey { get; set; }
    public string? FileName { get; set; }
    public long? SizeBytes { get; set; }
    public string? ErrorMessage { get; set; }
}
