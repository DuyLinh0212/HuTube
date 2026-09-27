using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Domain.Channels;
using HuTube.Domain.Rbac;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Recommendations;
using Microsoft.AspNetCore.Hosting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace HuTube.IntegrationTests;

public sealed class RecommendationModelFactory : AuthApiFactory
{
    public FakeModelHttpFactory ModelHttp { get; }
    public RecommendationModelFactory() => ModelHttp = new FakeModelHttpFactory(Snapshots);

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        base.ConfigureWebHost(builder);
        builder.UseSetting("Recommendation:ServiceUrl", "http://recommender.test");
        builder.UseSetting("Recommendation:AdminToken", "model-admin-test");
        builder.ConfigureServices(services => {
            services.RemoveAll<IHttpClientFactory>();
            services.AddSingleton<IHttpClientFactory>(ModelHttp);
        });
    }
}

public sealed class FakeModelHttpFactory(TestRecommendationSnapshots snapshots) : IHttpClientFactory
{
    public bool FailTraining { get; set; }
    public HttpClient CreateClient(string name) => new(new Handler(this, snapshots));

    private sealed class Handler(FakeModelHttpFactory parent, TestRecommendationSnapshots snapshots) : HttpMessageHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            if (request.Headers.GetValues("X-Model-Admin-Token").Single() != "model-admin-test")
                return new HttpResponseMessage(HttpStatusCode.Unauthorized);
            if (request.Method == HttpMethod.Post)
            {
                if (parent.FailTraining)
                    return new HttpResponseMessage(HttpStatusCode.UnprocessableEntity) {
                        Content = new StringContent("training failed") };
                using var json = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(ct));
                var csvKey = json.RootElement.GetProperty("csvKey").GetString()!;
                var hash = json.RootElement.GetProperty("csvSha256").GetString()!;
                var active = new ModelManifest("fake-model-v1", csvKey, hash,
                    "collaborative_cf/artifacts/fake-model-v1.zip", "fake-artifact-hash", DateTimeOffset.UtcNow);
                snapshots.Objects["collaborative_cf/active.json"] =
                    JsonSerializer.SerializeToUtf8Bytes(active, new JsonSerializerOptions(JsonSerializerDefaults.Web));
                return new HttpResponseMessage(HttpStatusCode.Accepted) {
                    Content = JsonContent.Create(new { jobId = "test-job", status = "running" }) };
            }
            return new HttpResponseMessage(HttpStatusCode.OK) {
                Content = JsonContent.Create(new { jobId = "test-job", status = "completed" }) };
        }
    }
}

