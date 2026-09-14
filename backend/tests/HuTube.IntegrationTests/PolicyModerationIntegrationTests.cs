using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Application.Policies;
using HuTube.Application.Videos;
using HuTube.Domain.Channels;
using HuTube.Domain.Rbac;
using HuTube.Domain.Videos;
using Microsoft.EntityFrameworkCore;

namespace HuTube.IntegrationTests;

public sealed class PolicyModerationIntegrationTests(AuthApiFactory factory) : IClassFixture<AuthApiFactory>
{
    private const string Password = "Password123!";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    [Fact]
    public async Task PublicPolicies_ShouldExposeSeededRows_AndAdminPolicyRequiresPermission()
    {
        var publicClient = factory.CreateClient();
        var publicResponse = await publicClient.GetAsync("/api/v1/policies");
        Assert.Equal(HttpStatusCode.OK, publicResponse.StatusCode);

        var policies = await publicResponse.Content.ReadFromJsonAsync<List<PolicyDto>>(JsonOptions);
        Assert.NotNull(policies);
        Assert.True(policies.Count >= 33);
        Assert.Contains(policies, policy => policy.Code == "CHILD_SAFETY" && policy.Status == "published");
        Assert.Contains(policies, policy => policy.Group == "enforcement");

        var (moderator, _) = await CreateUserAsync("policy_moderator", SystemRoles.Moderator);
        Assert.Equal(HttpStatusCode.Forbidden, (await moderator.GetAsync("/api/v1/admin/policies")).StatusCode);

        var (superAdmin, _) = await CreateUserAsync("policy_super_admin", SystemRoles.SuperAdmin);
        var adminResponse = await superAdmin.GetAsync("/api/v1/admin/policies?status=published");
        Assert.Equal(HttpStatusCode.OK, adminResponse.StatusCode);
        var adminPolicies = await adminResponse.Content.ReadFromJsonAsync<List<PolicyDto>>(JsonOptions);
        Assert.NotNull(adminPolicies);
        Assert.Contains(adminPolicies, policy => policy.Code == "CHILD_SAFETY");
    }

    [Fact]
    public async Task SuperAdmin_CanCreateAndPublishPolicy()
    {
        var (client, _) = await CreateUserAsync("policy_writer", SystemRoles.SuperAdmin);
        var code = "TEST_POLICY_" + Guid.NewGuid().ToString("N")[..12].ToUpperInvariant();

        var createResponse = await client.PostAsJsonAsync("/api/v1/admin/policies", new
        {
            code,
            name = "Chính sách kiểm thử",
            group = "guidelines",
            content = "Nội dung policy kiểm thử.",
            severity = "medium",
            version = "1.0",
            status = "draft"
        });

        Assert.Equal(HttpStatusCode.Created, createResponse.StatusCode);
        var created = await createResponse.Content.ReadFromJsonAsync<PolicyDto>(JsonOptions);
        Assert.NotNull(created);
        Assert.Equal(code, created.Code);
        Assert.Equal("draft", created.Status);

        var publishResponse = await client.PutAsJsonAsync($"/api/v1/admin/policies/{created.PolicyId}/publish", new
        {
            name = "Chính sách kiểm thử đã publish",
            group = "guidelines",
            content = "Nội dung policy kiểm thử đã cập nhật.",
            severity = "high",
            status = "published",
            version = "1.1"
        });

        Assert.Equal(HttpStatusCode.OK, publishResponse.StatusCode);
        var published = await publishResponse.Content.ReadFromJsonAsync<PolicyDto>(JsonOptions);
        Assert.NotNull(published);
        Assert.Equal("published", published.Status);
        Assert.Equal("1.1", published.Version);
        Assert.Equal("high", published.Severity);
    }

    [Fact]
    public async Task Moderator_CanViewQueue()
    {
        var (moderator, _) = await CreateUserAsync("moderation_moderator", SystemRoles.Moderator);

        var queueResponse = await moderator.GetAsync("/api/v1/admin/moderation/queue");
        Assert.Equal(HttpStatusCode.OK, queueResponse.StatusCode);
    }

