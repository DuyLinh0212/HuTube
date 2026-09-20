namespace HuTube.Domain.Channels;

public sealed class Subscription
{
    public Guid SubscriptionId { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public Guid ChannelId { get; set; }
    public DateTimeOffset SubscribedAt { get; set; } = DateTimeOffset.UtcNow;
    public bool NotificationsEnabled { get; set; } = true;
    public string Status { get; set; } = "active";
}
