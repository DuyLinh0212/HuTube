using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using HuTube.Application.Account;
using HuTube.Application.Auth;
using HuTube.Infrastructure.Account;
using Microsoft.AspNetCore.Hosting;
using Microsoft.EntityFrameworkCore;

namespace HuTube.IntegrationTests;

public sealed class FeedbackSurveyApiFactory : AuthApiFactory
{
    public const string SurveySecret = "hutube-survey-integration-secret-at-least-32-chars";
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        base.ConfigureWebHost(builder);
        builder.UseSetting("FeedbackSurvey:Enabled", "true");
        builder.UseSetting("FeedbackSurvey:TokenEntryId", "123456");
        builder.UseSetting("FeedbackSurvey:WebhookSecret", SurveySecret);
    }
}

public sealed class FeedbackSurveyIntegrationTests(FeedbackSurveyApiFactory factory) : IClassFixture<FeedbackSurveyApiFactory>
{
    private const string StatusUrl = "/api/v1/feedback-survey";

    [Fact]
    public async Task Submission_CompletesOnlyLinkedUserAndPreservesFirstCompletionOnRetry()
    {
        var (client, userId) = await CreateUserAsync();
        var (other, otherUserId) = await CreateUserAsync();
        var status = (await client.GetFromJsonAsync<FeedbackSurveyStatus>(StatusUrl))!;
        Assert.True(status.Enabled);
        Assert.False(status.HasCompleted);
        Assert.Contains("&entry.819508883=", status.FormUrl);
        var query = Microsoft.AspNetCore.WebUtilities.QueryHelpers.ParseQuery(new Uri(status.FormUrl!).Query);
        var token = query["entry.123456"].ToString();
        Assert.True(new FeedbackSurveySecurity(new FeedbackSurveyOptions { TokenEntryId = "123456", WebhookSecret = FeedbackSurveyApiFactory.SurveySecret }).TryReadToken(token, out var linkedId));
        Assert.Equal(userId, linkedId);

        // A link/status request alone must not mark the survey complete.
        Assert.False((await client.GetFromJsonAsync<FeedbackSurveyStatus>(StatusUrl))!.HasCompleted);
        var submittedAt = DateTimeOffset.UtcNow.AddMinutes(-1);
        var submission = new FeedbackSurveySubmission(FeedbackSurveyOptions.PublicFormId, token, "google-response-1", submittedAt);
        Assert.Equal(HttpStatusCode.NoContent, (await SendAsync(submission)).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await SendAsync(submission with { SubmittedAt = DateTimeOffset.UtcNow })).StatusCode);

        status = (await client.GetFromJsonAsync<FeedbackSurveyStatus>(StatusUrl))!;
        Assert.True(status.HasCompleted);
        Assert.Null(status.FormUrl);
        Assert.NotNull(status.CompletedAt);
        Assert.True(Math.Abs((status.CompletedAt.Value - submittedAt).TotalMilliseconds) < 1);
        Assert.False((await other.GetFromJsonAsync<FeedbackSurveyStatus>(StatusUrl))!.HasCompleted);
        await using var db = factory.CreateDb();
        Assert.NotNull((await db.Users.SingleAsync(x => x.UserId == userId)).FeedbackSurveyCompletedAt);
        Assert.Null((await db.Users.SingleAsync(x => x.UserId == otherUserId)).FeedbackSurveyCompletedAt);
    }

    [Fact]
    public async Task Submission_RejectsUnsignedForgedAndWrongFormCallbacks()
    {
        var (client, _) = await CreateUserAsync();
        var status = (await client.GetFromJsonAsync<FeedbackSurveyStatus>(StatusUrl))!;
        var query = Microsoft.AspNetCore.WebUtilities.QueryHelpers.ParseQuery(new Uri(status.FormUrl!).Query);
        var token = query["entry.123456"].ToString();
        var submission = new FeedbackSurveySubmission(FeedbackSurveyOptions.PublicFormId, token, "response-2", DateTimeOffset.UtcNow);
        using var anonymous = factory.CreateClient(new() { HandleCookies = false });
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync(StatusUrl)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.PostAsJsonAsync(StatusUrl + "/google-form-submission", submission)).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await SendAsync(submission with { FormId = "another-form" })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await SendAsync(submission with { SurveyToken = Guid.NewGuid().ToString("N") + token[32..] })).StatusCode);
        Assert.False((await client.GetFromJsonAsync<FeedbackSurveyStatus>(StatusUrl))!.HasCompleted);
    }

    private async Task<(HttpClient Client, Guid UserId)> CreateUserAsync()
    {
        var client = factory.CreateClient(new() { HandleCookies = false });
        var name = "survey_" + Guid.NewGuid().ToString("N");
        var email = name + "@example.com";
        (await client.PostAsJsonAsync("/api/v1/auth/register", new { username = name, email, displayName = "Người dùng khảo sát", password = "CorrectHorse42!" })).EnsureSuccessStatusCode();
        (await client.PostAsJsonAsync("/api/v1/auth/verify-email", new { token = factory.Emails.Token(email) })).EnsureSuccessStatusCode();
        var loginResponse = await client.PostAsJsonAsync("/api/v1/auth/login", new { email, password = "CorrectHorse42!", platform = "mobile", deviceName = "Survey test" });
        loginResponse.EnsureSuccessStatusCode();
        var login = (await loginResponse.Content.ReadFromJsonAsync<LoginResponse>())!;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login.AccessToken);
        return (client, login.User.UserId);
    }

    private async Task<HttpResponseMessage> SendAsync(FeedbackSurveySubmission submission)
    {
        var body = JsonSerializer.Serialize(submission, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
        var signature = "sha256=" + Convert.ToHexStringLower(HMACSHA256.HashData(
            Encoding.UTF8.GetBytes(FeedbackSurveyApiFactory.SurveySecret), Encoding.UTF8.GetBytes(timestamp + "." + body)));
        using var request = new HttpRequestMessage(HttpMethod.Post, StatusUrl + "/google-form-submission") { Content = new StringContent(body, Encoding.UTF8, "application/json") };
        request.Headers.Add("X-HuTube-Survey-Timestamp", timestamp);
        request.Headers.Add("X-HuTube-Survey-Signature", signature);
        using var client = factory.CreateClient(new() { HandleCookies = false });
        return await client.SendAsync(request);
    }
}
