namespace HuTube.Domain.Videos;

public sealed class RecommendationJob
{
    public Guid JobId { get; set; } = Guid.NewGuid();
    public Guid ActorUserId { get; set; }
    public string Kind { get; set; } = "";
    public string Status { get; set; } = "queued";
    public string Step { get; set; } = "queued";
    public string PayloadJson { get; set; } = "{}";
    public string LogsJson { get; set; } = "[]";
    public string? Error { get; set; }
    public int Completed { get; set; }
    public int Total { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}
