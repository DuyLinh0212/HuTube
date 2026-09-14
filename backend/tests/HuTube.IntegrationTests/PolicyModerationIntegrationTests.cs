using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Application.Policies;
using HuTube.Application.Taxonomy;
using HuTube.Application.Users;
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
    public async Task SuperAdmin_CanManageTopicsAndTags()
    {
        var (admin, _) = await CreateUserAsync("taxonomy_admin", SystemRoles.SuperAdmin);
        var suffix = Guid.NewGuid().ToString("N")[..10];
        var topicSlug = "topic-" + suffix;

        var createTopic = await admin.PostAsJsonAsync("/api/v1/admin/topics", new
        {
            name = "Chủ đề kiểm thử " + suffix,
            slug = topicSlug,
            description = "Mô tả chủ đề kiểm thử",
            status = "active"
        });
        Assert.Equal(HttpStatusCode.Created, createTopic.StatusCode);
        var topic = await createTopic.Content.ReadFromJsonAsync<AdminTopicResponse>(JsonOptions);
        Assert.NotNull(topic);
        Assert.Equal(topicSlug, topic.Slug);
        Assert.Equal(0, topic.VideoCount);

        var allTopics = await admin.GetAsync("/api/v1/admin/topics?status=all");
        Assert.Equal(HttpStatusCode.OK, allTopics.StatusCode);
        var topicRows = await allTopics.Content.ReadFromJsonAsync<List<AdminTopicResponse>>(JsonOptions);
        Assert.Contains(topicRows!, row => row.CategoryId == topic.CategoryId);

        var updateTopic = await admin.PutAsJsonAsync($"/api/v1/admin/topics/{topic.CategoryId}", new
        {
            name = "Chủ đề kiểm thử đã sửa " + suffix,
            slug = topicSlug + "-updated",
            description = "Mô tả mới",
            status = "active"
        });
        Assert.Equal(HttpStatusCode.OK, updateTopic.StatusCode);
        var updatedTopic = await updateTopic.Content.ReadFromJsonAsync<AdminTopicResponse>(JsonOptions);
        Assert.NotNull(updatedTopic);
        Assert.Equal(topicSlug + "-updated", updatedTopic.Slug);

        var archiveTopic = await admin.PostAsync($"/api/v1/admin/topics/{topic.CategoryId}/archive", null);
        Assert.Equal(HttpStatusCode.NoContent, archiveTopic.StatusCode);

        var createTag = await admin.PostAsJsonAsync("/api/v1/admin/tags", new { name = "#Tag-" + suffix });
        Assert.Equal(HttpStatusCode.Created, createTag.StatusCode);
        var tag = await createTag.Content.ReadFromJsonAsync<AdminTagResponse>(JsonOptions);
        Assert.NotNull(tag);
        Assert.Equal("tag-" + suffix.ToLowerInvariant(), tag.Name);

        var findTag = await admin.GetAsync($"/api/v1/admin/tags?search={Uri.EscapeDataString(suffix)}");
        Assert.Equal(HttpStatusCode.OK, findTag.StatusCode);
        var tagRows = await findTag.Content.ReadFromJsonAsync<List<AdminTagResponse>>(JsonOptions);
        Assert.Contains(tagRows!, row => row.TagId == tag.TagId);

        var updateTag = await admin.PutAsJsonAsync($"/api/v1/admin/tags/{tag.TagId}", new { name = "updated-" + suffix });
        Assert.Equal(HttpStatusCode.OK, updateTag.StatusCode);
        var updatedTag = await updateTag.Content.ReadFromJsonAsync<AdminTagResponse>(JsonOptions);
        Assert.NotNull(updatedTag);
        Assert.Equal("updated-" + suffix, updatedTag.Name);

        var deleteTag = await admin.DeleteAsync($"/api/v1/admin/tags/{tag.TagId}");
        Assert.Equal(HttpStatusCode.NoContent, deleteTag.StatusCode);
    }

    [Fact]
    public async Task SuperAdmin_CanInspectAndLockUnlockUser()
    {
        var (admin, _) = await CreateUserAsync("user_admin", SystemRoles.SuperAdmin);
        var (_, targetId) = await CreateUserAsync("managed_user", SystemRoles.Moderator);
        await using (var db = factory.CreateDb())
        {
            await db.Users.Where(user => user.UserId == targetId)
                .ExecuteUpdateAsync(update => update.SetProperty(user => user.RoleId, SystemRoles.User));
        }

        var listResponse = await admin.GetAsync("/api/v1/admin/users?search=managed_user&page=1&pageSize=10");
        Assert.Equal(HttpStatusCode.OK, listResponse.StatusCode);
        var list = await listResponse.Content.ReadFromJsonAsync<AdminUserListResponse>(JsonOptions);
        Assert.NotNull(list);
        var row = Assert.Single(list.Items, item => item.UserId == targetId);
        Assert.Equal("active", row.Status);

        var detailResponse = await admin.GetAsync($"/api/v1/admin/users/{targetId}");
        Assert.Equal(HttpStatusCode.OK, detailResponse.StatusCode);
        var detail = await detailResponse.Content.ReadFromJsonAsync<AdminUserDetailResponse>(JsonOptions);
        Assert.NotNull(detail);
        Assert.Equal(targetId, detail.UserId);
        Assert.Equal("user", detail.RoleCode);

        var lockResponse = await admin.PostAsJsonAsync($"/api/v1/admin/users/{targetId}/lock", new
        {
            reason = "Khóa tài khoản để kiểm thử quản trị",
            notify = false
        });
        Assert.Equal(HttpStatusCode.OK, lockResponse.StatusCode);
        var locked = await lockResponse.Content.ReadFromJsonAsync<AdminUserDetailResponse>(JsonOptions);
        Assert.NotNull(locked);
        Assert.Equal("banned", locked.Status);
        Assert.Contains(locked.AuditHistory, item => item.Action == "admin.user_locked");

        var unlockResponse = await admin.PostAsJsonAsync($"/api/v1/admin/users/{targetId}/unlock", new
        {
            reason = "Mở khóa sau khi kiểm thử quản trị",
            notify = false
        });
        Assert.Equal(HttpStatusCode.OK, unlockResponse.StatusCode);
        var unlocked = await unlockResponse.Content.ReadFromJsonAsync<AdminUserDetailResponse>(JsonOptions);
        Assert.NotNull(unlocked);
        Assert.Equal("active", unlocked.Status);
        Assert.Contains(unlocked.AuditHistory, item => item.Action == "admin.user_unlocked");
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
        Assert.Equal("https://storage.test/videos/video.mp4", item.VideoUrl);
        Assert.Equal("https://storage.test/video-thumbnails/thumb.jpg", item.ThumbnailUrl);
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
            UploadedByUserId = ownerId,
            Title = "Video moderation " + suffix,
            Description = "Mô tả moderation",
            VideoUrl = "test://videos/video.mp4",
            ThumbnailUrl = "test://video-thumbnails/thumb.jpg",
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
