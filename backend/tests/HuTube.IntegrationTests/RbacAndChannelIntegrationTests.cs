using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Application.Channels;
using HuTube.Application.Rbac;
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
    public async Task INT_S4_06_AdminRbac_SuperAdminCanCreateAndUpdateCustomRole()
    {
        var (superAdminClient, _, _) = await CreateUserAsync("super_admin", SystemRoles.SuperAdmin);
        var suffix = Guid.NewGuid().ToString("N")[..10];
        var code = $"content_reviewer_{suffix}";

        var createRes = await superAdminClient.PostAsJsonAsync("/api/v1/admin/roles", new
        {
            code,
            name = "Content reviewer",
            description = "Review reported content",
            permissionCodes = new[] { AdminPermissions.ModerationViewQueue },
            reason = "Tạo role kiểm duyệt nội dung cho Sprint 4"
        });

        Assert.Equal(HttpStatusCode.Created, createRes.StatusCode);
        var created = await createRes.Content.ReadFromJsonAsync<RoleResponse>(JsonOptions);
        Assert.NotNull(created);
        Assert.Equal(code, created.Code);
        Assert.Contains(AdminPermissions.ModerationViewQueue, created.Permissions);

        var updateRes = await superAdminClient.PutAsJsonAsync($"/api/v1/admin/roles/{created.RoleId}", new
        {
            name = "Content reviewer",
            description = "Review and decide reported content",
            permissionCodes = new[] { AdminPermissions.ModerationViewQueue, AdminPermissions.ModerationReview },
            reason = "Bổ sung quyền review cho role kiểm duyệt"
        });

        Assert.Equal(HttpStatusCode.OK, updateRes.StatusCode);
        var updated = await updateRes.Content.ReadFromJsonAsync<RoleResponse>(JsonOptions);
        Assert.NotNull(updated);
        Assert.Contains(AdminPermissions.ModerationReview, updated.Permissions);

        var auditRes = await superAdminClient.GetAsync("/api/v1/admin/audit-logs");
        Assert.Equal(HttpStatusCode.OK, auditRes.StatusCode);
        var auditJson = await auditRes.Content.ReadAsStringAsync();
        Assert.Contains("rbac.role_created", auditJson);
        Assert.Contains("rbac.role_updated", auditJson);
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
        Assert.Contains("/channel-invitations?invitation=", factory.Emails.Bodies[editorUser.Email]);
        Assert.Contains("Gaming Channel", factory.Emails.Bodies[editorUser.Email]);

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

    [Fact]
    public async Task ChannelHandle_IsNormalizedAcrossCheckCreateAndLookup_AndRemainsUnique()
    {
        var (ownerClient, _, _) = await CreateUserAsync("handle_owner");
        var (otherClient, _, _) = await CreateUserAsync("handle_other");
        var create = await ownerClient.PostAsJsonAsync("/api/v1/channels",
            new CreateChannelRequest("Handle channel", "@My-Channel", "Unicode mô tả"));
        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        var channel = (await create.Content.ReadFromJsonAsync<ChannelResponse>(JsonOptions))!;
        Assert.Equal("my-channel", channel.Handle);

        var check = await ownerClient.GetFromJsonAsync<CheckHandleResponse>("/api/v1/channels/check-handle?handle=%40MY-CHANNEL", JsonOptions);
        Assert.NotNull(check);
        Assert.False(check.IsAvailable);
        Assert.Equal("my-channel", check.Handle);

        var lookup = await otherClient.GetFromJsonAsync<ChannelResponse>("/api/v1/channels/handle/%40MY-CHANNEL", JsonOptions);
        Assert.NotNull(lookup);
        Assert.Equal(channel.ChannelId, lookup.ChannelId);

        var duplicate = await otherClient.PostAsJsonAsync("/api/v1/channels",
            new CreateChannelRequest("Duplicate handle", "my-channel", null));
        Assert.Equal(HttpStatusCode.Conflict, duplicate.StatusCode);
        Assert.Contains("HANDLE_ALREADY_EXISTS", await duplicate.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task ChannelSubscription_IsIdempotentAndNotificationPreferenceRoundTrips()
    {
        var (ownerClient, _, _) = await CreateUserAsync("subscription_owner");
        var (viewerClient, viewer, _) = await CreateUserAsync("subscription_viewer");
        var channelResponse = await ownerClient.PostAsJsonAsync("/api/v1/channels",
            new CreateChannelRequest("Subscribed channel", "subscribed-channel", null));
        var channel = (await channelResponse.Content.ReadFromJsonAsync<ChannelResponse>(JsonOptions))!;

        var initialStatusResponse = await viewerClient.GetAsync($"/api/v1/channels/{channel.ChannelId}/subscribe-status");
        Assert.Equal(HttpStatusCode.OK, initialStatusResponse.StatusCode);
        var initialStatus = (await initialStatusResponse.Content.ReadFromJsonAsync<SubscriptionStatusResponse>(JsonOptions))!;
        Assert.False(initialStatus.IsSubscribed);
        Assert.Equal("none", initialStatus.Status);

        var first = await viewerClient.PostAsync($"/api/v1/channels/{channel.ChannelId}/subscribe", null);
        var firstBody = (await first.Content.ReadFromJsonAsync<SubscriptionResponse>(JsonOptions))!;
        var second = await viewerClient.PostAsync($"/api/v1/channels/{channel.ChannelId}/subscribe", null);
        var secondBody = (await second.Content.ReadFromJsonAsync<SubscriptionResponse>(JsonOptions))!;
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        Assert.Equal(HttpStatusCode.OK, second.StatusCode);
        Assert.Equal(firstBody.SubscriptionId, secondBody.SubscriptionId);

        var preference = await viewerClient.PatchAsJsonAsync($"/api/v1/channels/{channel.ChannelId}/subscribe-notifications", new { enabled = false });
        Assert.Equal(HttpStatusCode.OK, preference.StatusCode);
        Assert.False((await preference.Content.ReadFromJsonAsync<SubscriptionResponse>(JsonOptions))!.NotificationsEnabled);
        var status = await viewerClient.GetFromJsonAsync<SubscriptionStatusResponse>($"/api/v1/channels/{channel.ChannelId}/subscribe-status", JsonOptions);
        Assert.NotNull(status);
        Assert.Equal(channel.ChannelId, status.ChannelId);
        Assert.True(status.IsSubscribed);
        Assert.False(status.NotificationsEnabled);

        Assert.Equal(HttpStatusCode.NoContent, (await viewerClient.DeleteAsync($"/api/v1/channels/{channel.ChannelId}/subscribe")).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await viewerClient.DeleteAsync($"/api/v1/channels/{channel.ChannelId}/subscribe")).StatusCode);
        var inactiveStatus = await viewerClient.GetFromJsonAsync<SubscriptionStatusResponse>($"/api/v1/channels/{channel.ChannelId}/subscribe-status", JsonOptions);
        Assert.NotNull(inactiveStatus);
        Assert.False(inactiveStatus.IsSubscribed);
        Assert.Equal("paused", inactiveStatus.Status);
        await using var db = factory.CreateDb();
        Assert.Equal(1, await db.Subscriptions.CountAsync(item => item.UserId == viewer.UserId && item.ChannelId == channel.ChannelId));
        Assert.Equal("paused", await db.Subscriptions.Where(item => item.SubscriptionId == firstBody.SubscriptionId).Select(item => item.Status).SingleAsync());
    }

    [Fact]
    public async Task SubscriptionsEndpoint_ReturnsOnlyActiveSubscriptionsForCurrentActor()
    {
        // Arrange
        var (ownerOneClient, _, _) = await CreateUserAsync("sublist_o1");
        var (ownerTwoClient, _, _) = await CreateUserAsync("sublist_o2");
        var (viewerClient, viewer, _) = await CreateUserAsync("sublist_v");
        var channelOne = (await (await ownerOneClient.PostAsJsonAsync("/api/v1/channels",
            new CreateChannelRequest("Subscription list one", "subscription-list-one", null)))
            .Content.ReadFromJsonAsync<ChannelResponse>(JsonOptions))!;
        var channelTwo = (await (await ownerTwoClient.PostAsJsonAsync("/api/v1/channels",
            new CreateChannelRequest("Subscription list two", "subscription-list-two", null)))
            .Content.ReadFromJsonAsync<ChannelResponse>(JsonOptions))!;

        await viewerClient.PostAsync($"/api/v1/channels/{channelOne.ChannelId}/subscribe", null);
        await viewerClient.PostAsync($"/api/v1/channels/{channelTwo.ChannelId}/subscribe", null);
        await viewerClient.DeleteAsync($"/api/v1/channels/{channelTwo.ChannelId}/subscribe");

        // Act
        var subscriptions = await viewerClient.GetFromJsonAsync<List<SubscribedChannelResponse>>(
            "/api/v1/subscriptions", JsonOptions);
        var secondUserSubscriptions = await ownerTwoClient.GetFromJsonAsync<List<SubscribedChannelResponse>>(
            "/api/v1/subscriptions", JsonOptions);
        var guestResponse = await factory.CreateClient().GetAsync("/api/v1/subscriptions");

        // Assert
        Assert.NotNull(subscriptions);
        var listed = Assert.Single(subscriptions!);
        Assert.Equal(channelOne.ChannelId, listed.ChannelId);
        Assert.DoesNotContain(subscriptions, item => item.ChannelId == channelTwo.ChannelId);
        Assert.Empty(secondUserSubscriptions!);
        Assert.Equal(HttpStatusCode.Unauthorized, guestResponse.StatusCode);

        await using var db = factory.CreateDb();
        Assert.Equal("active", await db.Subscriptions
            .Where(item => item.UserId == viewer.UserId && item.ChannelId == channelOne.ChannelId)
            .Select(item => item.Status).SingleAsync());
        Assert.Equal("paused", await db.Subscriptions
            .Where(item => item.UserId == viewer.UserId && item.ChannelId == channelTwo.ChannelId)
            .Select(item => item.Status).SingleAsync());
    }

    [Fact]
    public async Task ChannelInvitation_NormalizesDuplicateEmailAndRejectsWrongActor()
    {
        var (ownerClient, _, _) = await CreateUserAsync("invite_owner");
        var (inviteeClient, invitee, _) = await CreateUserAsync("invitee");
        var (wrongClient, _, _) = await CreateUserAsync("invite_wrong_actor");
        var channelResponse = await ownerClient.PostAsJsonAsync("/api/v1/channels",
            new CreateChannelRequest("Invitation channel", "invitation-channel", null));
        var channel = (await channelResponse.Content.ReadFromJsonAsync<ChannelResponse>(JsonOptions))!;

        var invitationResponse = await ownerClient.PostAsJsonAsync($"/api/v1/channels/{channel.ChannelId}/members/invite",
            new InviteMemberRequest(invitee.Email, ChannelRoles.Editor));
        Assert.Equal(HttpStatusCode.Created, invitationResponse.StatusCode);
        var invitation = (await invitationResponse.Content.ReadFromJsonAsync<ChannelInvitationResponse>(JsonOptions))!;

        var duplicate = await ownerClient.PostAsJsonAsync($"/api/v1/channels/{channel.ChannelId}/members/invite",
            new InviteMemberRequest(invitee.Email.ToUpperInvariant(), ChannelRoles.Viewer));
        Assert.Equal(HttpStatusCode.Conflict, duplicate.StatusCode);
        Assert.Contains("INVITATION_ALREADY_SENT", await duplicate.Content.ReadAsStringAsync());

        var wrongActor = await wrongClient.PostAsync($"/api/v1/channels/invitations/{invitation.ChannelInvitationId}/accept", null);
        Assert.Equal(HttpStatusCode.Forbidden, wrongActor.StatusCode);
        Assert.Contains("INVITATION_ACCESS_DENIED", await wrongActor.Content.ReadAsStringAsync());

        var accepted = await inviteeClient.PostAsync($"/api/v1/channels/invitations/{invitation.ChannelInvitationId}/accept", null);
        Assert.Equal(HttpStatusCode.OK, accepted.StatusCode);
        var member = (await accepted.Content.ReadFromJsonAsync<ChannelMemberResponse>(JsonOptions))!;
        Assert.Equal(invitee.UserId, member.UserId);
        Assert.Equal(ChannelRoles.Editor, member.RoleCode);
    }

    [Fact]
    public async Task ChannelManagement_ExposesOwnerViewsBrandingRolesAndMemberLifecycle()
    {
        var (ownerClient, owner, _) = await CreateUserAsync("channel_surface_owner");
        var (memberClient, member, _) = await CreateUserAsync("channel_surface_member");
        var (declineeClient, declinee, _) = await CreateUserAsync("channel_surface_declinee");
        var channelResponse = await ownerClient.PostAsJsonAsync("/api/v1/channels",
            new CreateChannelRequest("Surface channel", "surface-channel", "Channel surface contract"));
        Assert.Equal(HttpStatusCode.Created, channelResponse.StatusCode);
        var channel = (await channelResponse.Content.ReadFromJsonAsync<ChannelResponse>(JsonOptions))!;

        var myChannel = await ownerClient.GetFromJsonAsync<ChannelResponse>("/api/v1/channels/me", JsonOptions);
        Assert.NotNull(myChannel);
        Assert.Equal(channel.ChannelId, myChannel!.ChannelId);
        Assert.True(myChannel.IsOwner);

        var accessible = await ownerClient.GetFromJsonAsync<List<ChannelResponse>>(
            "/api/v1/channels/accessible", JsonOptions);
        Assert.Contains(accessible!, item => item.ChannelId == channel.ChannelId && item.IsOwner);

        var roles = await ownerClient.GetFromJsonAsync<List<ChannelRoleResponse>>(
            "/api/v1/channels/roles", JsonOptions);
        Assert.NotNull(roles);
        Assert.Contains(roles!, item => item.Code == ChannelRoles.Editor);
        Assert.All(roles!, item => Assert.NotEmpty(item.Permissions));

        var png = Convert.FromBase64String(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j8ioAAAAASUVORK5CYII=");
        using (var avatarForm = new MultipartFormDataContent())
        {
            var file = new ByteArrayContent(png);
            file.Headers.ContentType = new MediaTypeHeaderValue("image/png");
            avatarForm.Add(file, "file", "surface-avatar.png");
            var avatar = await ownerClient.PostAsync($"/api/v1/channels/{channel.ChannelId}/avatar", avatarForm);
            Assert.Equal(HttpStatusCode.OK, avatar.StatusCode);
            var updated = (await avatar.Content.ReadFromJsonAsync<ChannelResponse>(JsonOptions))!;
            Assert.StartsWith("https://storage.test/channel-avatars/", updated.AvatarUrl);
        }
        using (var bannerForm = new MultipartFormDataContent())
        {
            var file = new ByteArrayContent(png);
            file.Headers.ContentType = new MediaTypeHeaderValue("image/png");
            bannerForm.Add(file, "file", "surface-banner.png");
            var banner = await ownerClient.PostAsync($"/api/v1/channels/{channel.ChannelId}/banner", bannerForm);
            Assert.Equal(HttpStatusCode.OK, banner.StatusCode);
            var updated = (await banner.Content.ReadFromJsonAsync<ChannelResponse>(JsonOptions))!;
            Assert.StartsWith("https://storage.test/channel-banners/", updated.BannerUrl);
        }

        var memberInvite = await ownerClient.PostAsJsonAsync(
            $"/api/v1/channels/{channel.ChannelId}/members/invite",
            new InviteMemberRequest(member.Email, ChannelRoles.Editor));
        var memberInvitation = (await memberInvite.Content.ReadFromJsonAsync<ChannelInvitationResponse>(JsonOptions))!;
        Assert.Equal(HttpStatusCode.Created, memberInvite.StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await memberClient.PostAsync(
            $"/api/v1/channels/invitations/{memberInvitation.ChannelInvitationId}/accept", null)).StatusCode);

        var role = await ownerClient.PatchAsJsonAsync(
            $"/api/v1/channels/{channel.ChannelId}/members/{member.UserId}/role",
            new ChangeMemberRoleRequest(ChannelRoles.Manager));
        Assert.Equal(HttpStatusCode.OK, role.StatusCode);
        Assert.Equal(ChannelRoles.Manager,
            (await role.Content.ReadFromJsonAsync<ChannelMemberResponse>(JsonOptions))!.RoleCode);

        var declineInvite = await ownerClient.PostAsJsonAsync(
            $"/api/v1/channels/{channel.ChannelId}/members/invite",
            new InviteMemberRequest(declinee.Email, ChannelRoles.Viewer));
        var declineInvitation = (await declineInvite.Content.ReadFromJsonAsync<ChannelInvitationResponse>(JsonOptions))!;
        Assert.Equal(HttpStatusCode.NoContent, (await declineeClient.PostAsync(
            $"/api/v1/channels/invitations/{declineInvitation.ChannelInvitationId}/decline", null)).StatusCode);
        var pending = await ownerClient.GetFromJsonAsync<List<ChannelInvitationResponse>>(
            $"/api/v1/channels/{channel.ChannelId}/invitations", JsonOptions);
        Assert.DoesNotContain(pending!, item => item.ChannelInvitationId == declineInvitation.ChannelInvitationId);

        Assert.Equal(HttpStatusCode.NoContent, (await ownerClient.DeleteAsync(
            $"/api/v1/channels/{channel.ChannelId}/members/{member.UserId}")).StatusCode);
        var members = await ownerClient.GetFromJsonAsync<List<ChannelMemberResponse>>(
            $"/api/v1/channels/{channel.ChannelId}/members", JsonOptions);
        Assert.Single(members!);
        Assert.Equal(owner.UserId, members![0].UserId);
    }
}
