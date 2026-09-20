using HuTube.Application.Channels;
using HuTube.Application.Auth;
using HuTube.Domain.Channels;
using HuTube.Domain.Users;
using Xunit;

namespace HuTube.UnitTests;

public sealed class ChannelTests
{
    private sealed class FakeEmailSender : IAuthEmailSender
    {
        public List<(string Email, string Subject, string Body)> Messages { get; } = [];

        public Task SendAsync(string email, string subject, string body, CancellationToken cancellationToken)
        {
            Messages.Add((email, subject, body));
            return Task.CompletedTask;
        }
    }

    private sealed class FakeChannelStore : IChannelStore
    {
        public List<Channel> Channels { get; } = [];
        public List<ChannelMember> Members { get; } = [];
        public List<ChannelInvitation> Invitations { get; } = [];
        public List<User> Users { get; } = [];
        public List<Subscription> Subscriptions { get; } = [];

        public Task<Subscription?> FindSubscriptionAsync(Guid userId, Guid channelId, CancellationToken ct) =>
            Task.FromResult(Subscriptions.SingleOrDefault(s => s.UserId == userId && s.ChannelId == channelId));

        public void AddSubscription(Subscription subscription) => Subscriptions.Add(subscription);

        public Task<long> CountSubscribersAsync(Guid channelId, CancellationToken ct) =>
            Task.FromResult((long)Subscriptions.Count(s => s.ChannelId == channelId && s.Status == "active"));

        public Task<List<SubscribedChannelResponse>> GetSubscribedChannelsAsync(Guid userId, CancellationToken ct)
        {
            var result = from s in Subscriptions
                         where s.UserId == userId && s.Status == "active"
                         join c in Channels on s.ChannelId equals c.ChannelId
                         where c.Status == "active"
                         select new SubscribedChannelResponse(c.ChannelId, c.Name, c.Handle, c.AvatarUrl, 1, s.SubscribedAt);
            return Task.FromResult(result.ToList());
        }

        public Task<Channel?> FindChannelAsync(Guid channelId, CancellationToken ct) =>
            Task.FromResult(Channels.SingleOrDefault(c => c.ChannelId == channelId));

        public Task<Channel?> FindChannelByHandleAsync(string handle, CancellationToken ct) =>
            Task.FromResult(Channels.SingleOrDefault(c => c.Handle == handle));

        public Task<int> CountChannelsByOwnerAsync(Guid ownerUserId, CancellationToken ct) =>
            Task.FromResult(Channels.Count(c => c.OwnerUserId == ownerUserId && c.Status != "deleted"));

        public Task<List<Channel>> GetAccessibleChannelsAsync(Guid userId, CancellationToken ct) =>
            Task.FromResult(Channels
                .Where(channel => channel.Status == "active" &&
                    (channel.OwnerUserId == userId || Members.Any(member => member.ChannelId == channel.ChannelId && member.UserId == userId && member.Status == "active")))
                .OrderBy(channel => channel.OwnerUserId == userId ? 0 : 1)
                .ThenBy(channel => channel.Name)
                .ToList());

        public void AddChannel(Channel channel) => Channels.Add(channel);

        public Task<ChannelMember?> FindMemberAsync(Guid channelId, Guid userId, CancellationToken ct) =>
            Task.FromResult(Members.SingleOrDefault(m => m.ChannelId == channelId && m.UserId == userId && m.Status == "active"));

        public Task<List<ChannelMemberInfo>> GetMembersWithUserInfoAsync(Guid channelId, CancellationToken ct)
        {
            var result = from m in Members
                         where m.ChannelId == channelId && m.Status == "active"
                         join u in Users on m.UserId equals u.UserId
                         select new ChannelMemberInfo(m, u.Username, u.Email, u.DisplayName);
            return Task.FromResult(result.ToList());
        }

        public void AddMember(ChannelMember member) => Members.Add(member);
        public void RemoveMember(ChannelMember member) => Members.Remove(member);

        public Task<ChannelInvitation?> FindInvitationAsync(Guid invitationId, CancellationToken ct) =>
            Task.FromResult(Invitations.SingleOrDefault(i => i.ChannelInvitationId == invitationId));

        public Task<ChannelInvitation?> FindPendingInvitationAsync(Guid channelId, string email, CancellationToken ct) =>
            Task.FromResult(Invitations.SingleOrDefault(i => i.ChannelId == channelId && i.InvitedEmail == email && i.Status == "pending"));

