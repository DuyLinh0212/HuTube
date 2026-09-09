namespace HuTube.Domain.Channels;

public sealed class ChannelQuota
{
    public Guid ChannelQuotaId { get; set; } = Guid.NewGuid();
    public Guid ChannelId { get; set; }
    public long StorageLimit { get; set; } = 10L * 1024 * 1024 * 1024; // 10 GB default
    public long StorageUsed { get; set; } = 0;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}
