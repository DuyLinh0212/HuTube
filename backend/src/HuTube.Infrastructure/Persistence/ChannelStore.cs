using HuTube.Application.Channels;
using HuTube.Domain.Channels;
using HuTube.Domain.Users;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Persistence;

public sealed class ChannelStore(HuTubeDbContext db) : IChannelStore
{
    public Task<Channel?> FindChannelAsync(Guid channelId, CancellationToken ct) =>
        db.Channels.SingleOrDefaultAsync(x => x.ChannelId == channelId, ct);

    public Task<Channel?> FindChannelByHandleAsync(string handle, CancellationToken ct) =>
        db.Channels.SingleOrDefaultAsync(x => x.Handle == handle, ct);

    public Task<Channel?> FindOwnedChannelAsync(Guid ownerUserId, CancellationToken ct) =>
        db.Channels.SingleOrDefaultAsync(x => x.OwnerUserId == ownerUserId && x.Status != "deleted", ct);

    public Task<List<Channel>> GetAccessibleChannelsAsync(Guid userId, CancellationToken ct) =>
        db.Channels
            .Where(channel => channel.Status == "active" && (channel.OwnerUserId == userId ||
                db.ChannelMembers.Any(member => member.ChannelId == channel.ChannelId && member.UserId == userId && member.Status == "active")))
            .OrderBy(channel => channel.OwnerUserId == userId ? 0 : 1)
            .ThenBy(channel => channel.Name)
            .ToListAsync(ct);

    public Task<int> CountChannelsByOwnerAsync(Guid ownerUserId, CancellationToken ct) =>
        db.Channels.CountAsync(x => x.OwnerUserId == ownerUserId && x.Status != "deleted", ct);

    public void AddChannel(Channel channel) => db.Channels.Add(channel);

    public void AddChannelQuota(ChannelQuota quota) => db.ChannelQuotas.Add(quota);

    public Task<ChannelMember?> FindMemberAsync(Guid channelId, Guid userId, CancellationToken ct) =>
        db.ChannelMembers.SingleOrDefaultAsync(x => x.ChannelId == channelId && x.UserId == userId && x.Status == "active", ct);

    public async Task<List<ChannelMemberInfo>> GetMembersWithUserInfoAsync(Guid channelId, CancellationToken ct)
    {
        var list = new List<ChannelMemberInfo>();
        var channel = await db.Channels.SingleOrDefaultAsync(c => c.ChannelId == channelId, ct);
        if (channel != null)
        {
            var owner = await db.Users.SingleOrDefaultAsync(u => u.UserId == channel.OwnerUserId, ct);
            if (owner != null)
            {
                list.Add(new ChannelMemberInfo(
                    new ChannelMember { ChannelId = channelId, UserId = owner.UserId, RoleCode = ChannelRoles.Owner, Status = "active", JoinedAt = channel.CreatedAt },
                    owner.Username, owner.Email, owner.DisplayName, owner.AvatarUrl));
            }
        }

        var members = await db.ChannelMembers
            .Where(m => m.ChannelId == channelId && m.Status == "active")
            .Join(db.Users, m => m.UserId, u => u.UserId, (m, u) => new ChannelMemberInfo(m, u.Username, u.Email, u.DisplayName, u.AvatarUrl))
            .ToListAsync(ct);

        list.AddRange(members);
        return list;
    }

    public void AddMember(ChannelMember member) => db.ChannelMembers.Add(member);

    public void RemoveMember(ChannelMember member) => db.ChannelMembers.Remove(member);

    public Task<ChannelInvitation?> FindInvitationAsync(Guid invitationId, CancellationToken ct) =>
        db.ChannelInvitations.SingleOrDefaultAsync(x => x.ChannelInvitationId == invitationId, ct);

    public Task<ChannelInvitation?> FindPendingInvitationAsync(Guid channelId, string email, CancellationToken ct) =>
        db.ChannelInvitations.SingleOrDefaultAsync(x => x.ChannelId == channelId && x.InvitedEmail == email && x.Status == "pending", ct);

    public Task<List<ChannelInvitation>> GetPendingInvitationsAsync(Guid channelId, CancellationToken ct) =>
        db.ChannelInvitations.Where(x => x.ChannelId == channelId && x.Status == "pending").OrderByDescending(x => x.CreatedAt).ToListAsync(ct);

    public async Task<List<ChannelInvitationInfo>> GetUserInvitationsWithChannelAsync(string email, Guid userId, CancellationToken ct)
    {
        var rows = await db.ChannelInvitations
            .Where(i => (i.InvitedEmail == email || i.InvitedUserId == userId) && i.Status == "pending")
            .Join(db.Channels.Where(c => c.Status == "active"), i => i.ChannelId, c => c.ChannelId, (i, c) => new { Invitation = i, ChannelName = c.Name, ChannelHandle = c.Handle })
            .OrderByDescending(x => x.Invitation.CreatedAt)
            .ToListAsync(ct);
        return rows.Select(x => new ChannelInvitationInfo(x.Invitation, x.ChannelName, x.ChannelHandle)).ToList();
    }

    public void AddInvitation(ChannelInvitation invitation) => db.ChannelInvitations.Add(invitation);

    public Task<User?> FindUserByEmailAsync(string email, CancellationToken ct) =>
        db.Users.SingleOrDefaultAsync(x => x.Email == email, ct);

    public Task<User?> FindUserByIdAsync(Guid userId, CancellationToken ct) =>
        db.Users.SingleOrDefaultAsync(x => x.UserId == userId, ct);

    public Task<Subscription?> FindSubscriptionAsync(Guid userId, Guid channelId, CancellationToken ct) =>
        db.Subscriptions.SingleOrDefaultAsync(x => x.UserId == userId && x.ChannelId == channelId, ct);

    public void AddSubscription(Subscription subscription) => db.Subscriptions.Add(subscription);

    public Task<long> CountSubscribersAsync(Guid channelId, CancellationToken ct) =>
        db.Subscriptions.LongCountAsync(x => x.ChannelId == channelId && x.Status == "active", ct);

    public Task<long> CountPublishedVideosAsync(Guid channelId, CancellationToken ct) =>
        db.Videos.LongCountAsync(x => x.ChannelId == channelId && x.Status == "published" &&
            x.Visibility == "public" && x.ModerationStatus == "approved", ct);

    public async Task<List<SubscribedChannelResponse>> GetSubscribedChannelsAsync(Guid userId, CancellationToken ct)
    {
        return await db.Subscriptions
            .Where(s => s.UserId == userId && s.Status == "active")
            .Join(db.Channels.Where(c => c.Status == "active"),
                s => s.ChannelId,
                c => c.ChannelId,
                (s, c) => new { s.SubscribedAt, c.ChannelId, c.Name, c.Handle, c.AvatarUrl })
            .OrderByDescending(x => x.SubscribedAt)
            .Select(x => new SubscribedChannelResponse(
                x.ChannelId,
                x.Name,
                x.Handle,
                x.AvatarUrl,
                // Count subscribers directly (can be optimized later using a cached field if needed)
                db.Subscriptions.LongCount(sub => sub.ChannelId == x.ChannelId && sub.Status == "active"),
                x.SubscribedAt))
            .ToListAsync(ct);
    }

    public Task SaveAsync(CancellationToken ct) => db.SaveChangesAsync(ct);
}
