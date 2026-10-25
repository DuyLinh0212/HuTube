namespace HuTube.Domain.Videos;

public sealed class ModerationOutboxEvent
{
    public Guid EventId { get; set; }
    public string EventType { get; set; } = "";
    public string Payload { get; set; } = "{}";
    public DateTimeOffset OccurredAt { get; set; }
    public DateTimeOffset AvailableAt { get; set; }
    public DateTimeOffset? PublishedAt { get; set; }
    public int Attempts { get; set; }
    public string? LastError { get; set; }
}

public sealed class NotificationInboxEvent
{
    public Guid EventId { get; set; }
    public bool OwnerProcessed { get; set; }
    public Guid? LastSubscriptionId { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
}

public sealed class NotificationDelivery
{
    public Guid DeliveryId { get; set; }
    public Guid EventId { get; set; }
    public Guid UserId { get; set; }
    public Guid? NotificationId { get; set; }
    public string Type { get; set; } = "";
    public string Payload { get; set; } = "{}";
    public bool RealtimeDone { get; set; }
    public bool EmailDone { get; set; }
    public bool PushDone { get; set; }
    public int Attempts { get; set; }
    public DateTimeOffset AvailableAt { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
    public string? LastError { get; set; }
}

public sealed class PushDevice
{
    public Guid PushDeviceId { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public Guid SessionId { get; set; }
    public string Token { get; set; } = "";
    public string TokenHash { get; set; } = "";
    public string Platform { get; set; } = "android";
    public DateTimeOffset UpdatedAt { get; set; }
}
