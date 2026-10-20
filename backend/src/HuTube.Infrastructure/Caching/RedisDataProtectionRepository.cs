using System.Xml.Linq;
using Microsoft.AspNetCore.DataProtection.Repositories;

namespace HuTube.Infrastructure.Caching;

// This is a persistent key ring, separate from expiring cache entries.
public sealed class RedisDataProtectionRepository(UpstashRedisClient redis, string key) : IXmlRepository
{
    public IReadOnlyCollection<XElement> GetAllElements()
    {
        var result = redis.CommandAsync(["HVALS", key]).GetAwaiter().GetResult();
        return result.EnumerateArray().Select(value => XElement.Parse(value.GetString()!)).ToArray();
    }

    public void StoreElement(XElement element, string friendlyName) => redis.CommandAsync([
        "HSET", key, string.IsNullOrEmpty(friendlyName) ? Guid.NewGuid().ToString("N") : friendlyName,
        element.ToString(SaveOptions.DisableFormatting)
    ]).GetAwaiter().GetResult();
}
