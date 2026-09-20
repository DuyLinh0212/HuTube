using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Application.Channels;
using HuTube.Application.Videos;
using HuTube.Domain.Videos;
using Microsoft.EntityFrameworkCore;

namespace HuTube.IntegrationTests;

public sealed class SearchAndFilterIntegrationTests(AuthApiFactory factory) : IClassFixture<AuthApiFactory>
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    [Fact]
    public async Task Search_ByKeyword_MatchesTitleChannelDescriptionAndTags()
    {
        // Arrange
        var (client, _, channelId) = await CreateUserAndChannelAsync("search_kw");
        var uniqueMarker = Guid.NewGuid().ToString("N")[..8];

        var v1 = await CreateCustomPublishedVideoAsync(client, channelId, $"Video Alpha {uniqueMarker}", "Mô tả bình thường", 100, ["music"]);
        var v2 = await CreateCustomPublishedVideoAsync(client, channelId, "Video thông thường", $"Mô tả chứa từ khóa {uniqueMarker}", 150, ["vlog"]);
        var v3 = await CreateCustomPublishedVideoAsync(client, channelId, "Video du lịch", "Khám phá ẩm thực", 200, [$"tag-{uniqueMarker}"]);

        var anonymous = factory.CreateClient();

        // Act & Assert: Tìm theo tiêu đề
        var resTitle = await anonymous.GetFromJsonAsync<PageResult<VideoCardResponse>>($"/api/v1/videos/search?q={uniqueMarker}", JsonOptions);
        Assert.NotNull(resTitle);
        Assert.Contains(resTitle.Items, x => x.VideoId == v1.VideoId);
        Assert.Contains(resTitle.Items, x => x.VideoId == v2.VideoId);
        Assert.Contains(resTitle.Items, x => x.VideoId == v3.VideoId);

        // Tìm theo tag cụ thể
        var resTag = await anonymous.GetFromJsonAsync<PageResult<VideoCardResponse>>($"/api/v1/videos/search?tag=tag-{uniqueMarker}", JsonOptions);
        Assert.NotNull(resTag);
        Assert.Single(resTag.Items, x => x.VideoId == v3.VideoId);

        // Also test explore endpoint with q
        var resExplore = await anonymous.GetFromJsonAsync<PageResult<VideoCardResponse>>($"/api/v1/feed/explore?q={uniqueMarker}", JsonOptions);
        Assert.NotNull(resExplore);
        Assert.Contains(resExplore.Items, x => x.VideoId == v1.VideoId);
    }

    [Fact]
    public async Task Search_WithSpecialCharactersAndEmptyQuery_ReturnsSafely()
    {
        var anonymous = factory.CreateClient();

        // Query rỗng
        var resEmpty = await anonymous.GetAsync("/api/v1/videos/search?q=");
        Assert.Equal(HttpStatusCode.OK, resEmpty.StatusCode);

        // Chỉ có khoảng trắng
        var resSpaces = await anonymous.GetAsync("/api/v1/videos/search?q=%20%20%20");
        Assert.Equal(HttpStatusCode.OK, resSpaces.StatusCode);

        // Ký tự đặc biệt SQL / HTML
        var resSpecial = await anonymous.GetAsync("/api/v1/videos/search?q=%25_%27%22%3Cscript%3E");
        Assert.Equal(HttpStatusCode.OK, resSpecial.StatusCode);

        var data = await resSpecial.Content.ReadFromJsonAsync<PageResult<VideoCardResponse>>(JsonOptions);
        Assert.NotNull(data);
    }

    [Fact]
    public async Task Search_WithCombinedFilters_CategoryDurationAndDate()
    {
        // Arrange
        var (client, _, channelId) = await CreateUserAndChannelAsync("search_comb");
        var uniqueMarker = Guid.NewGuid().ToString("N")[..8];

        Guid categoryId;
        await using (var db = factory.CreateDb())
        {
            var cat = await db.Categories.FirstOrDefaultAsync(x => x.Status == "active");
            if (cat == null)
            {
                cat = new Category { CategoryId = Guid.NewGuid(), Name = "Âm nhạc", Slug = $"music-{uniqueMarker}", Status = "active", CreatedAt = DateTimeOffset.UtcNow, UpdatedAt = DateTimeOffset.UtcNow };
                db.Categories.Add(cat);
                await db.SaveChangesAsync();
            }
            categoryId = cat.CategoryId;
        }

        // Short video (< 4 mins = 120s), with category
        var shortVideo = await CreateCustomPublishedVideoAsync(client, channelId, $"Short Video {uniqueMarker}", "Mô tả", 120, ["short"], categoryId);
        // Medium video (4-20 mins = 600s), with category
        var mediumVideo = await CreateCustomPublishedVideoAsync(client, channelId, $"Medium Video {uniqueMarker}", "Mô tả", 600, ["medium"], categoryId);
        // Long video (> 20 mins = 1500s), no category
        var longVideo = await CreateCustomPublishedVideoAsync(client, channelId, $"Long Video {uniqueMarker}", "Mô tả", 1500, ["long"]);

        var anonymous = factory.CreateClient();

        // Act 1: Lọc category + duration=short
        var resShort = await anonymous.GetFromJsonAsync<PageResult<VideoCardResponse>>(
            $"/api/v1/videos/search?q={uniqueMarker}&categoryId={categoryId}&duration=short", JsonOptions);

        Assert.NotNull(resShort);
        Assert.Contains(resShort.Items, x => x.VideoId == shortVideo.VideoId);
        Assert.DoesNotContain(resShort.Items, x => x.VideoId == mediumVideo.VideoId);
        Assert.DoesNotContain(resShort.Items, x => x.VideoId == longVideo.VideoId);

        // Act 2: Lọc duration=long
        var resLong = await anonymous.GetFromJsonAsync<PageResult<VideoCardResponse>>(
            $"/api/v1/videos/search?q={uniqueMarker}&duration=long", JsonOptions);

        Assert.NotNull(resLong);
        Assert.Contains(resLong.Items, x => x.VideoId == longVideo.VideoId);
        Assert.DoesNotContain(resLong.Items, x => x.VideoId == shortVideo.VideoId);

        // Act 3: Lọc dateRange=today
        var resToday = await anonymous.GetFromJsonAsync<PageResult<VideoCardResponse>>(
            $"/api/v1/videos/search?q={uniqueMarker}&dateRange=today", JsonOptions);

        Assert.NotNull(resToday);
        Assert.Contains(resToday.Items, x => x.VideoId == shortVideo.VideoId);
    }

    [Fact]
    public async Task Search_StrictlyExcludesNonPublicVideos()
    {
        // Arrange
        var (client, _, channelId) = await CreateUserAndChannelAsync("search_sec");
        var uniqueMarker = Guid.NewGuid().ToString("N")[..8];

        // 1. Video công khai đã duyệt
        var publicVideo = await CreateCustomPublishedVideoAsync(client, channelId, $"Public {uniqueMarker}", "Public", 100, ["safe"]);

        // 2. Video riêng tư
        var privateVideo = await UploadAsync(client, channelId, $"Private {uniqueMarker}", "private");

        // 3. Video bị từ chối kiểm duyệt (moderation_status = rejected)
        var rejectedVideo = await UploadAsync(client, channelId, $"Rejected {uniqueMarker}", "public");
        await using (var db = factory.CreateDb())
        {
            await db.Videos.Where(x => x.VideoId == rejectedVideo.VideoId)
                .ExecuteUpdateAsync(x => x.SetProperty(v => v.ModerationStatus, "rejected"));
        }

        var anonymous = factory.CreateClient();

        // Act: Tìm kiếm
        var searchResult = await anonymous.GetFromJsonAsync<PageResult<VideoCardResponse>>(
            $"/api/v1/videos/search?q={uniqueMarker}", JsonOptions);

        // Assert: Chỉ có video công khai đã duyệt
        Assert.NotNull(searchResult);
        Assert.Contains(searchResult.Items, x => x.VideoId == publicVideo.VideoId);
        Assert.DoesNotContain(searchResult.Items, x => x.VideoId == privateVideo.VideoId);
        Assert.DoesNotContain(searchResult.Items, x => x.VideoId == rejectedVideo.VideoId);
    }

    [Fact]
    public async Task Search_PaginationAndSorting()
    {
        // Arrange
        var (client, _, channelId) = await CreateUserAndChannelAsync("search_page");
        var uniqueMarker = Guid.NewGuid().ToString("N")[..8];

        var v1 = await CreateCustomPublishedVideoAsync(client, channelId, $"Paging {uniqueMarker} A", "Mô tả", 100, []);
        var v2 = await CreateCustomPublishedVideoAsync(client, channelId, $"Paging {uniqueMarker} B", "Mô tả", 120, []);

        var anonymous = factory.CreateClient();

        // Act: Page 1 with pageSize 1
        var page1 = await anonymous.GetFromJsonAsync<PageResult<VideoCardResponse>>(
            $"/api/v1/videos/search?q={uniqueMarker}&page=1&pageSize=1&sort=newest", JsonOptions);

        Assert.NotNull(page1);
        Assert.Single(page1.Items);
        Assert.Equal(1, page1.Page);
        Assert.Equal(1, page1.PageSize);
        Assert.True(page1.Total >= 2);

        // Page 2 with pageSize 1
        var page2 = await anonymous.GetFromJsonAsync<PageResult<VideoCardResponse>>(
            $"/api/v1/videos/search?q={uniqueMarker}&page=2&pageSize=1&sort=newest", JsonOptions);

        Assert.NotNull(page2);
        Assert.Single(page2.Items);
        Assert.NotEqual(page1.Items[0].VideoId, page2.Items[0].VideoId);
    }

    private async Task<(HttpClient Client, Guid UserId, Guid ChannelId)> CreateUserAndChannelAsync(string prefix)
    {
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-HuTube-Client", "web");
        var suffix = Guid.NewGuid().ToString("N")[..8];
        var email = $"{prefix}_{suffix}@example.com";
        var username = $"{prefix}_{suffix}"[..Math.Min(40, prefix.Length + 1 + suffix.Length)];
        (await client.PostAsJsonAsync("/api/v1/auth/register", new RegisterRequest(username, email, "Test User", "Password123!"))).EnsureSuccessStatusCode();
        (await client.PostAsJsonAsync("/api/v1/auth/verify-email", new TokenRequest(factory.Emails.Token(email)))).EnsureSuccessStatusCode();
        var login = await client.PostAsJsonAsync("/api/v1/auth/login", new LoginRequest(email, "Password123!", "web", "Test"));
        login.EnsureSuccessStatusCode();
        var auth = await login.Content.ReadFromJsonAsync<LoginResponse>(JsonOptions);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", auth!.AccessToken);
        Guid userId;
        await using (var db = factory.CreateDb()) userId = await db.Users.Where(x => x.Email == email).Select(x => x.UserId).SingleAsync();
        var channelResponse = await client.PostAsJsonAsync("/api/v1/channels", new CreateChannelRequest($"Kênh {prefix}", $"{prefix}-{suffix}"[..Math.Min(48, prefix.Length + 1 + suffix.Length)], "Kênh kiểm thử"));
        channelResponse.EnsureSuccessStatusCode();
        var channel = await channelResponse.Content.ReadFromJsonAsync<ChannelResponse>(JsonOptions);
        return (client, userId, channel!.ChannelId);
    }

    private async Task<VideoResponse> UploadAsync(HttpClient client, Guid channelId, string title, string visibility = "public", int duration = 120, string[]? tags = null, Guid? categoryId = null)
    {
        using var form = new MultipartFormDataContent();
        form.Add(new StringContent(channelId.ToString()), "ChannelId");
        form.Add(new StringContent(title), "Title");
        form.Add(new StringContent("Mô tả video kiểm thử"), "Description");
        form.Add(new StringContent(visibility), "Visibility");
        form.Add(new StringContent(duration.ToString()), "Duration");
        if (categoryId.HasValue) form.Add(new StringContent(categoryId.Value.ToString()), "CategoryId");
        foreach (var tag in tags ?? ["hu-tube"]) form.Add(new StringContent(tag), "Tags");
        var bytes = new ByteArrayContent(Encoding.UTF8.GetBytes("fake-video-content"));
        bytes.Headers.ContentType = new MediaTypeHeaderValue("video/mp4");
        form.Add(bytes, "Video", "sample.mp4");
        var response = await client.PostAsync("/api/v1/videos", form);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<VideoResponse>(JsonOptions))!;
    }

    private async Task<VideoResponse> CreateCustomPublishedVideoAsync(HttpClient client, Guid channelId, string title, string description, int duration, string[] tags, Guid? categoryId = null)
    {
        using var form = new MultipartFormDataContent();
        form.Add(new StringContent(channelId.ToString()), "ChannelId");
        form.Add(new StringContent(title), "Title");
        form.Add(new StringContent(description), "Description");
        form.Add(new StringContent("public"), "Visibility");
        form.Add(new StringContent(duration.ToString()), "Duration");
        if (categoryId.HasValue) form.Add(new StringContent(categoryId.Value.ToString()), "CategoryId");
        foreach (var tag in tags) form.Add(new StringContent(tag), "Tags");
        var bytes = new ByteArrayContent(Encoding.UTF8.GetBytes("fake-video-content"));
        bytes.Headers.ContentType = new MediaTypeHeaderValue("video/mp4");
        form.Add(bytes, "Video", "sample.mp4");
        var response = await client.PostAsync("/api/v1/videos", form);
        response.EnsureSuccessStatusCode();
        var video = (await response.Content.ReadFromJsonAsync<VideoResponse>(JsonOptions))!;

        await client.PostAsync($"/api/v1/videos/{video.VideoId}/submit-moderation", null);
        await using (var db = factory.CreateDb())
        {
            await db.Videos.Where(x => x.VideoId == video.VideoId).ExecuteUpdateAsync(x => x.SetProperty(v => v.ModerationStatus, "approved"));
            await db.ModerationCases.Where(x => x.VideoId == video.VideoId).ExecuteUpdateAsync(x => x.SetProperty(v => v.Status, "approved").SetProperty(v => v.ResolvedAt, DateTimeOffset.UtcNow));
        }
        var publish = await client.PostAsync($"/api/v1/videos/{video.VideoId}/publish", null);
        publish.EnsureSuccessStatusCode();
        return (await publish.Content.ReadFromJsonAsync<VideoResponse>(JsonOptions))!;
    }
}
