using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Application.Channels;
using HuTube.Domain.Channels;
using HuTube.Domain.Rbac;
using HuTube.Domain.Users;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace HuTube.IntegrationTests;

public sealed class RbacAndChannelIntegrationTests(AuthApiFactory factory) : IClassFixture<AuthApiFactory>
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private async Task<(HttpClient Client, User User, string Token)> CreateUserAsync(string prefix, Guid? roleId = null)
    {
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-HuTube-Client", "web");

        var email = $"{prefix}_{Guid.NewGuid():N}@example.com";
        var username = $"{prefix}_{Guid.NewGuid():N}"[..20];
        var password = "Password123!";

        // Register
        var registerRes = await client.PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest(username, email, "Test User", password));
        registerRes.EnsureSuccessStatusCode();

        // Verify email
        var token = factory.Emails.Token(email);
        var verifyRes = await client.PostAsJsonAsync("/api/v1/auth/verify-email", new TokenRequest(token));
        verifyRes.EnsureSuccessStatusCode();

        // Assign role if specified
        await using var db = factory.CreateDb();
        var user = await db.Users.SingleAsync(u => u.Email == email);
        if (roleId.HasValue)
        {
            user.RoleId = roleId.Value;
            await db.SaveChangesAsync();
        }

        // Login
        var platform = roleId.HasValue && roleId.Value != UserRoles.User ? "admin" : "web";
        var loginClient = factory.CreateClient();
        loginClient.DefaultRequestHeaders.Add("X-HuTube-Client", "web");
        if (platform == "admin") loginClient.DefaultRequestHeaders.Add("X-HuTube-App", "admin");

        var loginRes = await loginClient.PostAsJsonAsync("/api/v1/auth/login",
            new LoginRequest(email, password, platform, "Test device"));
        loginRes.EnsureSuccessStatusCode();
        var loginBody = await loginRes.Content.ReadFromJsonAsync<LoginResponse>(JsonOptions);

        loginClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", loginBody!.AccessToken);
        return (loginClient, user, loginBody.AccessToken);
    }

    [Fact]
    public async Task INT_S4_03_AdminRbac_Moderator_CanViewQueue_ButCannotApprove()
    {
        // 1. Seed Moderator
        var (moderatorClient, _, _) = await CreateUserAsync("mod", SystemRoles.Moderator);

        // 2 & 4. Gọi API Queue (moderation.view_queue được gán theo seed) -> Queue allowed (200)
        var queueRes = await moderatorClient.GetAsync("/api/v1/admin/moderation/queue");
        Assert.Equal(HttpStatusCode.OK, queueRes.StatusCode);

        // 3 & 5. Gọi API Approve (moderation.approve không được gán cho moderator) -> Approve forbidden (403)
        var approveRes = await moderatorClient.PostAsync("/api/v1/admin/moderation/approve", null);
        Assert.Equal(HttpStatusCode.Forbidden, approveRes.StatusCode);

        // Verify admin me returns role and permissions
        var meRes = await moderatorClient.GetAsync("/api/v1/admin/me");
        Assert.Equal(HttpStatusCode.OK, meRes.StatusCode);
        var meJson = await meRes.Content.ReadAsStringAsync();
        Assert.Contains("moderator", meJson);
        Assert.Contains("moderation.view_queue", meJson);
    }

    [Fact]
    public async Task INT_S4_04_ChannelMembership_OwnerAndEditor_PermissionEnforcement()
    {
        // Setup Owner and Editor users
        var (ownerClient, ownerUser, _) = await CreateUserAsync("owner");
        var (editorClient, editorUser, _) = await CreateUserAsync("editor");

        // 1. Owner tạo Channel
        var createRes = await ownerClient.PostAsJsonAsync("/api/v1/channels",
            new CreateChannelRequest("Gaming Channel", "gamingchannel", "Best gaming videos"));
        Assert.Equal(HttpStatusCode.Created, createRes.StatusCode);
        var channel = await createRes.Content.ReadFromJsonAsync<ChannelResponse>(JsonOptions);
        Assert.NotNull(channel);

        // 2. Owner invite Editor
        var inviteRes = await ownerClient.PostAsJsonAsync($"/api/v1/channels/{channel.ChannelId}/members/invite",
            new InviteMemberRequest(editorUser.Email, ChannelRoles.Editor));
        Assert.Equal(HttpStatusCode.Created, inviteRes.StatusCode);
        var invite = await inviteRes.Content.ReadFromJsonAsync<ChannelInvitationResponse>(JsonOptions);
        Assert.NotNull(invite);
        Assert.Equal("pending", invite.Status);

        // The recipient can discover the pending invitation from their own account.
        var myInvitationsRes = await editorClient.GetAsync("/api/v1/channels/invitations/me");
        Assert.Equal(HttpStatusCode.OK, myInvitationsRes.StatusCode);
        var myInvitations = await myInvitationsRes.Content.ReadFromJsonAsync<List<ChannelInvitationResponse>>(JsonOptions);
        Assert.Contains(myInvitations!, item => item.ChannelInvitationId == invite.ChannelInvitationId);

        // 3. Editor Accept invitation
        var acceptRes = await editorClient.PostAsync($"/api/v1/channels/invitations/{invite.ChannelInvitationId}/accept", null);
        Assert.Equal(HttpStatusCode.OK, acceptRes.StatusCode);
        var member = await acceptRes.Content.ReadFromJsonAsync<ChannelMemberResponse>(JsonOptions);
        Assert.NotNull(member);
        Assert.Equal(ChannelRoles.Editor, member.RoleCode);

        // 4. Editor gọi API được phép: GetMembers
        var getMembersRes = await editorClient.GetAsync($"/api/v1/channels/{channel.ChannelId}/members");
        Assert.Equal(HttpStatusCode.OK, getMembersRes.StatusCode);
        var members = await getMembersRes.Content.ReadFromJsonAsync<List<ChannelMemberResponse>>(JsonOptions);
        Assert.NotNull(members);
        Assert.Equal(2, members.Count); // Owner and Editor

        // 5. Editor gọi Owner-only API: DeleteChannel -> Forbidden (403)
        var deleteRes = await editorClient.DeleteAsync($"/api/v1/channels/{channel.ChannelId}");
        Assert.Equal(HttpStatusCode.Forbidden, deleteRes.StatusCode);

        // Owner can delete channel successfully
        var ownerDeleteRes = await ownerClient.DeleteAsync($"/api/v1/channels/{channel.ChannelId}");
        Assert.Equal(HttpStatusCode.NoContent, ownerDeleteRes.StatusCode);
    }
}
