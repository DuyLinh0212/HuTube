using System.Net.Http.Headers;
using System.Net.Http.Json;
using HuTube.Application.Auth;
using HuTube.Application.Recommendations;
using HuTube.Application.Videos;
using HuTube.Domain.Channels;
using HuTube.Domain.Videos;
using Microsoft.AspNetCore.Hosting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace HuTube.IntegrationTests;

public sealed class FakeRecommendations : IRecommendationClient
{
    public bool IsEnabled => true;
    public Guid Viewed { get; set; }
    public Guid Candidate { get; set; }
    public IReadOnlyList<Guid>? LastExcluded { get; private set; }
    public int Calls { get; private set; }
    public Task<IReadOnlyList<RecommendedItem>?> GetRecommendationsAsync(Guid userId, int limit,
        IReadOnlyList<Guid>? excludeVideoIds = null, CancellationToken ct = default)
    {
        Calls++;
        LastExcluded = excludeVideoIds;
        IReadOnlyList<RecommendedItem> items = [
            new(Viewed, 5, "fake-v1", "CF"),
            new(Candidate, 4, "fake-v1", "CF")
        ];
        return Task.FromResult<IReadOnlyList<RecommendedItem>?>(items);
    }
}

public sealed class RecommendationFeedFactory : AuthApiFactory
{
    public FakeRecommendations Recommender { get; } = new();
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        base.ConfigureWebHost(builder);
        builder.ConfigureServices(services => {
            services.RemoveAll<IRecommendationClient>();
            services.AddSingleton<IRecommendationClient>(Recommender);
        });
    }
}

public sealed class RecommendationFeedIntegrationTests(RecommendationFeedFactory factory)
    : IClassFixture<RecommendationFeedFactory>
{
    [Fact]
    public async Task ViewedVideoIsExcludedFromCfAndFallbackOnEveryPage()
    {
        var email = $"feed_{Guid.NewGuid():N}@example.com";
        const string password = "Password123!";
        using (var register = factory.CreateClient())
        {
            register.DefaultRequestHeaders.Add("X-HuTube-Client", "web");
            (await register.PostAsJsonAsync("/api/v1/auth/register",
                new RegisterRequest($"feed_{Guid.NewGuid():N}"[..20], email, "Feed Test", password)))
                .EnsureSuccessStatusCode();
            (await register.PostAsJsonAsync("/api/v1/auth/verify-email",
                new TokenRequest(factory.Emails.Token(email)))).EnsureSuccessStatusCode();
        }
        Guid userId;
        await using (var db = factory.CreateDb())
            userId = await db.Users.Where(x => x.Email == email).Select(x => x.UserId).SingleAsync();
        using var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-HuTube-Client", "web");
        var login = await client.PostAsJsonAsync("/api/v1/auth/login",
            new LoginRequest(email, password, "web", "Feed test"));
        login.EnsureSuccessStatusCode();
        var token = await login.Content.ReadFromJsonAsync<LoginResponse>();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token!.AccessToken);

        var channel = new Channel { OwnerUserId = userId,
            Name = "Feed test", Handle = "feed-" + Guid.NewGuid().ToString("N")[..12] };
        Video NewVideo(string title) => new() { ChannelId = channel.ChannelId, UploadedByUserId = userId,
            Title = title, VideoUrl = "test://video", Duration = 120, FileSize = 1024,
            Status = "published", Visibility = "public", ModerationStatus = "approved",
            PublishedAt = DateTimeOffset.UtcNow };
        var viewed = NewVideo("Already watched");
        var candidate = NewVideo("CF candidate");
        var fallback = NewVideo("Popular fallback");
        await using (var db = factory.CreateDb())
        {
            db.Channels.Add(channel); await db.SaveChangesAsync();
            db.Videos.AddRange(viewed, candidate, fallback); await db.SaveChangesAsync();
            db.ViewingHistories.Add(new ViewingHistory { UserId = userId,
                VideoId = viewed.VideoId, WatchDuration = 60, Progress = 50 });
            await db.SaveChangesAsync();
        }
        factory.Recommender.Viewed = viewed.VideoId;
        factory.Recommender.Candidate = candidate.VideoId;

        var first = await client.GetFromJsonAsync<PageResult<VideoCardResponse>>(
            "/api/v1/feed/recommended?page=1&pageSize=1");
        var second = await client.GetFromJsonAsync<PageResult<VideoCardResponse>>(
            "/api/v1/feed/recommended?page=2&pageSize=1");
        Assert.Equal(candidate.VideoId, first!.Items.Single().VideoId);
        Assert.Equal(fallback.VideoId, second!.Items.Single().VideoId);
        Assert.Contains(viewed.VideoId, factory.Recommender.LastExcluded!);
        Assert.DoesNotContain(viewed.VideoId, first.Items.Concat(second.Items).Select(x => x.VideoId));

        var callsBeforeResolve = factory.Recommender.Calls;
        var context = await client.GetFromJsonAsync<RecommendationContextResponse>(
            "/api/v1/feed/recommendation-context");
        Assert.Equal(userId, context!.UserId);
        Assert.Contains(viewed.VideoId, context.ExcludeItemIds);
        Assert.True(context.Enabled);

        var resolvedResponse = await client.PostAsJsonAsync("/api/v1/feed/resolve",
            new ResolveFeedRequest([viewed.VideoId, candidate.VideoId, candidate.VideoId], 1, 1));
        Assert.True(resolvedResponse.IsSuccessStatusCode, await resolvedResponse.Content.ReadAsStringAsync());
        var resolved = await resolvedResponse.Content.ReadFromJsonAsync<PageResult<VideoCardResponse>>();
        Assert.Equal(candidate.VideoId, resolved!.Items.Single().VideoId);
        var resolvedSecondResponse = await client.PostAsJsonAsync("/api/v1/feed/resolve",
            new ResolveFeedRequest([viewed.VideoId, candidate.VideoId], 2, 1));
        var resolvedSecond = await resolvedSecondResponse.Content.ReadFromJsonAsync<PageResult<VideoCardResponse>>();
        Assert.Equal(fallback.VideoId, resolvedSecond!.Items.Single().VideoId);
        var fallbackResponse = await client.PostAsJsonAsync("/api/v1/feed/resolve",
            new ResolveFeedRequest([], 1, 10));
        var resolvedFallback = await fallbackResponse.Content.ReadFromJsonAsync<PageResult<VideoCardResponse>>();
        Assert.DoesNotContain(viewed.VideoId, resolvedFallback!.Items.Select(x => x.VideoId));
        Assert.Equal(callsBeforeResolve, factory.Recommender.Calls);

        using var anonymous = factory.CreateClient();
        Assert.Equal(System.Net.HttpStatusCode.Unauthorized,
            (await anonymous.GetAsync("/api/v1/feed/recommendation-context")).StatusCode);
        Assert.Equal(System.Net.HttpStatusCode.Unauthorized,
            (await anonymous.PostAsJsonAsync("/api/v1/feed/resolve", new ResolveFeedRequest([]))).StatusCode);
        Assert.Equal(System.Net.HttpStatusCode.BadRequest,
            (await client.PostAsJsonAsync("/api/v1/feed/resolve",
                new ResolveFeedRequest(Enumerable.Repeat(candidate.VideoId, 101).ToArray()))).StatusCode);
    }
}
