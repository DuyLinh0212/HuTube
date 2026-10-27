namespace HuTube.Domain.Channels;

// Anonymous aggregate input: the event does not store viewer identity.
public sealed class ChannelAnalyticsEvent
{
    public Guid EventId { get; set; } = Guid.NewGuid();
    public Guid ChannelId { get; set; }
    public Guid? VideoId { get; set; }
    public DateTimeOffset OccurredAt { get; set; }
    public string Metric { get; set; } = "";
    public long Value { get; set; }
}