        public Task<List<ChannelInvitation>> GetPendingInvitationsAsync(Guid channelId, CancellationToken ct) =>
            Task.FromResult(Invitations.Where(i => i.ChannelId == channelId && i.Status == "pending").ToList());

        public Task<List<ChannelInvitationInfo>> GetUserInvitationsWithChannelAsync(string email, Guid userId, CancellationToken ct)
        {
            var result = from i in Invitations
                         where (i.InvitedEmail == email || i.InvitedUserId == userId) && i.Status == "pending"
                         join c in Channels on i.ChannelId equals c.ChannelId
                         select new ChannelInvitationInfo(i, c.Name, c.Handle);
            return Task.FromResult(result.ToList());
        }

        public void AddInvitation(ChannelInvitation invitation) => Invitations.Add(invitation);

        public Task<User?> FindUserByEmailAsync(string email, CancellationToken ct) =>
            Task.FromResult(Users.SingleOrDefault(u => u.Email == email));

        public Task<User?> FindUserByIdAsync(Guid userId, CancellationToken ct) =>
            Task.FromResult(Users.SingleOrDefault(u => u.UserId == userId));

        public Task SaveAsync(CancellationToken ct) => Task.CompletedTask;
    }

    [Fact]
    public async Task CreateChannel_ShouldSucceed_AndMakeCreatorOwner()
    {
        var store = new FakeChannelStore();
        var service = new ChannelService(store);
        var ownerId = Guid.NewGuid();

        var response = await service.CreateChannelAsync(ownerId, new("Tech Channel", "techchannel", "Tech content"));

        Assert.NotNull(response);
        Assert.Equal("techchannel", response.Handle);
        Assert.Equal(ownerId, response.OwnerUserId);
        Assert.Single(store.Channels);
        Assert.Equal(ownerId, store.Channels[0].OwnerUserId);
    }

    [Fact]
    public async Task CreateChannel_DuplicateHandle_ShouldThrow409()
    {
        var store = new FakeChannelStore();
        var service = new ChannelService(store);
        var ownerId = Guid.NewGuid();
        await service.CreateChannelAsync(ownerId, new("First Channel", "techchannel", null));

        var ex = await Assert.ThrowsAsync<ChannelException>(() =>
            service.CreateChannelAsync(Guid.NewGuid(), new("Second Channel", "TECHCHANNEL", null)));

        Assert.Equal(409, ex.Status);
        Assert.Equal("HANDLE_ALREADY_EXISTS", ex.Code);
    }

    [Fact]
    public async Task UpdateChannel_NonMember_ShouldThrow403()
    {
        var store = new FakeChannelStore();
        var service = new ChannelService(store);
        var ownerId = Guid.NewGuid();
        var channel = await service.CreateChannelAsync(ownerId, new("My Channel", "mychannel", null));

        var strangerId = Guid.NewGuid();
        var ex = await Assert.ThrowsAsync<ChannelException>(() =>
            service.UpdateChannelAsync(channel.ChannelId, strangerId, new("New Name", null, null, null)));

        Assert.Equal(403, ex.Status);
    }

    [Fact]
    public async Task InviteMember_And_Accept_ShouldCreateActiveMember()
    {
        var store = new FakeChannelStore();
        var service = new ChannelService(store);
        var ownerId = Guid.NewGuid();
        var channel = await service.CreateChannelAsync(ownerId, new("Channel", "channel", null));

        var invitee = new User { UserId = Guid.NewGuid(), Email = "invitee@example.com", Username = "invitee", DisplayName = "Invitee" };
        store.Users.Add(invitee);

        var invite = await service.InviteMemberAsync(channel.ChannelId, ownerId, new("invitee@example.com", ChannelRoles.Editor));
        Assert.Equal("pending", invite.Status);

        var memberResponse = await service.AcceptInvitationAsync(invite.ChannelInvitationId, invitee.UserId);
        Assert.Equal(ChannelRoles.Editor, memberResponse.RoleCode);
        Assert.Equal("active", memberResponse.Status);
    }

