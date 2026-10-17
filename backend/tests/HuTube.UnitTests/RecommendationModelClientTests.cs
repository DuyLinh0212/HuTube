using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using HuTube.Infrastructure.Recommendations;
using Microsoft.Extensions.Logging.Abstractions;

namespace HuTube.UnitTests;

public sealed class RecommendationModelClientTests
{
    private const string JobId = "91c97536-74af-40d2-a57d-9ae957208abc";
    private static readonly ScoreAggregationConfig Scores = new("average", []);

    private static RecommendationModelClient Client(HttpClient http, int timeoutSeconds = 5) =>
        new(http, new RecommendationOptions {
            ServiceUrl = "https://recommender.test", AdminToken = "test-admin",
            TimeoutSeconds = timeoutSeconds
        }, NullLogger.Instance);

    [Theory]
    [InlineData(HttpStatusCode.BadGateway)]
    [InlineData(HttpStatusCode.ServiceUnavailable)]
    [InlineData(HttpStatusCode.GatewayTimeout)]
    public async Task SubmissionRetriesProxyStartupErrorsWithTheSameDurablePayload(HttpStatusCode startupStatus)
    {
        // Arrange
        var payloads = new List<string>();
        using var http = new HttpClient(new Handler(async (request, ct) => {
            Assert.Equal("/internal/model/train", request.RequestUri!.AbsolutePath);
            Assert.Equal("test-admin", request.Headers.GetValues("X-Model-Admin-Token").Single());
            payloads.Add(await request.Content!.ReadAsStringAsync(ct));
            return payloads.Count == 1
                ? new HttpResponseMessage(startupStatus) { Content = new StringContent("<!DOCTYPE html><title>502</title>") }
                : new HttpResponseMessage(HttpStatusCode.Accepted) { Content = JsonContent.Create(new { jobId = JobId }) };
        }));

        // Act
        var result = await Client(http).SubmitAsync(JobId, "collaborative_cf/test.csv", new string('a', 64),
            Scores, "item_based", CancellationToken.None);

        // Assert
        Assert.Equal(JobId, result);
        Assert.Equal(2, payloads.Count);
        Assert.Equal(payloads[0], payloads[1]);
        using var payload = JsonDocument.Parse(payloads[0]);
        Assert.Equal(JobId, payload.RootElement.GetProperty("jobId").GetString());
    }

    [Theory]
    [InlineData(HttpStatusCode.Unauthorized, "{}", "MODEL_ADMIN_TOKEN_MISMATCH")]
    [InlineData(HttpStatusCode.ServiceUnavailable, "{\"detail\":{\"message\":\"Storage is not configured\",\"retryable\":false}}", "Storage is not configured")]
    [InlineData(HttpStatusCode.UnprocessableEntity, "<!DOCTYPE html><style>large embedded font</style>", "HTTP 422")]
    public async Task SubmissionRejectsPermanentErrorsWithoutRetryingOrDisplayingProxyHtml(
        HttpStatusCode status, string body, string expectedMessage)
    {
        // Arrange
        var calls = 0;
        using var http = new HttpClient(new Handler((_, _) => {
            calls++;
            return Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent(body) });
        }));

        // Act
        var error = await Assert.ThrowsAsync<InvalidOperationException>(() => Client(http).SubmitAsync(
            JobId, "collaborative_cf/test.csv", new string('a', 64), Scores, "item_based", CancellationToken.None));

        // Assert
        Assert.Equal(1, calls);
        Assert.Contains(expectedMessage, error.Message);
        Assert.DoesNotContain("<!DOCTYPE", error.Message);
        Assert.DoesNotContain("embedded font", error.Message);
    }

    [Fact]
    public async Task StartupRetriesStopAtTheConfiguredDeadlineWithAnActionableMessage()
    {
        // Arrange
        using var http = new HttpClient(new Handler((_, _) => Task.FromResult(
            new HttpResponseMessage(HttpStatusCode.BadGateway) { Content = new StringContent("<html>proxy error</html>") })));

        // Act
        var error = await Assert.ThrowsAsync<InvalidOperationException>(() => Client(http, 1).SubmitAsync(
            JobId, "collaborative_cf/test.csv", new string('a', 64), Scores, "item_based", CancellationToken.None));

        // Assert
        Assert.Contains("MODEL_SERVICE_UNAVAILABLE", error.Message);
        Assert.DoesNotContain("<html>", error.Message);
    }

    [Fact]
    public async Task LostSubmissionResponseRetainsTheDurableIdForReconciliation()
    {
        // Arrange
        using var http = new HttpClient(new Handler((_, _) => throw new HttpRequestException("Connection reset")));

        // Act
        var result = await Client(http).SubmitAsync(JobId, "collaborative_cf/test.csv", new string('a', 64),
            Scores, "item_based", CancellationToken.None);

        // Assert
        Assert.Equal(JobId, result);
    }

    [Fact]
    public async Task CallerCancellationIsNotConvertedToAnUnknownSubmission()
    {
        // Arrange
        using var http = new HttpClient(new Handler((_, ct) => {
            ct.ThrowIfCancellationRequested();
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.Accepted));
        }));
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();

        // Act / Assert
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => Client(http).SubmitAsync(
            JobId, "collaborative_cf/test.csv", new string('a', 64), Scores, "item_based", cancelled.Token));
    }

    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> handle)
        : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) => handle(request, ct);
    }
}
