using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace HuTube.Infrastructure.Caching;

public sealed class RedisUnavailableException : Exception
{
    public RedisUnavailableException() : base("Redis is temporarily unavailable.") { }
}

public sealed class UpstashRedisClient(IHttpClientFactory clients, IConfiguration configuration,
    TimeProvider clock, ILogger<UpstashRedisClient> logger)
{
    private long unavailableUntil;
    private static string? Endpoint(IConfiguration config) => First(config["UPSTASH_REDIS_REST_URL"],
        config["SystemMonitoring:RedisRestUrl"], config["Redis:Endpoint"]);
    private static string? Token(IConfiguration config) => First(config["UPSTASH_REDIS_REST_TOKEN"],
        config["SystemMonitoring:RedisRestToken"], config["Redis:Password"]);
    private static string? First(params string?[] values) => values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));

    public static bool IsConfigured(IConfiguration config) => config.GetValue("Redis:Enabled", true)
        && !string.IsNullOrWhiteSpace(Token(config))
        && Uri.TryCreate(Endpoint(config), UriKind.Absolute, out var uri) && uri.Scheme == "https"
        && uri.UserInfo.Length == 0 && uri.Query.Length == 0 && uri.Fragment.Length == 0;
    public bool Configured => IsConfigured(configuration);

    public async Task<JsonElement> CommandAsync(string[] command, CancellationToken ct = default)
    {
        if (!Configured || clock.GetUtcNow().UtcTicks < Interlocked.Read(ref unavailableUntil))
            throw new RedisUnavailableException();
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint(configuration)) {
                Content = JsonContent.Create(command)
            };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", Token(configuration));
            using var response = await clients.CreateClient("redis-rest").SendAsync(request, ct);
            response.EnsureSuccessStatusCode();
            using var document = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(ct), cancellationToken: ct);
            if (document.RootElement.TryGetProperty("error", out _) || !document.RootElement.TryGetProperty("result", out var result))
                throw new InvalidOperationException("Redis rejected the command.");
            return result.Clone();
        }
        catch (Exception ex) when (!ct.IsCancellationRequested
            && ex is HttpRequestException or OperationCanceledException or JsonException or InvalidOperationException)
        {
            var until = clock.GetUtcNow().AddSeconds(30).UtcTicks;
            if (Interlocked.Exchange(ref unavailableUntil, until) < clock.GetUtcNow().UtcTicks)
                logger.LogWarning("Redis is unavailable; using the data source and pausing Redis requests for 30 seconds.");
            throw new RedisUnavailableException();
        }
    }
}
