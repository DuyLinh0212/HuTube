using System.Net.Http.Json;
using System.Text.Json;
using HuTube.Application.Recommendations;
using Microsoft.Extensions.Logging;

namespace HuTube.Infrastructure.Recommendations;

public sealed class RecommendationOptions
{
    public string ServiceUrl { get; set; } = "http://127.0.0.1:8000";
    public string ServiceToken { get; set; } = "";
    public string AdminToken { get; set; } = "";
    public int TimeoutSeconds { get; set; } = RecommendationWakeupPolicy.DefaultTimeoutSeconds;
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
        // The linked token below bounds the entire wake-up and retry sequence.
        _http.Timeout = Timeout.InfiniteTimeSpan;
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

            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeoutCts.CancelAfter(RecommendationWakeupPolicy.GetTimeout(_options.TimeoutSeconds));
            var retryAttempt = 0;

            while (true)
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, "internal/recommendations")
                {
                    Content = JsonContent.Create(payload)
                };

                if (!string.IsNullOrWhiteSpace(_options.ServiceToken))
                {
                    request.Headers.Add("X-Service-Token", _options.ServiceToken);
                }

                using var response = await _http.SendAsync(request, timeoutCts.Token);

                if (response.IsSuccessStatusCode)
                {
                    var result = await response.Content.ReadFromJsonAsync<InternalRecommendationResponse>(JsonOptions, timeoutCts.Token);
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

                var errBody = await response.Content.ReadAsStringAsync(timeoutCts.Token);
                if (response.StatusCode == System.Net.HttpStatusCode.BadGateway)
                {
                    // Render Free can answer the first POST with a gateway 502 while
                    // the instance is asleep. A GET to the health endpoint is held
                    // until the instance has started, so wait for that before retrying
                    // the inference request instead of repeatedly POSTing into the 502.
                    if (!await WaitForServiceHealthAsync(timeoutCts.Token))
                    {
                        return null;
                    }

                    retryAttempt = 0;
                    continue;
                }

                if (RecommendationWakeupPolicy.IsTransientStartupResponse(response.StatusCode, errBody))
                {
                    retryAttempt++;
                    var delay = RecommendationWakeupPolicy.GetRetryDelay(retryAttempt);
                    _logger.LogInformation(
                        "Recommendation Service returned HTTP {StatusCode} while starting. Retrying in {Delay} (attempt {Attempt}).",
                        response.StatusCode, delay, retryAttempt);
                    await Task.Delay(delay, timeoutCts.Token);
                    continue;
                }

                if (response.StatusCode == System.Net.HttpStatusCode.ServiceUnavailable)
                {
                    _logger.LogWarning("CF recommendation service model is not ready (503): {Error}. Falling back to default feed.", errBody);
                    return null;
                }

                _logger.LogWarning("CF recommendation service returned HTTP {StatusCode}: {Error}. Falling back.", response.StatusCode, errBody);
                return null;
            }
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

    private async Task<bool> WaitForServiceHealthAsync(CancellationToken ct)
    {
        var attempt = 0;
        while (!ct.IsCancellationRequested)
        {
            using var response = await _http.GetAsync("health", ct);
            if (response.IsSuccessStatusCode)
            {
                _logger.LogInformation("Recommendation Service health check succeeded after startup.");
                return true;
            }

            var body = await response.Content.ReadAsStringAsync(ct);
            if (response.StatusCode is not (System.Net.HttpStatusCode.BadGateway
                or System.Net.HttpStatusCode.ServiceUnavailable))
            {
                _logger.LogWarning(
                    "Recommendation Service health check returned HTTP {StatusCode}: {Error}.",
                    response.StatusCode, body);
                return false;
            }

            attempt++;
            var delay = RecommendationWakeupPolicy.GetRetryDelay(attempt);
            _logger.LogInformation(
                "Recommendation Service health check returned HTTP {StatusCode} while starting. Retrying in {Delay} (attempt {Attempt}).",
                response.StatusCode, delay, attempt);
            await Task.Delay(delay, ct);
        }

        return false;
    }
}
