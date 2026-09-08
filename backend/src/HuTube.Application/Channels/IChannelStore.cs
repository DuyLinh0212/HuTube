using HuTube.Domain.Channels;
using HuTube.Domain.Users;

namespace HuTube.Application.Channels;

public interface IChannelStore
{
    Task<Channel?> FindChannelAsync(Guid channelId, CancellationToken ct);
    Task<Channel?> FindChannelByHandleAsync(string handle, CancellationToken ct);
    Task<int> CountChannelsByOwnerAsync(Guid ownerUserId, CancellationToken ct);
    void AddChannel(Channel channel);
    Task<ChannelMember?> FindMemberAsync(Guid channelId, Guid userId, CancellationToken ct);
    Task<List<ChannelMemberInfo>> GetMembersWithUserInfoAsync(Guid channelId, CancellationToken ct);
    void AddMember(ChannelMember member);
    void RemoveMember(ChannelMember member);
    Task<ChannelInvitation?> FindInvitationAsync(Guid invitationId, CancellationToken ct);
    Task<ChannelInvitation?> FindPendingInvitationAsync(Guid channelId, string email, CancellationToken ct);
    Task<List<ChannelInvitation>> GetPendingInvitationsAsync(Guid channelId, CancellationToken ct);
    Task<List<ChannelInvitationInfo>> GetUserInvitationsWithChannelAsync(string email, Guid userId, CancellationToken ct);
    void AddInvitation(ChannelInvitation invitation);
    Task<User?> FindUserByEmailAsync(string email, CancellationToken ct);
    Task<User?> FindUserByIdAsync(Guid userId, CancellationToken ct);
    Task SaveAsync(CancellationToken ct);
}

public sealed record ChannelMemberInfo(
    ChannelMember Member,
    string Username,
    string Email,
    string DisplayName);

public sealed record ChannelInvitationInfo(
    ChannelInvitation Invitation,
    string ChannelName,
    string ChannelHandle);
