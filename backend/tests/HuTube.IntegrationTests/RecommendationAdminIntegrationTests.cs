using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Domain.Channels;
using HuTube.Domain.Rbac;
using HuTube.Domain.Users;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Recommendations;
using Microsoft.EntityFrameworkCore;

namespace HuTube.IntegrationTests;

public sealed class RecommendationAdminIntegrationTests(AuthApiFactory factory) : IClassFixture<AuthApiFactory>
{
    private async Task<(HttpClient Client, Guid UserId)> LoginAsync(Guid roleId)
    {
        var email = $"cf_{Guid.NewGuid():N}@example.com";
        var password = "Password123!";
        using (var register = factory.CreateClient())
        {
            register.DefaultRequestHeaders.Add("X-HuTube-Client", "web");
            (await register.PostAsJsonAsync("/api/v1/auth/register",
                new RegisterRequest($"cf_{Guid.NewGuid():N}"[..20], email, "CF Test", password)))
                .EnsureSuccessStatusCode();
            (await register.PostAsJsonAsync("/api/v1/auth/verify-email",
                new TokenRequest(factory.Emails.Token(email)))).EnsureSuccessStatusCode();
        }
        Guid userId;
        await using (var db = factory.CreateDb())
        {
            var user = await db.Users.SingleAsync(x => x.Email == email);
            user.RoleId = roleId; userId = user.UserId;
            await db.SaveChangesAsync();
        }
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-HuTube-Client", "web");
        client.DefaultRequestHeaders.Add("X-HuTube-App", "admin");
        var login = await client.PostAsJsonAsync("/api/v1/auth/login",
            new LoginRequest(email, password, "admin", "CF test"));
        login.EnsureSuccessStatusCode();
        var payload = await login.Content.ReadFromJsonAsync<LoginResponse>();
        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", payload!.AccessToken);
        return (client, userId);
    }

    [Fact]
    public async Task RecommendationEndpointsRequireLiveSuperAdminRole()
    {
        using var guest = factory.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await guest.GetAsync("/api/v1/admin/recommendations/users")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound,
            (await guest.GetAsync("/api/v1/simulator/users")).StatusCode);

        var (admin, _) = await LoginAsync(SystemRoles.Admin);
        using (admin)
            Assert.Equal(HttpStatusCode.Forbidden,
                (await admin.GetAsync("/api/v1/admin/recommendations/users")).StatusCode);

