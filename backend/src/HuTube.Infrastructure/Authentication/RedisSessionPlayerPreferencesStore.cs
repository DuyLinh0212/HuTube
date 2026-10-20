using System.Globalization;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Domain.Users;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace HuTube.Infrastructure.Authentication;

public sealed class RedisSessionPlayerPreferencesStore(
    IHttpClientFactory clients, IConfiguration configuration, IMemoryCache memory,
    ILogger<RedisSessionPlayerPreferencesStore> logger) : ISessionPlayerPreferencesStore
{
    // HSET changes only audio fields; existing authentication fields remain intact.
    private const string SaveScript = """
        redis.call('HSET', KEYS[1], 'volume', ARGV[1], 'muted', ARGV[2])
        redis.call('PEXPIREAT', KEYS[1], ARGV[3])
        return 1
        """;
    private const string RemoveScript = """
        redis.call('HDEL', KEYS[1], 'volume', 'muted')
        if redis.call('HLEN', KEYS[1]) == 0 then redis.call('DEL', KEYS[1]) end
        return 1
        """;

    private static string Key(Guid id) => $"dalitu:auth:session:{id:N}";
    private static string MemoryKey(Guid id) => $"session-player-preferences:{id:N}";

    public async Task<SessionPlayerPreferences?> GetAsync(UserSession session, CancellationToken ct)
    {
        var cached = memory.Get<SessionPlayerPreferences>(MemoryKey(session.SessionId));
        if (!Configured) return cached;
        try
        {
            var result = await CommandAsync(["HMGET", Key(session.SessionId), "volume", "muted"], ct);
            if (result.ValueKind == JsonValueKind.Array && result.GetArrayLength() == 2
                && decimal.TryParse(result[0].GetString(), NumberStyles.Number, CultureInfo.InvariantCulture, out var volume)
                && volume is >= 0m and <= 1m && bool.TryParse(result[1].GetString(), out var muted))
            {
                var preferences = new SessionPlayerPreferences(volume, muted);
                memory.Set(MemoryKey(session.SessionId), preferences, session.ExpiresAt);
                return preferences;
            }
            memory.Remove(MemoryKey(session.SessionId));
            return null;
        }
        catch (Exception ex) when (Unavailable(ex, ct))
        {
            logger.LogWarning(ex, "Could not read session player preferences from Redis; using the local session copy.");
            return cached;
        }
    }

    public async Task SetAsync(UserSession session, SessionPlayerPreferences preferences, CancellationToken ct)
    {
        memory.Set(MemoryKey(session.SessionId), preferences, session.ExpiresAt);
        if (!Configured) return;
        try
        {
            await CommandAsync(["EVAL", SaveScript, "1", Key(session.SessionId),
                preferences.Volume.ToString(CultureInfo.InvariantCulture), preferences.Muted ? "true" : "false",
                session.ExpiresAt.ToUnixTimeMilliseconds().ToString(CultureInfo.InvariantCulture)], ct);
        }
        catch (Exception ex) when (Unavailable(ex, ct))
        {
            logger.LogWarning(ex, "Could not save session player preferences in Redis; keeping the local session copy.");
        }
    }

    public async Task RemoveAsync(Guid sessionId, CancellationToken ct)
    {
        memory.Remove(MemoryKey(sessionId));
        if (!Configured) return;
        try { await CommandAsync(["EVAL", RemoveScript, "1", Key(sessionId)], ct); }
        catch (Exception ex) when (Unavailable(ex, ct))
        {
            logger.LogWarning(ex, "Could not clear old player preferences; the Redis key will expire with the session.");
        }
    }

    private string? Endpoint => configuration["UPSTASH_REDIS_REST_URL"] ?? configuration["SystemMonitoring:RedisRestUrl"];
    private string? Token => configuration["UPSTASH_REDIS_REST_TOKEN"] ?? configuration["SystemMonitoring:RedisRestToken"];
    private bool Configured => !string.IsNullOrWhiteSpace(Endpoint) && !string.IsNullOrWhiteSpace(Token);

    private async Task<JsonElement> CommandAsync(string[] command, CancellationToken ct)
    {
        if (!Uri.TryCreate(Endpoint, UriKind.Absolute, out var endpoint) || endpoint.Scheme != "https"
            || endpoint.UserInfo.Length > 0 || endpoint.Query.Length > 0 || endpoint.Fragment.Length > 0)
            throw new InvalidOperationException("The session Redis REST endpoint must use HTTPS.");
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint) { Content = JsonContent.Create(command) };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", Token);
        using var response = await clients.CreateClient("session-player-preferences").SendAsync(request, ct);
        response.EnsureSuccessStatusCode();
        using var json = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(ct), cancellationToken: ct);
        if (json.RootElement.TryGetProperty("error", out _) || !json.RootElement.TryGetProperty("result", out var result))
            throw new InvalidOperationException("Redis rejected the session player preferences command.");
        return result.Clone();
    }

    private static bool Unavailable(Exception ex, CancellationToken ct) => !ct.IsCancellationRequested
        && ex is HttpRequestException or OperationCanceledException or JsonException or InvalidOperationException;
}