    [Theory]
    [InlineData("approve")]
    [InlineData("age_restricted")]
    [InlineData("recommendation_restricted")]
    [InlineData("reject")]
    [InlineData("escalate")]
    public async Task SuperAdmin_CanClaimAndResolveCase_WithWireDecision(string decision)
    {
        var (admin, ownerId) = await CreateUserAsync("moderation_admin", SystemRoles.SuperAdmin);
        var caseId = await SeedModerationCaseAsync(ownerId, decision);

        var queueResponse = await admin.GetAsync("/api/v1/admin/moderation/queue?status=pending");
        Assert.Equal(HttpStatusCode.OK, queueResponse.StatusCode);
        var queue = await queueResponse.Content.ReadFromJsonAsync<List<ModerationQueueItemResponse>>(JsonOptions);
        var item = Assert.Single(queue!, x => x.ModerationCaseId == caseId);
        Assert.Equal("Video moderation "+decision, item.Title);
        Assert.Equal("Mô tả moderation", item.Description);
        Assert.Equal(125, item.Duration);
        Assert.Equal("high", item.RiskLevel);

        var claimResponse = await admin.PostAsync($"/api/v1/admin/moderation/{caseId}/claim", null);
        Assert.Equal(HttpStatusCode.OK, claimResponse.StatusCode);

        var policyCode = decision is "age_restricted" or "recommendation_restricted" or "reject"
            ? "SEXUAL_CONTENT"
            : null;
        var request = new ResolveModerationRequest(decision, policyCode, "Lý do kiểm thử", "Ghi chú nội bộ");
        var resolveResponse = await admin.PostAsJsonAsync($"/api/v1/admin/moderation/{caseId}/resolve", request);
        Assert.Equal(HttpStatusCode.OK, resolveResponse.StatusCode);

        var result = await resolveResponse.Content.ReadFromJsonAsync<ModerationDecisionResponse>(JsonOptions);
        Assert.NotNull(result);
        Assert.Equal(caseId, result.ModerationCaseId);
        Assert.Equal(decision, result.Decision);
        Assert.Equal(policyCode, result.PolicyCode);

        await using var db = factory.CreateDb();
        var moderationCase = await db.ModerationCases.SingleAsync(x => x.ModerationCaseId == caseId);
        var video = await db.Videos.SingleAsync(x => x.VideoId == moderationCase.VideoId);
        Assert.Equal(decision, moderationCase.Decision);

        if (decision is "approve" or "age_restricted" or "recommendation_restricted")
        {
            Assert.Equal("approved", moderationCase.Status);
            Assert.Equal("published", video.Status);
            Assert.Equal("approved", video.ModerationStatus);
        }
        else if (decision == "reject")
        {
            Assert.Equal("rejected", moderationCase.Status);
            Assert.Equal("blocked", video.Status);
            Assert.Equal("rejected", video.ModerationStatus);
        }
        else
        {
            Assert.Equal("escalated", moderationCase.Status);
            Assert.Equal("pending", video.ModerationStatus);
        }

        if (decision == "age_restricted") Assert.True(video.AgeRestricted);
        if (decision == "recommendation_restricted") Assert.Contains("recommendation_restricted", video.Metadata);
    }

    [Fact]
    public async Task Moderation_ShouldRejectPascalCaseDecisionValues()
    {
        var (admin, ownerId) = await CreateUserAsync("moderation_wire", SystemRoles.SuperAdmin);
        var caseId = await SeedModerationCaseAsync(ownerId, "wire");
        var response = await admin.PostAsJsonAsync(
            $"/api/v1/admin/moderation/{caseId}/resolve",
            new { decision = "AgeRestricted", policyCode = "SEXUAL_CONTENT", reason = "Không đúng wire contract" });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(JsonOptions);
        Assert.Equal("INVALID_DECISION", body.GetProperty("code").GetString());
    }

    private async Task<(HttpClient Client, Guid UserId)> CreateUserAsync(string prefix, Guid roleId)
    {
        var email = $"{prefix}_{Guid.NewGuid():N}@example.com";
        var username = $"{prefix}_{Guid.NewGuid():N}"[..20];
        var registrationClient = factory.CreateClient();
        registrationClient.DefaultRequestHeaders.Add("X-HuTube-Client", "web");

        (await registrationClient.PostAsJsonAsync(
            "/api/v1/auth/register",
            new RegisterRequest(username, email, "Integration Admin", Password))).EnsureSuccessStatusCode();
        (await registrationClient.PostAsJsonAsync(
            "/api/v1/auth/verify-email",
            new TokenRequest(factory.Emails.Token(email)))).EnsureSuccessStatusCode();

        await using (var db = factory.CreateDb())
        {
            await db.Users.Where(user => user.Email == email)
                .ExecuteUpdateAsync(update => update.SetProperty(user => user.RoleId, roleId));
        }

        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-HuTube-Client", "web");
        client.DefaultRequestHeaders.Add("X-HuTube-App", "admin");
        var login = await client.PostAsJsonAsync(
            "/api/v1/auth/login",
            new LoginRequest(email, Password, "admin", "Policy moderation integration test"));
        login.EnsureSuccessStatusCode();
        var loginResponse = (await login.Content.ReadFromJsonAsync<LoginResponse>(JsonOptions))!;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", loginResponse.AccessToken);
        return (client, loginResponse.User.UserId);
    }

    private async Task<Guid> SeedModerationCaseAsync(Guid ownerId, string suffix)
    {
        await using var db = factory.CreateDb();
        var now = DateTimeOffset.UtcNow;
        var channel = new Channel
        {
            OwnerUserId = ownerId,
            Name = "Kênh moderation " + suffix,
            Handle = "moderation-" + suffix + "-" + Guid.NewGuid().ToString("N")[..8],
            Description = "Kênh kiểm thử moderation",
            CreatedAt = now,
            UpdatedAt = now
        };
        var video = new Video
        {
            ChannelId = channel.ChannelId,
            Title = "Video moderation " + suffix,
            Description = "Mô tả moderation",
            VideoUrl = "https://storage.test/video.mp4",
            Duration = 125,
            FileSize = 100,
            Visibility = "public",
            Status = "processing",
            ModerationStatus = "pending",
            Metadata = "{}",
            CreatedAt = now,
            UpdatedAt = now
        };
        var moderationCase = new ModerationCase
        {
            VideoId = video.VideoId,
            CaseType = "upload_review",
            Status = "pending",
            RiskLevel = "high",
            SubmittedAt = now,
            UpdatedAt = now
        };

        db.Channels.Add(channel);
        await db.SaveChangesAsync();
        db.Videos.Add(video);
        await db.SaveChangesAsync();
        db.ModerationCases.Add(moderationCase);
        await db.SaveChangesAsync();
        return moderationCase.ModerationCaseId;
    }
}