        var (super, userId) = await LoginAsync(SystemRoles.SuperAdmin);
        using (super)
        {
            Assert.Equal(HttpStatusCode.OK,
                (await super.GetAsync("/api/v1/admin/recommendations/users")).StatusCode);
            await using (var db = factory.CreateDb())
            {
                var user = await db.Users.SingleAsync(x => x.UserId == userId);
                user.RoleId = SystemRoles.Admin;
                await db.SaveChangesAsync();
            }
            Assert.Equal(HttpStatusCode.Forbidden,
                (await super.GetAsync("/api/v1/admin/recommendations/users")).StatusCode);
        }
    }

    [Fact]
    public async Task CreatingBotsDoesNotResetAnExistingAccount()
    {
        var (super, _) = await LoginAsync(SystemRoles.SuperAdmin);
        using (super)
        {
            var response = await super.PostAsJsonAsync("/api/v1/admin/recommendations/bots",
                new { count = 2, prefix = "cfbot" });
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            var oldRoute = await super.PostAsJsonAsync("/api/v1/admin/cf-seeder/viewers", new { accounts = new object[0] });
            Assert.Equal(HttpStatusCode.NotFound, oldRoute.StatusCode);
            await using var db = factory.CreateDb();
            Assert.Equal(2, await db.Users.CountAsync(x => x.Username.StartsWith("cfbot_")));
            Assert.Contains(await db.AuditLogs.ToListAsync(), x => x.Action == "recommendations.bots_created");
        }
    }

    [Fact]
    public async Task MatrixDiffCountsAddedChangedAndRemovedPairs()
    {
        var (super, actorId) = await LoginAsync(SystemRoles.SuperAdmin);
        using (super)
        {
            var created = await super.PostAsJsonAsync("/api/v1/admin/recommendations/bots",
                new { count = 2, prefix = "matrixbot" });
            created.EnsureSuccessStatusCode();
            var bots = (await created.Content.ReadFromJsonAsync<List<AdminUserOption>>())!;
            var channel = new Channel { OwnerUserId = actorId,
                Name = "Matrix test", Handle = "matrix-" + Guid.NewGuid().ToString("N")[..12] };
            var first = new Video { ChannelId = channel.ChannelId, UploadedByUserId = actorId,
                Title = "First matrix video", Duration = 120, FileSize = 1024, VideoUrl = "test://first",
                Status = "published", ModerationStatus = "approved", Visibility = "public",
                PublishedAt = DateTimeOffset.UtcNow };
            var second = new Video { ChannelId = channel.ChannelId, UploadedByUserId = actorId,
                Title = "Second matrix video", Duration = 120, FileSize = 1024, VideoUrl = "test://second",
                Status = "published", ModerationStatus = "approved", Visibility = "public",
                PublishedAt = DateTimeOffset.UtcNow };
            await using (var db = factory.CreateDb())
            {
                db.Channels.Add(channel);
                await db.SaveChangesAsync();
                db.Videos.AddRange(first, second);
                await db.SaveChangesAsync();
                db.ViewingHistories.Add(new ViewingHistory { UserId = bots[0].UserId,
                    VideoId = first.VideoId, WatchDuration = 60, Progress = 50 });
                db.VideoReactions.Add(new VideoReaction { UserId = bots[0].UserId,
                    VideoId = second.VideoId, Type = "like" });
                await db.SaveChangesAsync();
            }
            var csvKey = "collaborative_cf/2026/09/26/old.csv";
            var oldCsv = Encoding.UTF8.GetBytes(
                "user_id,video_id,watch_ratio,like,dislike,rating,comment_count,subscribed,score\n" +
                $"{bots[0].UserId},{first.VideoId},0.2,0,0,,0,0,3\n" +
                $"{bots[1].UserId},{second.VideoId},0.5,0,0,,0,0,3.5\n");
            var manifest = new ModelManifest("test-model", csvKey,
                Convert.ToHexString(SHA256.HashData(oldCsv)).ToLowerInvariant(),
                "collaborative_cf/artifacts/test.zip", "0", DateTimeOffset.UtcNow);
            factory.Snapshots.Objects[csvKey] = oldCsv;
            factory.Snapshots.Objects["collaborative_cf/active.json"] =
                JsonSerializer.SerializeToUtf8Bytes(manifest, new JsonSerializerOptions(JsonSerializerDefaults.Web));

            var response = await super.GetAsync("/api/v1/admin/recommendations/status");
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            var diff = await response.Content.ReadFromJsonAsync<MatrixDiffResponse>();
            Assert.NotNull(diff);
            Assert.Equal(1, diff.Added);
            Assert.Equal(1, diff.Changed);
            Assert.Equal(1, diff.Removed);
            Assert.Equal(1.5, diff.ChangeRate);

            var preview = await super.GetFromJsonAsync<MatrixPreviewResponse>(
                "/api/v1/admin/recommendations/matrix-preview");
            Assert.NotNull(preview);
            Assert.Equal(diff.Current.Pairs, preview.Total);
            Assert.Contains(preview.Rows, row => row[0] == bots[0].UserId.ToString()
                && row[1] == first.VideoId.ToString());

            var export = await super.GetStringAsync("/api/v1/admin/recommendations/matrix.csv");
            Assert.Contains($"{bots[0].UserId},{first.VideoId},0.5", export);
            Assert.DoesNotContain("email", export, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("password", export, StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public async Task SimulationUsesExistingServicesAndPreservesBotCredentials()
    {
        var (super, actorId) = await LoginAsync(SystemRoles.SuperAdmin);
        using (super)
        {
            var created = await super.PostAsJsonAsync("/api/v1/admin/recommendations/bots",
                new { count = 1, prefix = "simtest" });
            created.EnsureSuccessStatusCode();
            var bot = (await created.Content.ReadFromJsonAsync<List<AdminUserOption>>())!.Single();
            var channel = new Channel { OwnerUserId = actorId,
                Name = "Simulation test", Handle = "sim-" + Guid.NewGuid().ToString("N")[..12] };
            var video = new Video { ChannelId = channel.ChannelId, UploadedByUserId = actorId,
                Title = "Simulation test video", Duration = 120, FileSize = 1024,
                VideoUrl = "test://simulation", Status = "published", ModerationStatus = "approved",
                Visibility = "public", PublishedAt = DateTimeOffset.UtcNow };
            string originalHash;
            await using (var db = factory.CreateDb())
            {
                originalHash = await db.Users.Where(x => x.UserId == bot.UserId).Select(x => x.PasswordHash).SingleAsync();
                db.Channels.Add(channel); await db.SaveChangesAsync();
                db.Videos.Add(video); await db.SaveChangesAsync();
            }
            var payload = new {
                userIds = new[] { bot.UserId }, videoIds = new[] { video.VideoId },
                mode = "target", actionsPerUser = 1, delayMs = 0, watchPercent = 75,
                viewRate = 100, likeRate = 100, dislikeRate = 0, ratingRate = 100,
                commentRate = 100, subscribeRate = 100,
                commentTemplates = new[] { "Very useful video" }, confirmRealUsers = false
            };
            var denied = await super.PostAsJsonAsync("/api/v1/admin/recommendations/simulation-jobs",
                new { userIds = new[] { actorId }, payload.videoIds, payload.mode,
                    payload.actionsPerUser, payload.delayMs, payload.watchPercent,
                    payload.viewRate, payload.likeRate,
                    payload.dislikeRate, payload.ratingRate, payload.commentRate, payload.subscribeRate,
                    payload.commentTemplates, confirmRealUsers = false });
            Assert.Equal(HttpStatusCode.BadRequest, denied.StatusCode);
            var accepted = await super.PostAsJsonAsync("/api/v1/admin/recommendations/simulation-jobs", payload);
            Assert.True(accepted.StatusCode == HttpStatusCode.Accepted,
                await accepted.Content.ReadAsStringAsync());
            var jobId = (await accepted.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("jobId").GetGuid();
            RecommendationJob? job = null;
            for (var attempt = 0; attempt < 30; attempt++)
            {
                await Task.Delay(500);
                job = await super.GetFromJsonAsync<RecommendationJob>($"/api/v1/admin/recommendations/jobs/{jobId}");
                if (job?.Status is "completed" or "failed") break;
            }
            Assert.NotNull(job);
            Assert.Equal("completed", job.Status);
            await using var verify = factory.CreateDb();
            Assert.Equal(originalHash, await verify.Users.Where(x => x.UserId == bot.UserId).Select(x => x.PasswordHash).SingleAsync());
            Assert.True(await verify.ViewingHistories.AnyAsync(x => x.UserId == bot.UserId && x.VideoId == video.VideoId));
            Assert.True(await verify.VideoReactions.AnyAsync(x => x.UserId == bot.UserId && x.VideoId == video.VideoId && x.Type == "like"));
            Assert.True(await verify.VideoRatings.AnyAsync(x => x.UserId == bot.UserId && x.VideoId == video.VideoId));
            Assert.True(await verify.Comments.AnyAsync(x => x.UserId == bot.UserId && x.VideoId == video.VideoId));
            Assert.True(await verify.Subscriptions.AnyAsync(x => x.UserId == bot.UserId && x.ChannelId == channel.ChannelId));
            Assert.True(await verify.AuditLogs.AnyAsync(x => x.ActorUserId == actorId && x.Action == "recommendations.simulated_view"));
        }
    }
}
