namespace HuTube.Domain.Channels;

public static class ChannelQuotaRules
{
    public static bool CanReserve(long storageUsed, long fileSize, long storageLimit)
    {
        if (fileSize < 0) return false;
        if (storageLimit <= 0) return false;
        return storageUsed + fileSize <= storageLimit;
    }

    public static long Remaining(long storageLimit, long storageUsed)
    {
        if (storageLimit <= 0) return 0;
        return Math.Max(0, storageLimit - storageUsed);
    }
}

public sealed class ChannelQuota
{
    public Guid ChannelQuotaId { get; set; } = Guid.NewGuid();
    public Guid ChannelId { get; set; }
    public long StorageLimit { get; set; } = 10L * 1024 * 1024 * 1024; // 10 GB default
    public long StorageUsed { get; set; } = 0;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}