    [Fact]
    public async Task AccessibleChannels_ShouldIncludeAcceptedMemberWithoutOwnedChannel()
    {
        var store = new FakeChannelStore();
        var service = new ChannelService(store);
        var ownerId = Guid.NewGuid();
        var collaboratorId = Guid.NewGuid();
        var channel = await service.CreateChannelAsync(ownerId, new("Shared Channel", "sharedchannel", null));
        store.Members.Add(new ChannelMember
        {
            ChannelMemberId = Guid.NewGuid(),
            ChannelId = channel.ChannelId,
            UserId = collaboratorId,
            RoleCode = ChannelRoles.Editor,
            Status = "active"
        });

        var accessible = await service.GetAccessibleChannelsAsync(collaboratorId);

        var result = Assert.Single(accessible);
        Assert.Equal(channel.ChannelId, result.ChannelId);
        Assert.False(result.IsOwner);
        Assert.Equal(ChannelRoles.Editor, result.MyRole);
        Assert.Contains(ChannelPermissions.VideoView, result.Permissions);
    }

    [Fact]
    public async Task InviteMember_ShouldSendInvitationEmail()
    {
        var store = new FakeChannelStore();
        var emailSender = new FakeEmailSender();
        var service = new ChannelService(
            store,
            emailSender: emailSender,
            authOptions: new AuthOptions { WebBaseUrl = "http://localhost:4200" });
        var ownerId = Guid.NewGuid();
        var channel = await service.CreateChannelAsync(ownerId, new("Channel", "channel", null));

        var invitee = new User
        {
            UserId = Guid.NewGuid(),
            Email = "invitee@example.com",
            Username = "invitee",
            DisplayName = "Invitee"
        };
        store.Users.Add(invitee);

        var invitation = await service.InviteMemberAsync(
            channel.ChannelId,
            ownerId,
            new("invitee@example.com", ChannelRoles.Editor));

        var message = Assert.Single(emailSender.Messages);
        Assert.Equal(invitee.Email, message.Email);
        Assert.Contains("Bạn được mời tham gia kênh", message.Subject);
        Assert.Contains($"/channel-invitations?invitation={invitation.ChannelInvitationId}", message.Body);
    }

    [Fact]
    public async Task RevokedInvitation_CannotBeAccepted()
    {
        var store = new FakeChannelStore();
        var service = new ChannelService(store);
        var ownerId = Guid.NewGuid();
        var channel = await service.CreateChannelAsync(ownerId, new("Channel", "channel", null));

        var invitee = new User { UserId = Guid.NewGuid(), Email = "invitee@example.com", Username = "invitee", DisplayName = "Invitee" };
        store.Users.Add(invitee);

        var invite = await service.InviteMemberAsync(channel.ChannelId, ownerId, new("invitee@example.com", ChannelRoles.Viewer));
        await service.RevokeInvitationAsync(channel.ChannelId, invite.ChannelInvitationId, ownerId);

        var ex = await Assert.ThrowsAsync<ChannelException>(() =>
            service.AcceptInvitationAsync(invite.ChannelInvitationId, invitee.UserId));

        Assert.Equal(400, ex.Status);
        Assert.Equal("INVITATION_REVOKED", ex.Code);
    }

    [Fact]
    public async Task ExpiredInvitation_IsMarkedExpired_AndCannotBeDeclined()
    {
        var store = new FakeChannelStore();
        var service = new ChannelService(store);
        var ownerId = Guid.NewGuid();
        var channel = await service.CreateChannelAsync(ownerId, new("Channel", "channel", null));
        var invitee = new User { UserId = Guid.NewGuid(), Email = "invitee@example.com", Username = "invitee", DisplayName = "Invitee" };
        store.Users.Add(invitee);

        await service.InviteMemberAsync(channel.ChannelId, ownerId, new(invitee.Email, ChannelRoles.Editor));
        var invitation = store.Invitations.Single();
        invitation.ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(-1);

        var pending = await service.GetMyInvitationsAsync(invitee.UserId);
        Assert.Empty(pending);
        Assert.Equal("expired", invitation.Status);
        Assert.NotNull(invitation.RespondedAt);

        var ex = await Assert.ThrowsAsync<ChannelException>(() =>
            service.DeclineInvitationAsync(invitation.ChannelInvitationId, invitee.UserId));

        Assert.Equal(410, ex.Status);
        Assert.Equal("INVITATION_EXPIRED", ex.Code);
    }