public sealed class RecommendationModelJobIntegrationTests(RecommendationModelFactory factory)
    : IClassFixture<RecommendationModelFactory>
{
    [Fact]
    public async Task ModelJobUploadsDatedCsvAndDoesNotReplaceManifestOnFailure()
    {
        var email = $"model_{Guid.NewGuid():N}@example.com";
        const string password = "Password123!";
        using (var register = factory.CreateClient())
        {
            register.DefaultRequestHeaders.Add("X-HuTube-Client", "web");
            (await register.PostAsJsonAsync("/api/v1/auth/register",
                new RegisterRequest($"model_{Guid.NewGuid():N}"[..20], email, "Model Test", password)))
                .EnsureSuccessStatusCode();
            (await register.PostAsJsonAsync("/api/v1/auth/verify-email",
                new TokenRequest(factory.Emails.Token(email)))).EnsureSuccessStatusCode();
        }
        Guid adminId;
        await using (var db = factory.CreateDb())
        {
            var admin = await db.Users.SingleAsync(x => x.Email == email);
            admin.RoleId = SystemRoles.SuperAdmin;
            adminId = admin.UserId;
            await db.SaveChangesAsync();
        }
        using var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-HuTube-Client", "web");
        client.DefaultRequestHeaders.Add("X-HuTube-App", "admin");
        var login = await client.PostAsJsonAsync("/api/v1/auth/login",
            new LoginRequest(email, password, "admin", "Model test"));
        login.EnsureSuccessStatusCode();
        var token = await login.Content.ReadFromJsonAsync<LoginResponse>();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token!.AccessToken);

        var botsResponse = await client.PostAsJsonAsync("/api/v1/admin/recommendations/bots",
            new { count = 2, prefix = "modelbot" });
        botsResponse.EnsureSuccessStatusCode();
        var bots = (await botsResponse.Content.ReadFromJsonAsync<List<AdminUserOption>>())!;
        var channel = new Channel { OwnerUserId = adminId,
            Name = "Model test", Handle = "model-" + Guid.NewGuid().ToString("N")[..12] };
        var first = new Video { ChannelId = channel.ChannelId, UploadedByUserId = adminId,
            Title = "Model item one", VideoUrl = "test://one", Duration = 120, FileSize = 1024,
            Status = "published", Visibility = "public", ModerationStatus = "approved",
            PublishedAt = DateTimeOffset.UtcNow };
        var second = new Video { ChannelId = channel.ChannelId, UploadedByUserId = adminId,
            Title = "Model item two", VideoUrl = "test://two", Duration = 120, FileSize = 1024,
            Status = "published", Visibility = "public", ModerationStatus = "approved",
            PublishedAt = DateTimeOffset.UtcNow };
        await using (var db = factory.CreateDb())
        {
            db.Channels.Add(channel); await db.SaveChangesAsync();
            db.Videos.AddRange(first, second); await db.SaveChangesAsync();
            db.ViewingHistories.AddRange(
                new ViewingHistory { UserId = bots[0].UserId, VideoId = first.VideoId, WatchDuration = 60, Progress = 50 },
                new ViewingHistory { UserId = bots[0].UserId, VideoId = second.VideoId, WatchDuration = 60, Progress = 50 },
                new ViewingHistory { UserId = bots[1].UserId, VideoId = first.VideoId, WatchDuration = 60, Progress = 50 });
            await db.SaveChangesAsync();
        }
        var queued = await client.PostAsJsonAsync("/api/v1/admin/recommendations/model-jobs", new { });
        Assert.Equal(HttpStatusCode.Accepted, queued.StatusCode);
        var jobId = (await queued.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("jobId").GetGuid();
        var completed = await AwaitJob(client, jobId);
        Assert.Equal("completed", completed.Status);
        var manifest = JsonSerializer.Deserialize<ModelManifest>(
            factory.Snapshots.Objects["collaborative_cf/active.json"],
            new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
        Assert.Matches(@"^collaborative_cf/\d{4}/\d{2}/\d{2}/interactions_\d{8}T\d{6}Z_[a-f0-9]{12}\.csv$", manifest.CsvKey);
        var csv = factory.Snapshots.Objects[manifest.CsvKey];
        Assert.Equal(Convert.ToHexString(SHA256.HashData(csv)).ToLowerInvariant(), manifest.CsvSha256);
        Assert.DoesNotContain("email", Encoding.UTF8.GetString(csv), StringComparison.OrdinalIgnoreCase);

        factory.ModelHttp.FailTraining = true;
        var failedQueue = await client.PostAsJsonAsync("/api/v1/admin/recommendations/model-jobs", new { });
        Assert.Equal(HttpStatusCode.Accepted, failedQueue.StatusCode);
        var failedId = (await failedQueue.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("jobId").GetGuid();
        Assert.Equal("failed", (await AwaitJob(client, failedId)).Status);
        Assert.Equal(manifest.CsvKey, JsonSerializer.Deserialize<ModelManifest>(
            factory.Snapshots.Objects["collaborative_cf/active.json"],
            new JsonSerializerOptions(JsonSerializerDefaults.Web))!.CsvKey);
    }

    private static async Task<RecommendationJob> AwaitJob(HttpClient client, Guid jobId)
    {
        for (var attempt = 0; attempt < 50; attempt++)
        {
            await Task.Delay(400);
            var job = await client.GetFromJsonAsync<RecommendationJob>($"/api/v1/admin/recommendations/jobs/{jobId}");
            if (job?.Status is "completed" or "failed") return job;
        }
        throw new TimeoutException("Recommendation job did not finish during the test.");
    }
}
