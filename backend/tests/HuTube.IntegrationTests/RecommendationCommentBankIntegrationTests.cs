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

public sealed class RecommendationCommentBankIntegrationTests(AuthApiFactory factory) : IClassFixture<AuthApiFactory>
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

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task SimulationCommentsOnlyUseTheVideoCategoryBank(bool emptyMusicBank)
    {
        // Arrange: three videos with distinct category membership and distinguishable templates.
        var (super, actorId) = await LoginAsync(SystemRoles.SuperAdmin);
        using var client = super;
        var created = await client.PostAsJsonAsync("/api/v1/admin/recommendations/bots", new { count = 1, prefix = "banktest" });
        created.EnsureSuccessStatusCode();
        var bot = (await created.Content.ReadFromJsonAsync<List<AdminUserOption>>())!.Single();
        var daily = new Category { CategoryId = Guid.NewGuid(), Name = "Daily fixture", Slug = "daily-" + Guid.NewGuid().ToString("N") };
        var music = new Category { CategoryId = Guid.NewGuid(), Name = "Music fixture", Slug = "music-" + Guid.NewGuid().ToString("N") };
        var channel = new Channel { OwnerUserId = actorId, Name = "Comment bank fixture", Handle = "bank-" + Guid.NewGuid().ToString("N")[..12] };
        Video VideoFor(Guid? categoryId) => new() {
            ChannelId = channel.ChannelId, UploadedByUserId = actorId, CategoryId = categoryId,
            Title = "Comment bank video", Duration = 60, FileSize = 1024, VideoUrl = "test://comment-bank",
            Status = "published", ModerationStatus = "approved", Visibility = "public", PublishedAt = DateTimeOffset.UtcNow,
        };
        var dailyVideo = VideoFor(daily.CategoryId);
        var musicVideo = VideoFor(music.CategoryId);
        var uncategorizedVideo = VideoFor(null);
        await using (var db = factory.CreateDb())
        {
            db.Categories.AddRange(daily, music); db.Channels.Add(channel); await db.SaveChangesAsync();
            db.Videos.AddRange(dailyVideo, musicVideo, uncategorizedVideo); await db.SaveChangesAsync();
        }
        var musicTemplates = emptyMusicBank ? Array.Empty<string>()
            : Enumerable.Range(1, 300).Select(i => $"Music template only {i}").ToArray();
        var request = new SimulatorRequest([bot.UserId], [dailyVideo.VideoId, musicVideo.VideoId, uncategorizedVideo.VideoId],
            "target", 3, 0, null, 0, 0, 0, 0, 100, 0, ["Shared bank must never be used"], false,
            CategoryComments: [new(daily.CategoryId, ["Daily template only"]),
                new(music.CategoryId, musicTemplates)]);
        var legacy = request with { CategoryComments = null };

        // Act: mixed-category requests from old clients fail clearly instead of mixing templates.
        var rejected = await client.PostAsJsonAsync("/api/v1/admin/recommendations/simulation-jobs", legacy);
        Assert.Equal(HttpStatusCode.BadRequest, rejected.StatusCode);
        var accepted = await client.PostAsJsonAsync("/api/v1/admin/recommendations/simulation-jobs", request);
        Assert.True(accepted.StatusCode == HttpStatusCode.Accepted, await accepted.Content.ReadAsStringAsync());
        var jobId = (await accepted.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("jobId").GetGuid();
        RecommendationJob? job = null;
        for (var attempt = 0; attempt < 60; attempt++)
        {
            await Task.Delay(500);
            job = await client.GetFromJsonAsync<RecommendationJob>($"/api/v1/admin/recommendations/jobs/{jobId}");
            if (job?.Status is "completed" or "failed") break;
        }

        // Assert against real PostgreSQL comments, not just the serialized request.
        Assert.NotNull(job); Assert.Equal("completed", job.Status);
        var storedRequest = JsonSerializer.Deserialize<SimulatorRequest>(job.PayloadJson,
            new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Assert.Equal(musicTemplates, Assert.Single(storedRequest!.CategoryComments!, bank => bank.CategoryId == music.CategoryId).Templates);
        await using var verify = factory.CreateDb();
        var comments = await verify.Comments.Where(x => x.UserId == bot.UserId).ToListAsync();
        Assert.Equal(emptyMusicBank ? 1 : 2, comments.Count);
        Assert.Equal("Daily template only", Assert.Single(comments, x => x.VideoId == dailyVideo.VideoId).Content);
        if (!emptyMusicBank)
            Assert.Contains(Assert.Single(comments, x => x.VideoId == musicVideo.VideoId).Content, musicTemplates);
        else Assert.DoesNotContain(comments, x => x.VideoId == musicVideo.VideoId);
        Assert.DoesNotContain(comments, x => x.VideoId == uncategorizedVideo.VideoId);
        Assert.DoesNotContain(comments, x => x.Content.Contains("Shared bank"));
    }

}
