using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace HuTube.Infrastructure.Recommendations;

public sealed class RecommendationModelClient(
    HttpClient client, RecommendationOptions options, ILogger logger)
{
    public async Task<string> SubmitAsync(string jobId, string csvKey, string csvSha256,
        ScoreAggregationConfig scoreAggregation, string modelAlgorithm, CancellationToken ct)
    {
        using var startup = CancellationTokenSource.CreateLinkedTokenSource(ct);
        startup.CancelAfter(RecommendationWakeupPolicy.GetTimeout(options.TimeoutSeconds));
        var retryAttempt = 0;
        try
        {
            while (true)
            {
                // Reuse the durable ID and payload: the service deduplicates a
                // submission even if a proxy lost the original response.
                using var request = new HttpRequestMessage(HttpMethod.Post,
                    options.ServiceUrl.TrimEnd('/') + "/internal/model/train") {
                    Content = JsonContent.Create(new { jobId, csvKey, csvSha256,
                        scoreAggregation, modelAlgorithm }) };
                request.Headers.Add("X-Model-Admin-Token", options.AdminToken);
                HttpResponseMessage response;
                try { response = await client.SendAsync(request, startup.Token); }
                catch (Exception ex) when (!ct.IsCancellationRequested
                    && ex is HttpRequestException or OperationCanceledException)
                {
                    logger.LogWarning(ex, "Model submission outcome is unknown for {JobId}; polling its durable ID.", jobId);
                    return jobId;
                }
                using (response)
                {
                    var body = await response.Content.ReadAsStringAsync(startup.Token);
                    if (response.StatusCode == HttpStatusCode.Unauthorized)
                        throw new InvalidOperationException("MODEL_ADMIN_TOKEN_MISMATCH: Recommendation__AdminToken của API phải trùng RECOMMENDER_ADMIN_TOKEN của Recommendation Service. Kiểm tra cấu hình và khởi động lại cả hai dịch vụ.");
                    if (!response.IsSuccessStatusCode)
                    {
                        if (RecommendationWakeupPolicy.IsTransientStartupResponse(response.StatusCode, body))
                        {
                            var delay = RecommendationWakeupPolicy.GetRetryDelay(++retryAttempt);
                            logger.LogInformation("Recommendation Service returned HTTP {StatusCode}; retrying model submission {JobId} in {Delay} (attempt {Attempt}).",
                                response.StatusCode, jobId, delay, retryAttempt);
                            await Task.Delay(delay, startup.Token);
                            continue;
                        }
                        throw Failure(response.StatusCode, body);
                    }
                    using var submitted = JsonDocument.Parse(body);
                    return submitted.RootElement.GetProperty("jobId").GetString()
                        ?? throw new InvalidOperationException("Recommendation Service did not return a job ID.");
                }
            }
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            throw new InvalidOperationException("MODEL_SERVICE_UNAVAILABLE: Dịch vụ mô hình chưa sẵn sàng. Vui lòng thử cập nhật lại sau.");
        }
    }

    internal static InvalidOperationException Failure(HttpStatusCode status, string body)
    {
        // Render proxy pages can contain HTML, CSS and embedded fonts. Keep
        // those out of persisted job errors displayed by the admin UI.
        string? message = null;
        try
        {
            using var document = JsonDocument.Parse(body);
            var detail = document.RootElement;
            if (detail.ValueKind == JsonValueKind.Object && detail.TryGetProperty("detail", out var nested))
                detail = nested;
            if (detail.ValueKind == JsonValueKind.Object && detail.TryGetProperty("message", out var text))
                detail = text;
            if (detail.ValueKind == JsonValueKind.String) message = detail.GetString();
        }
        catch (JsonException) { }
        return new InvalidOperationException($"Recommendation Service trả HTTP {(int)status}. "
            + (string.IsNullOrWhiteSpace(message) ? "Vui lòng kiểm tra log dịch vụ và thử lại."
                : message[..Math.Min(500, message.Length)]));
    }
}
