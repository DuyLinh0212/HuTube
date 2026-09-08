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

    public Task<int> CountChannelsByOwnerAsync(Guid ownerUserId, CancellationToken ct) =>
        db.Channels.CountAsync(x => x.OwnerUserId == ownerUserId && x.Status != "deleted", ct);

    public void AddChannel(Channel channel) => db.Channels.Add(channel);

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
                    owner.Username, owner.Email, owner.DisplayName));
            }
        }

        var members = await db.ChannelMembers
            .Where(m => m.ChannelId == channelId && m.Status == "active")
            .Join(db.Users, m => m.UserId, u => u.UserId, (m, u) => new ChannelMemberInfo(m, u.Username, u.Email, u.DisplayName))
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

    public async Task<List<ChannelInvitationInfo>> GetUserInvitationsWithChannelAsync(string email, Guid userId, CancellationToken ct) =>
        await db.ChannelInvitations
            .Where(i => (i.InvitedEmail == email || i.InvitedUserId == userId) && i.Status == "pending")
            .Join(db.Channels, i => i.ChannelId, c => c.ChannelId, (i, c) => new ChannelInvitationInfo(i, c.Name, c.Handle))
            .OrderByDescending(x => x.Invitation.CreatedAt)
            .ToListAsync(ct);

    public void AddInvitation(ChannelInvitation invitation) => db.ChannelInvitations.Add(invitation);

    public Task<User?> FindUserByEmailAsync(string email, CancellationToken ct) =>
        db.Users.SingleOrDefaultAsync(x => x.Email == email, ct);

    public Task<User?> FindUserByIdAsync(Guid userId, CancellationToken ct) =>
        db.Users.SingleOrDefaultAsync(x => x.UserId == userId, ct);

    public Task SaveAsync(CancellationToken ct) => db.SaveChangesAsync(ct);
}