    [Fact]
    public async Task DuplicatePendingInvitation_ShouldBeRejected()
    {
        var store = new FakeChannelStore();
        var service = new ChannelService(store);
        var ownerId = Guid.NewGuid();
        var channel = await service.CreateChannelAsync(ownerId, new("Channel", "channel", null));
        var invitee = new User { UserId = Guid.NewGuid(), Email = "invitee@example.com", Username = "invitee", DisplayName = "Invitee" };
        store.Users.Add(invitee);

        await service.InviteMemberAsync(channel.ChannelId, ownerId, new("INVITEE@example.com", ChannelRoles.Editor));
        var ex = await Assert.ThrowsAsync<ChannelException>(() =>
            service.InviteMemberAsync(channel.ChannelId, ownerId, new(invitee.Email, ChannelRoles.Editor)));

        Assert.Equal(409, ex.Status);
        Assert.Equal("INVITATION_ALREADY_SENT", ex.Code);
    }

    [Fact]
    public async Task ChangeRole_ManagerCannotChangeAnotherManager()
    {
        var store = new FakeChannelStore();
        var service = new ChannelService(store);
        var ownerId = Guid.NewGuid();
        var channel = await service.CreateChannelAsync(ownerId, new("Channel", "channel", null));

        var manager1 = new User { UserId = Guid.NewGuid(), Email = "m1@example.com", Username = "m1", DisplayName = "M1" };
        var manager2 = new User { UserId = Guid.NewGuid(), Email = "m2@example.com", Username = "m2", DisplayName = "M2" };
        store.Users.Add(manager1);
        store.Users.Add(manager2);

        store.Members.Add(new() { ChannelMemberId = Guid.NewGuid(), ChannelId = channel.ChannelId, UserId = manager1.UserId, RoleCode = ChannelRoles.Manager, Status = "active" });
        store.Members.Add(new() { ChannelMemberId = Guid.NewGuid(), ChannelId = channel.ChannelId, UserId = manager2.UserId, RoleCode = ChannelRoles.Manager, Status = "active" });

        var ex = await Assert.ThrowsAsync<ChannelException>(() =>
            service.ChangeMemberRoleAsync(channel.ChannelId, manager2.UserId, manager1.UserId, new(ChannelRoles.Editor)));

        Assert.Equal(403, ex.Status);
    }

    [Fact]
    public async Task RemoveMember_CannotRemoveOwner()
    {
        var store = new FakeChannelStore();
        var service = new ChannelService(store);
        var ownerId = Guid.NewGuid();
        var channel = await service.CreateChannelAsync(ownerId, new("Channel", "channel", null));

        var ex = await Assert.ThrowsAsync<ChannelException>(() =>
            service.RemoveMemberAsync(channel.ChannelId, ownerId, ownerId));

        Assert.Equal(400, ex.Status);
        Assert.Equal("CANNOT_REMOVE_OWNER", ex.Code);
    }

    [Fact]
    public async Task Subscribe_Success_ShouldCreateActiveSubscription()
    {
        var store = new FakeChannelStore();
        var service = new ChannelService(store);
        var ownerId = Guid.NewGuid();
        var subscriberId = Guid.NewGuid();
        var channel = await service.CreateChannelAsync(ownerId, new("My Channel", "mychannel", null));

        var sub = await service.SubscribeAsync(channel.ChannelId, subscriberId);

        Assert.NotNull(sub);
        Assert.Equal("active", sub.Status);
        Assert.Equal(channel.ChannelId, sub.ChannelId);
        Assert.Equal(subscriberId, sub.UserId);
        Assert.Single(store.Subscriptions);

        var count = await store.CountSubscribersAsync(channel.ChannelId, CancellationToken.None);
        Assert.Equal(1, count);
    }

    [Fact]
    public async Task Subscribe_OwnChannel_ShouldThrow400()
    {
        var store = new FakeChannelStore();
        var service = new ChannelService(store);
        var ownerId = Guid.NewGuid();
        var channel = await service.CreateChannelAsync(ownerId, new("My Channel", "mychannel", null));

        var ex = await Assert.ThrowsAsync<ChannelException>(() =>
            service.SubscribeAsync(channel.ChannelId, ownerId));

        Assert.Equal(400, ex.Status);
        Assert.Equal("CANNOT_SUBSCRIBE_OWN_CHANNEL", ex.Code);
        Assert.Empty(store.Subscriptions);
    }

