using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace HuTube.IntegrationTests;

public sealed class RateLimitIntegrationTests(AuthApiFactory factory) : IClassFixture<AuthApiFactory>
{
    [Fact]
    public async Task Search_RateLimitExceeded_ShouldReturnRetryContract()
    {
        await using var limited = factory.WithWebHostBuilder(builder =>
            builder.UseSetting("RateLimit:SearchPermitLimit", "2"));
        using var client = limited.CreateClient(new() { HandleCookies = false });

        await client.GetAsync("/api/v1/videos/search?q=rate-limit");
        await client.GetAsync("/api/v1/videos/search?q=rate-limit");
        var response = await client.GetAsync("/api/v1/videos/search?q=rate-limit");

        await AssertRateLimitResponseAsync(response);
    }

    [Fact]
    public async Task UploadPreflight_RateLimitExceeded_ShouldReturnRetryContract()
    {
        await using var limited = factory.WithWebHostBuilder(builder =>
            builder.UseSetting("RateLimit:UploadPreflightPermitLimit", "2"));
        using var client = limited.CreateClient(new() { HandleCookies = false });

        await client.PostAsJsonAsync("/api/v1/videos/upload-preflight", new { fileName = "video.mp4", fileSize = 1 });
        await client.PostAsJsonAsync("/api/v1/videos/upload-preflight", new { fileName = "video.mp4", fileSize = 1 });
        var response = await client.PostAsJsonAsync("/api/v1/videos/upload-preflight", new { fileName = "video.mp4", fileSize = 1 });

        await AssertRateLimitResponseAsync(response);
    }

    [Fact]
    public async Task PaymentWebhook_RateLimitExceeded_ShouldReturnRetryContract()
    {
        await using var limited = factory.WithWebHostBuilder(builder =>
            builder.UseSetting("RateLimit:PaymentWebhookPermitLimit", "2"));
        using var client = limited.CreateClient(new() { HandleCookies = false });

        await client.PostAsJsonAsync("/api/v1/payments/webhook/sepay", new { eventId = "rate-limit" });
        await client.PostAsJsonAsync("/api/v1/payments/webhook/sepay", new { eventId = "rate-limit" });
        var response = await client.PostAsJsonAsync("/api/v1/payments/webhook/sepay", new { eventId = "rate-limit" });

        await AssertRateLimitResponseAsync(response);
    }

    private static async Task AssertRateLimitResponseAsync(HttpResponseMessage response)
    {
        Assert.Equal(HttpStatusCode.TooManyRequests, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("RATE_LIMIT_EXCEEDED", body.GetProperty("code").GetString());
        Assert.NotNull(response.Headers.RetryAfter);
    }
}
