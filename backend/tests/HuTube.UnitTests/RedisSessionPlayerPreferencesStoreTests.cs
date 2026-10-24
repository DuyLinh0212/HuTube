using System.Net;
using HuTube.Application.Auth;
using HuTube.Domain.Users;
using HuTube.Infrastructure.Authentication;
using HuTube.Infrastructure.Caching;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;

namespace HuTube.UnitTests;

public sealed class RedisSessionPlayerPreferencesStoreTests
{
    [Fact]
    public async Task RedisConnectionLossDuringReadReturnsTheCachedSessionCopy()
    {
        // Arrange
        var handler = new RedisDisconnectsAfterWriteHandler();
        using var http = new HttpClient(handler);
        var clients = new FixedHttpClientFactory(http);
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["UPSTASH_REDIS_REST_URL"] = "https://redis.example.test",
            ["UPSTASH_REDIS_REST_TOKEN"] = "test-token"
        }).Build();
        using var memory = new MemoryCache(new MemoryCacheOptions());
        var store = new RedisSessionPlayerPreferencesStore(
            new UpstashRedisClient(clients, configuration, TimeProvider.System, NullLogger<UpstashRedisClient>.Instance),
            memory, NullLogger<RedisSessionPlayerPreferencesStore>.Instance);
        var session = new UserSession { ExpiresAt = DateTimeOffset.UtcNow.AddHours(1) };
        var expected = new SessionPlayerPreferences(0.35m, true);

        // Act
        await store.SetAsync(session, expected, CancellationToken.None);
        Assert.Equal(expected, await store.GetAsync(session, CancellationToken.None));
        Assert.Equal(1, handler.RequestCount); // A warm read does not call Redis.
        memory.Remove($"session-player-preferences:{session.SessionId:N}");
        var actual = await store.GetAsync(session, CancellationToken.None);

        // Assert
        Assert.Equal(expected, actual);
        Assert.Equal(2, handler.RequestCount);
        Assert.Equal(expected, await store.GetAsync(session, CancellationToken.None));
        Assert.Equal(2, handler.RequestCount); // Redis cooldown also protects fallback reads.
    }

    private sealed class RedisDisconnectsAfterWriteHandler : HttpMessageHandler
    {
        public int RequestCount { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            RequestCount++;
            if (RequestCount == 1)
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent("{\"result\":1}", System.Text.Encoding.UTF8, "application/json")
                });

            throw new HttpRequestException("Redis disconnected after the preference was saved.");
        }
    }

    private sealed class FixedHttpClientFactory(HttpClient client) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => client;
    }
}