    [Fact]
    public async Task Subscribe_InactiveChannel_ShouldThrowNotActive()
    {
        var store = new FakeChannelStore();
        var service = new ChannelService(store);
        var ownerId = Guid.NewGuid();
        var subscriberId = Guid.NewGuid();
        var channel = await service.CreateChannelAsync(ownerId, new("My Channel", "mychannel", null));
        store.Channels[0].Status = "suspended";

        var ex = await Assert.ThrowsAsync<ChannelException>(() =>
            service.SubscribeAsync(channel.ChannelId, subscriberId));

        Assert.Equal(409, ex.Status);
        Assert.Equal("CHANNEL_NOT_ACTIVE", ex.Code);
    }

    [Fact]
    public async Task Subscribe_DuplicateRequest_ShouldBeIdempotent()
    {
        var store = new FakeChannelStore();
        var service = new ChannelService(store);
        var ownerId = Guid.NewGuid();
        var subscriberId = Guid.NewGuid();
        var channel = await service.CreateChannelAsync(ownerId, new("My Channel", "mychannel", null));

        var sub1 = await service.SubscribeAsync(channel.ChannelId, subscriberId);
        var sub2 = await service.SubscribeAsync(channel.ChannelId, subscriberId);

        Assert.Equal(sub1.SubscriptionId, sub2.SubscriptionId);
        Assert.Single(store.Subscriptions);
        var count = await store.CountSubscribersAsync(channel.ChannelId, CancellationToken.None);
        Assert.Equal(1, count);
    }

    [Fact]
    public async Task Unsubscribe_Success_ShouldPauseSubscription_AndDecrementCount()
    {
        var store = new FakeChannelStore();
        var service = new ChannelService(store);
        var ownerId = Guid.NewGuid();
        var subscriberId = Guid.NewGuid();
        var channel = await service.CreateChannelAsync(ownerId, new("My Channel", "mychannel", null));

        await service.SubscribeAsync(channel.ChannelId, subscriberId);
        Assert.Equal(1, await store.CountSubscribersAsync(channel.ChannelId, CancellationToken.None));

        await service.UnsubscribeAsync(channel.ChannelId, subscriberId);

        Assert.Equal(0, await store.CountSubscribersAsync(channel.ChannelId, CancellationToken.None));
        var sub = await service.GetSubscriptionStatusAsync(channel.ChannelId, subscriberId);
        Assert.NotNull(sub);
        Assert.Equal("paused", sub.Status);
    }

    [Fact]
    public async Task Unsubscribe_DuplicateOrNonExistent_ShouldNotThrow()
    {
        var store = new FakeChannelStore();
        var service = new ChannelService(store);
        var ownerId = Guid.NewGuid();
        var subscriberId = Guid.NewGuid();
        var channel = await service.CreateChannelAsync(ownerId, new("My Channel", "mychannel", null));

        // Unsubscribe when never subscribed
        await service.UnsubscribeAsync(channel.ChannelId, subscriberId);

        // Subscribe then unsubscribe twice
        await service.SubscribeAsync(channel.ChannelId, subscriberId);
        await service.UnsubscribeAsync(channel.ChannelId, subscriberId);
        await service.UnsubscribeAsync(channel.ChannelId, subscriberId);

        Assert.Equal(0, await store.CountSubscribersAsync(channel.ChannelId, CancellationToken.None));
    }

    [Fact]
    public async Task GetSubscribedChannels_ShouldReturnOnlyActiveChannels()
    {
        var store = new FakeChannelStore();
        var service = new ChannelService(store);
        var subscriberId = Guid.NewGuid();

        var ch1 = await service.CreateChannelAsync(Guid.NewGuid(), new("Channel 1", "ch1", null));
        var ch2 = await service.CreateChannelAsync(Guid.NewGuid(), new("Channel 2", "ch2", null));

        await service.SubscribeAsync(ch1.ChannelId, subscriberId);
        await service.SubscribeAsync(ch2.ChannelId, subscriberId);

        var list = await service.GetSubscribedChannelsAsync(subscriberId);
        Assert.Equal(2, list.Count);

        // Unsubscribe ch2
        await service.UnsubscribeAsync(ch2.ChannelId, subscriberId);
        list = await service.GetSubscribedChannelsAsync(subscriberId);
        Assert.Single(list);
        Assert.Equal(ch1.ChannelId, list[0].ChannelId);
    }
}
