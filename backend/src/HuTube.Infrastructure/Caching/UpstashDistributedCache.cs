using Microsoft.Extensions.Caching.Distributed;

namespace HuTube.Infrastructure.Caching;

// HybridCache supplies absolute expirations. This REST adapter keeps Redis optional:
// cache failures become misses while reads still use the authoritative database.
public sealed class UpstashDistributedCache(UpstashRedisClient redis, string prefix, TimeProvider clock) : IDistributedCache
{
    public byte[]? Get(string key) => GetAsync(key).GetAwaiter().GetResult();
    public async Task<byte[]?> GetAsync(string key, CancellationToken token = default)
    {
        try
        {
            var result = await redis.CommandAsync(["GET", prefix + key], token);
            return result.ValueKind == System.Text.Json.JsonValueKind.String
                ? Convert.FromBase64String(result.GetString()!) : null;
        }
        catch (RedisUnavailableException) { return null; }
        catch (FormatException) { return null; }
    }

    public void Set(string key, byte[] value, DistributedCacheEntryOptions options) => SetAsync(key, value, options).GetAwaiter().GetResult();
    public async Task SetAsync(string key, byte[] value, DistributedCacheEntryOptions options, CancellationToken token = default)
    {
        if (options.SlidingExpiration.HasValue)
            throw new NotSupportedException("Use HybridCache with an absolute expiration for Redis REST.");
        var ttl = options.AbsoluteExpirationRelativeToNow;
        if (options.AbsoluteExpiration.HasValue)
        {
            var remaining = options.AbsoluteExpiration.Value - clock.GetUtcNow();
            if (!ttl.HasValue || remaining < ttl.Value) ttl = remaining;
        }
        if (!ttl.HasValue) throw new ArgumentException("Redis cache entries require an expiration.", nameof(options));
        if (ttl.Value <= TimeSpan.Zero) { await RemoveAsync(key, token); return; }
        try
        {
            await redis.CommandAsync(["SET", prefix + key, Convert.ToBase64String(value), "PX",
                Math.Ceiling(ttl.Value.TotalMilliseconds).ToString(System.Globalization.CultureInfo.InvariantCulture)], token);
        }
        catch (RedisUnavailableException) { }
    }

    // Absolute expirations must not be prolonged by a read or Refresh call.
    public void Refresh(string key) { }
    public Task RefreshAsync(string key, CancellationToken token = default) => Task.CompletedTask;
    public void Remove(string key) => RemoveAsync(key).GetAwaiter().GetResult();
    public async Task RemoveAsync(string key, CancellationToken token = default)
    {
        try { await redis.CommandAsync(["DEL", prefix + key], token); }
        catch (RedisUnavailableException) { }
    }
}
