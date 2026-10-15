using System.Net;
using System.Text.Json;

namespace HuTube.Infrastructure.Recommendations;

internal static class RecommendationWakeupPolicy
{
    public const int DefaultTimeoutSeconds = 90;

    public static TimeSpan GetTimeout(int timeoutSeconds) =>
        TimeSpan.FromSeconds(Math.Clamp(
            timeoutSeconds > 0 ? timeoutSeconds : DefaultTimeoutSeconds,
            1,
            120));

    public static TimeSpan GetRetryDelay(int attempt)
    {
        var exponent = Math.Clamp(attempt - 1, 0, 3);
        return TimeSpan.FromSeconds(1 << exponent);
    }

    public static bool IsTransientStartupResponse(HttpStatusCode statusCode, string responseBody)
    {
        if (statusCode is HttpStatusCode.BadGateway or HttpStatusCode.GatewayTimeout)
            return true;

        if (statusCode != HttpStatusCode.ServiceUnavailable)
            return false;

        if (string.IsNullOrWhiteSpace(responseBody))
            return true;

        try
        {
            using var document = JsonDocument.Parse(responseBody);
            var detail = document.RootElement;
            if (detail.ValueKind == JsonValueKind.Object
                && detail.TryGetProperty("detail", out var nestedDetail))
            {
                detail = nestedDetail;
            }

            if (detail.ValueKind == JsonValueKind.Object
                && detail.TryGetProperty("retryable", out var retryable)
                && retryable.ValueKind is JsonValueKind.True or JsonValueKind.False)
            {
                return retryable.GetBoolean();
            }

            // A valid service response without an explicit retryable flag is treated as
            // a permanent application error. Render's startup proxy responses are not JSON.
            return false;
        }
        catch (JsonException)
        {
            // Render may return a plain-text/HTML 503 while an instance is starting.
            return true;
        }
    }
}
