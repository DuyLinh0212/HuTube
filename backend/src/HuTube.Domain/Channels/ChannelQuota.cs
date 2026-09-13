namespace HuTube.Domain.Channels;

public static class ChannelQuotaRules
{
    public const long DefaultStorageLimit = 10L * 1024 * 1024 * 1024;

    public static bool CanReserve(long storageUsed, long fileSize, long storageLimit)
    {
        if (storageUsed < 0 || fileSize < 0) return false;
        if (storageLimit <= 0) return false;
        // Subtract before comparing so a malformed/large value cannot overflow
        // and accidentally make an over-quota upload look valid.
        return storageUsed <= storageLimit && fileSize <= storageLimit - storageUsed;
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
    public long StorageLimit { get; set; } = ChannelQuotaRules.DefaultStorageLimit;
    public long StorageUsed { get; set; } = 0;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}
