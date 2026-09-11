using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Application.Channels;
using HuTube.Application.Videos;
using Microsoft.AspNetCore.Hosting;
using Xunit;

namespace HuTube.IntegrationTests;

public sealed class DisabledFeaturesApiFactory : AuthApiFactory
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        base.ConfigureWebHost(builder);
        builder.UseSetting("Features:ModerationEnabled", "false");
        builder.UseSetting("Features:PlanEnforcementEnabled", "false");
    }
}

public sealed class FeatureFlagIntegrationTests : IAsyncLifetime
{
    private readonly DisabledFeaturesApiFactory _factory = new();
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    public Task InitializeAsync() => ((IAsyncLifetime)_factory).InitializeAsync();
    public Task DisposeAsync() => ((IAsyncLifetime)_factory).DisposeAsync();

    [Fact]
    public async Task DisabledModerationAndPlan_BypassesPlanButLocksPublicVisibility()
    {
        var (client, channelId) = await CreateUserAndChannelAsync();

        var preflight = await client.PostAsJsonAsync("/api/v1/videos/upload-preflight", new
            { channelId, fileSize = 1024, duration = 60, contentType = "video/mp4", sourceQuality = "2160p" });
        using var publicForm = UploadForm(channelId, "public");
        var publicUpload = await client.PostAsync("/api/v1/videos", publicForm);
        using var privateForm = UploadForm(channelId, "private");
        var privateUpload = await client.PostAsync("/api/v1/videos", privateForm);
        var video = await privateUpload.Content.ReadFromJsonAsync<VideoResponse>(JsonOptions);
        var moderation = await client.PostAsync($"/api/v1/videos/{video!.VideoId}/submit-moderation", null);

        Assert.Equal(HttpStatusCode.OK, preflight.StatusCode);
        Assert.Equal("2160p", (await preflight.Content.ReadFromJsonAsync<UploadPreflightResponse>(JsonOptions))!.MaxQuality);
        Assert.Equal(HttpStatusCode.Conflict, publicUpload.StatusCode);
        Assert.Equal(HttpStatusCode.Created, privateUpload.StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, moderation.StatusCode);
    }

    private async Task<(HttpClient Client, Guid ChannelId)> CreateUserAndChannelAsync()
    {
        var client = _factory.CreateClient(); client.DefaultRequestHeaders.Add("X-HuTube-Client", "web");
        var suffix = Guid.NewGuid().ToString("N"); var email = $"flags_{suffix}@example.com";
        (await client.PostAsJsonAsync("/api/v1/auth/register", new RegisterRequest($"flags_{suffix}", email, "Flags User", "Password123!"))).EnsureSuccessStatusCode();
        (await client.PostAsJsonAsync("/api/v1/auth/verify-email", new TokenRequest(_factory.Emails.Token(email)))).EnsureSuccessStatusCode();
        var login = await client.PostAsJsonAsync("/api/v1/auth/login", new LoginRequest(email, "Password123!", "web", "Test"));
        var auth = await login.Content.ReadFromJsonAsync<LoginResponse>(JsonOptions); client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", auth!.AccessToken);
        var channelResponse = await client.PostAsJsonAsync("/api/v1/channels", new CreateChannelRequest("Kênh flags", $"flags-{suffix}", null));
        var channel = await channelResponse.Content.ReadFromJsonAsync<ChannelResponse>(JsonOptions);
        return (client, channel!.ChannelId);
    }

    private static MultipartFormDataContent UploadForm(Guid channelId, string visibility)
    {
        var form = new MultipartFormDataContent(); form.Add(new StringContent(channelId.ToString()), "ChannelId");
        form.Add(new StringContent("Video feature flags"), "Title"); form.Add(new StringContent(visibility), "Visibility");
        form.Add(new StringContent("60"), "Duration"); form.Add(new StringContent("720p"), "SourceQuality");
        var content = new ByteArrayContent(Encoding.UTF8.GetBytes("fake-video")); content.Headers.ContentType = new MediaTypeHeaderValue("video/mp4");
        form.Add(content, "Video", "flags.mp4"); return form;
    }
}
