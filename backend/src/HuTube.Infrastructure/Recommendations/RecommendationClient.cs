using System.Net.Http.Json;
using System.Text.Json;
using HuTube.Application.Recommendations;
using Microsoft.Extensions.Logging;

namespace HuTube.Infrastructure.Recommendations;

public sealed class RecommendationOptions
{
    public string ServiceUrl { get; set; } = "http://127.0.0.1:8000";
    public string ServiceToken { get; set; } = "hutube-cf-internal-secret-key";
    public int TimeoutSeconds { get; set; } = 5;
    public bool Enabled { get; set; } = true;
}

public sealed class RecommendationClient : IRecommendationClient
{
    private readonly HttpClient _http;
    private readonly RecommendationOptions _options;
    private readonly ILogger<RecommendationClient> _logger;
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public RecommendationClient(
        HttpClient http,
        RecommendationOptions options,
        ILogger<RecommendationClient> logger)
    {
        _http = http;
        _options = options;
        _logger = logger;

        if (!string.IsNullOrWhiteSpace(_options.ServiceUrl))
        {
            _http.BaseAddress = new Uri(_options.ServiceUrl.TrimEnd('/') + "/");
        }
        _http.Timeout = TimeSpan.FromSeconds(_options.TimeoutSeconds > 0 ? _options.TimeoutSeconds : 2);
    }

    public bool IsEnabled => _options.Enabled;

    public async Task<IReadOnlyList<RecommendedItem>?> GetRecommendationsAsync(
        Guid userId,
        int limit,
        IReadOnlyList<Guid>? excludeVideoIds = null,
        CancellationToken ct = default)
    {
        if (!IsEnabled)
        {
            return null;
        }

        try
        {
            var payload = new InternalRecommendationRequest(
                UserId: userId.ToString(),
                Limit: limit,
                ExcludeItemIds: (excludeVideoIds ?? []).Select(g => g.ToString()).ToList()
            );

            using var request = new HttpRequestMessage(HttpMethod.Post, "internal/recommendations")
            {
                Content = JsonContent.Create(payload)
            };

            if (!string.IsNullOrWhiteSpace(_options.ServiceToken))
            {
                request.Headers.Add("X-Service-Token", _options.ServiceToken);
            }

            using var response = await _http.SendAsync(request, ct);

            if (response.IsSuccessStatusCode)
            {
                var result = await response.Content.ReadFromJsonAsync<InternalRecommendationResponse>(JsonOptions, ct);
                if (result?.Items == null || result.Items.Count == 0)
                {
                    return Array.Empty<RecommendedItem>();
                }

                var items = new List<RecommendedItem>(result.Items.Count);
                foreach (var dto in result.Items)
                {
                    if (Guid.TryParse(dto.ItemId, out var videoId))
                    {
                        items.Add(new RecommendedItem(
                            VideoId: videoId,
                            Score: dto.Score,
                            ModelVersion: result.ModelVersion ?? "unknown",
                            Source: result.Source ?? "CF"
                        ));
                    }
                }
                return items;
            }

            if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            {
                _logger.LogDebug("User {UserId} not present in CF recommendation model. Falling back to default feed.", userId);
                return null;
            }

            if (response.StatusCode == System.Net.HttpStatusCode.ServiceUnavailable)
            {
                _logger.LogWarning("CF recommendation service model is not ready (503). Falling back to default feed.");
                return null;
            }

            var errBody = await response.Content.ReadAsStringAsync(ct);
            _logger.LogWarning("CF recommendation service returned HTTP {StatusCode}: {Error}. Falling back.", response.StatusCode, errBody);
            return null;
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            _logger.LogWarning("CF recommendation service call timed out after {Timeout}s. Falling back to default feed.", _options.TimeoutSeconds);
            return null;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to call CF recommendation service. Falling back to default feed.");
            return null;
        }
    }
}
