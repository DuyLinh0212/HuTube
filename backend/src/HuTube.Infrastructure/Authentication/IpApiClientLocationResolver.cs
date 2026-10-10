using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using HuTube.Application.Auth;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;

namespace HuTube.Infrastructure.Authentication;

public sealed class IpApiClientLocationResolver(
    HttpClient http,
    GeoIpOptions options,
    IMemoryCache cache,
    ILogger<IpApiClientLocationResolver> logger) : IClientLocationResolver
{
    public async Task<ClientLocation?> ResolveAsync(string? ipAddress, CancellationToken ct = default)
    {
        if (!options.Enabled || !IPAddress.TryParse(ipAddress, out var address) || IsPrivate(address)) return null;
        if (cache.TryGetValue(CacheKey(ipAddress!), out ClientLocation? cached)) return cached;

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromMilliseconds(Math.Clamp(options.TimeoutMilliseconds, 100, 5000)));
        try
        {
            var endpoint = options.Endpoint.TrimEnd('/') + "/" + Uri.EscapeDataString(ipAddress!) + "/json/";
            using var response = await http.GetAsync(endpoint, timeout.Token);
            if (!response.IsSuccessStatusCode) return null;
            var payload = await response.Content.ReadFromJsonAsync<IpApiResponse>(cancellationToken: timeout.Token);
            if (payload is null || payload.Error == true) return null;

            var location = new ClientLocation(
                Clean(payload.CountryCode, 8), Clean(payload.Region, 120), Clean(payload.City, 120),
                payload.Latitude, payload.Longitude);
            cache.Set(CacheKey(ipAddress!), location, TimeSpan.FromHours(24));
            return location;
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            logger.LogDebug("GeoIP lookup timed out.");
            return null;
        }
        catch (HttpRequestException)
        {
            logger.LogDebug("GeoIP lookup failed.");
            return null;
        }
        catch (JsonException)
        {
            logger.LogDebug("GeoIP lookup returned an invalid response.");
            return null;
        }
        catch (UriFormatException)
        {
            logger.LogWarning("GeoIP endpoint configuration is invalid.");
            return null;
        }
    }

    private static string CacheKey(string ip) => "geoip:" + ip;
    private static string? Clean(string? value, int max) => string.IsNullOrWhiteSpace(value) ? null : value.Trim()[..Math.Min(value.Trim().Length, max)];

    private static bool IsPrivate(IPAddress address)
    {
        if (IPAddress.IsLoopback(address)) return true;
        if (address.IsIPv4MappedToIPv6) address = address.MapToIPv4();
        if (address.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork) return false;
        var bytes = address.GetAddressBytes();
        return bytes[0] == 10 || bytes[0] == 127 || (bytes[0] == 172 && bytes[1] is >= 16 and <= 31)
            || (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 169 && bytes[1] == 254);
    }

    private sealed record IpApiResponse(
        [property: JsonPropertyName("country_code")]
        string? CountryCode,
        [property: JsonPropertyName("region")]
        string? Region,
        [property: JsonPropertyName("city")]
        string? City,
        [property: JsonPropertyName("latitude")]
        double? Latitude,
        [property: JsonPropertyName("longitude")]
        double? Longitude,
        [property: JsonPropertyName("error")]
        bool? Error);
}
