using HuTube.Domain.Channels;

namespace HuTube.Application.Channels;

public sealed class ChannelService(IChannelStore store)
{
    private const int MaxChannelsPerUser = 10;
    private static readonly HashSet<string> AllowedInvitationRoles = new(StringComparer.OrdinalIgnoreCase)
    {
        ChannelRoles.Manager,
        ChannelRoles.Editor,
        ChannelRoles.Viewer,
        ChannelRoles.CommentModerator,
        "moderator"
    };

    public async Task<ChannelResponse> CreateChannelAsync(Guid userId, CreateChannelRequest request, CancellationToken ct = default)
    {
        var existingCount = await store.CountChannelsByOwnerAsync(userId, ct);
        if (existingCount >= MaxChannelsPerUser)
            throw new ChannelException(400, "CHANNEL_LIMIT_EXCEEDED", $"Mỗi tài khoản chỉ được tạo tối đa {MaxChannelsPerUser} kênh.");

        var normalizedHandle = request.Handle.Trim().ToLowerInvariant();
        var existing = await store.FindChannelByHandleAsync(normalizedHandle, ct);
        if (existing != null)
            throw new ChannelException(409, "HANDLE_ALREADY_EXISTS", "Handle kênh đã tồn tại.");

        var channel = new Channel
        {
            ChannelId = Guid.NewGuid(),
            OwnerUserId = userId,
            Name = request.Name.Trim(),
            Handle = normalizedHandle,
            Description = request.Description?.Trim(),
            Status = "active",
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };

        store.AddChannel(channel);
        await store.SaveAsync(ct);

        return ToResponse(channel);
    }

    public async Task<ChannelResponse> GetChannelAsync(Guid channelId, CancellationToken ct = default)
    {
        var channel = await store.FindChannelAsync(channelId, ct)
            ?? throw new ChannelException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");
        return ToResponse(channel);
    }

    public async Task<ChannelResponse> GetChannelByHandleAsync(string handle, CancellationToken ct = default)
    {
        var channel = await store.FindChannelByHandleAsync(handle.Trim().ToLowerInvariant(), ct)
            ?? throw new ChannelException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");
        return ToResponse(channel);
    }

    public async Task<ChannelResponse> UpdateChannelAsync(Guid channelId, Guid actorUserId, UpdateChannelRequest request, CancellationToken ct = default)
    {
        var channel = await store.FindChannelAsync(channelId, ct)
            ?? throw new ChannelException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");

        var member = await store.FindMemberAsync(channelId, actorUserId, ct);
        var isOwner = channel.OwnerUserId == actorUserId || member?.RoleCode == ChannelRoles.Owner;
        var isManager = member?.RoleCode == ChannelRoles.Manager;

        if (!isOwner && !isManager)
            throw new ChannelException(403, "FORBIDDEN", "Bạn không có quyền chỉnh sửa kênh này.");

        if (!string.IsNullOrWhiteSpace(request.Name)) channel.Name = request.Name.Trim();
        if (request.Description != null) channel.Description = request.Description.Trim();
        if (request.AvatarUrl != null) channel.AvatarUrl = request.AvatarUrl;
        if (request.BannerUrl != null) channel.BannerUrl = request.BannerUrl;
        channel.UpdatedAt = DateTimeOffset.UtcNow;

        await store.SaveAsync(ct);
        return ToResponse(channel);
    }

    public async Task DeleteChannelAsync(Guid channelId, Guid actorUserId, CancellationToken ct = default)
    {
        var channel = await store.FindChannelAsync(channelId, ct)
            ?? throw new ChannelException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");

        if (channel.OwnerUserId != actorUserId)
            throw new ChannelException(403, "FORBIDDEN", "Chỉ chủ sở hữu kênh mới có quyền xóa kênh.");

        channel.Status = "deleted";
        channel.UpdatedAt = DateTimeOffset.UtcNow;
        await store.SaveAsync(ct);
    }

    public async Task<ChannelInvitationResponse> InviteMemberAsync(Guid channelId, Guid actorUserId, InviteMemberRequest request, CancellationToken ct = default)
    {
        var channel = await store.FindChannelAsync(channelId, ct)
            ?? throw new ChannelException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");

        var member = await store.FindMemberAsync(channelId, actorUserId, ct);
        var isOwner = channel.OwnerUserId == actorUserId || member?.RoleCode == ChannelRoles.Owner;
        var isManager = member?.RoleCode == ChannelRoles.Manager;

        if (!isOwner && !isManager)
            throw new ChannelException(403, "FORBIDDEN", "Bạn không có quyền mời thành viên vào kênh.");

        var roleCode = request.RoleCode.Trim().ToLowerInvariant();
        if (roleCode == "moderator") roleCode = ChannelRoles.CommentModerator;

        if (!AllowedInvitationRoles.Contains(roleCode))
            throw new ChannelException(400, "INVALID_ROLE", "Vai trò mời không hợp lệ.");

        if (roleCode == ChannelRoles.Owner)
            throw new ChannelException(400, "CANNOT_INVITE_OWNER", "Không thể mời vai trò chủ sở hữu.");

        var normalizedEmail = request.Email.Trim().ToLowerInvariant();
        var targetUser = await store.FindUserByEmailAsync(normalizedEmail, ct)
            ?? throw new ChannelException(404, "USER_NOT_FOUND", "Không tìm thấy người dùng với email này.");

        if (targetUser.UserId == channel.OwnerUserId)
            throw new ChannelException(400, "ALREADY_OWNER", "Người dùng này là chủ sở hữu kênh.");

        var existingMember = await store.FindMemberAsync(channelId, targetUser.UserId, ct);
        if (existingMember != null && existingMember.Status == "active")
            throw new ChannelException(400, "ALREADY_MEMBER", "Người dùng đã là thành viên của kênh.");

        var existingInvite = await store.FindPendingInvitationAsync(channelId, normalizedEmail, ct);
        if (existingInvite != null && existingInvite.IsPending(DateTimeOffset.UtcNow))
            throw new ChannelException(400, "INVITATION_ALREADY_SENT", "Đã có lời mời đang chờ xử lý cho người dùng này.");

        var invitation = new ChannelInvitation
        {
            ChannelInvitationId = Guid.NewGuid(),
            ChannelId = channelId,
            InvitedUserId = targetUser.UserId,
            InvitedEmail = normalizedEmail,
            InvitedByUserId = actorUserId,
            RoleCode = roleCode,
            Status = "pending",
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(7),
            CreatedAt = DateTimeOffset.UtcNow
        };

        store.AddInvitation(invitation);
        await store.SaveAsync(ct);

        return new ChannelInvitationResponse(
            invitation.ChannelInvitationId,
            channel.ChannelId,
            channel.Name,
            channel.Handle,
            invitation.InvitedUserId,
            invitation.InvitedEmail,
            invitation.InvitedByUserId,
            invitation.RoleCode,
            invitation.Status,
            invitation.ExpiresAt,
            invitation.CreatedAt);
    }

    public async Task<ChannelMemberResponse> AcceptInvitationAsync(Guid invitationId, Guid actorUserId, CancellationToken ct = default)
    {
        var invitation = await store.FindInvitationAsync(invitationId, ct)
            ?? throw new ChannelException(404, "INVITATION_NOT_FOUND", "Không tìm thấy lời mời.");

        var user = await store.FindUserByIdAsync(actorUserId, ct)
            ?? throw new ChannelException(404, "USER_NOT_FOUND", "Người dùng không tồn tại.");

        var isTarget = invitation.InvitedUserId == actorUserId ||
            string.Equals(invitation.InvitedEmail, user.Email, StringComparison.OrdinalIgnoreCase);

        if (!isTarget)
            throw new ChannelException(403, "FORBIDDEN", "Lời mời này không dành cho bạn.");

        if (invitation.Status == "revoked")
            throw new ChannelException(400, "INVITATION_REVOKED", "Lời mời đã bị thu hồi.");

        if (invitation.Status != "pending" || invitation.ExpiresAt <= DateTimeOffset.UtcNow)
            throw new ChannelException(400, "INVITATION_EXPIRED", "Lời mời đã hết hạn hoặc đã được xử lý.");

        var existingMember = await store.FindMemberAsync(invitation.ChannelId, actorUserId, ct);
        if (existingMember != null)
        {
            existingMember.RoleCode = invitation.RoleCode;
            existingMember.Status = "active";
            existingMember.UpdatedAt = DateTimeOffset.UtcNow;
        }
        else
        {
            existingMember = new ChannelMember
            {
                ChannelMemberId = Guid.NewGuid(),
                ChannelId = invitation.ChannelId,
                UserId = actorUserId,
                RoleCode = invitation.RoleCode,
                Status = "active",
                JoinedAt = DateTimeOffset.UtcNow,
                UpdatedAt = DateTimeOffset.UtcNow
            };
            store.AddMember(existingMember);
        }

        invitation.Status = "accepted";
        invitation.RespondedAt = DateTimeOffset.UtcNow;
        await store.SaveAsync(ct);

        return new ChannelMemberResponse(
            existingMember.ChannelMemberId,
            existingMember.ChannelId,
            user.UserId,
            user.Username,
            user.Email,
            user.DisplayName,
            existingMember.RoleCode,
            existingMember.Status,
            existingMember.JoinedAt);
    }

    public async Task DeclineInvitationAsync(Guid invitationId, Guid actorUserId, CancellationToken ct = default)
    {
        var invitation = await store.FindInvitationAsync(invitationId, ct)
            ?? throw new ChannelException(404, "INVITATION_NOT_FOUND", "Không tìm thấy lời mời.");

        var user = await store.FindUserByIdAsync(actorUserId, ct)
            ?? throw new ChannelException(404, "USER_NOT_FOUND", "Người dùng không tồn tại.");

        var isTarget = invitation.InvitedUserId == actorUserId ||
            string.Equals(invitation.InvitedEmail, user.Email, StringComparison.OrdinalIgnoreCase);

        if (!isTarget)
            throw new ChannelException(403, "FORBIDDEN", "Lời mời này không dành cho bạn.");

        if (invitation.Status != "pending")
            throw new ChannelException(400, "INVITATION_INVALID", "Lời mời không ở trạng thái chờ phản hồi.");

        invitation.Status = "declined";
        invitation.RespondedAt = DateTimeOffset.UtcNow;
        await store.SaveAsync(ct);
    }

    public async Task RevokeInvitationAsync(Guid channelId, Guid invitationId, Guid actorUserId, CancellationToken ct = default)
    {
        var channel = await store.FindChannelAsync(channelId, ct)
            ?? throw new ChannelException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");

        var member = await store.FindMemberAsync(channelId, actorUserId, ct);
        var isOwner = channel.OwnerUserId == actorUserId || member?.RoleCode == ChannelRoles.Owner;
        var isManager = member?.RoleCode == ChannelRoles.Manager;

        if (!isOwner && !isManager)
            throw new ChannelException(403, "FORBIDDEN", "Bạn không có quyền thu hồi lời mời.");

        var invitation = await store.FindInvitationAsync(invitationId, ct)
            ?? throw new ChannelException(404, "INVITATION_NOT_FOUND", "Không tìm thấy lời mời.");

        if (invitation.ChannelId != channelId)
            throw new ChannelException(400, "INVALID_INVITATION", "Lời mời không thuộc kênh này.");

        if (invitation.Status != "pending")
            throw new ChannelException(400, "INVITATION_NOT_PENDING", "Chỉ có thể thu hồi lời mời đang chờ.");

        invitation.Status = "revoked";
        invitation.RespondedAt = DateTimeOffset.UtcNow;
        await store.SaveAsync(ct);
    }

    public async Task<List<ChannelMemberResponse>> GetMembersAsync(Guid channelId, Guid actorUserId, CancellationToken ct = default)
    {
        var channel = await store.FindChannelAsync(channelId, ct)
            ?? throw new ChannelException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");

        var member = await store.FindMemberAsync(channelId, actorUserId, ct);
        if (channel.OwnerUserId != actorUserId && member == null)
            throw new ChannelException(403, "FORBIDDEN", "Bạn không phải thành viên của kênh này.");

        var members = await store.GetMembersWithUserInfoAsync(channelId, ct);
        return members.Select(m => new ChannelMemberResponse(
            m.Member.ChannelMemberId,
            m.Member.ChannelId,
            m.Member.UserId,
            m.Username,
            m.Email,
            m.DisplayName,
            m.Member.RoleCode,
            m.Member.Status,
            m.Member.JoinedAt)).ToList();
    }

    public async Task<List<ChannelInvitationResponse>> GetPendingInvitationsAsync(Guid channelId, Guid actorUserId, CancellationToken ct = default)
    {
        var channel = await store.FindChannelAsync(channelId, ct)
            ?? throw new ChannelException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");

        var member = await store.FindMemberAsync(channelId, actorUserId, ct);
        var isOwner = channel.OwnerUserId == actorUserId || member?.RoleCode == ChannelRoles.Owner;
        var isManager = member?.RoleCode == ChannelRoles.Manager;

        if (!isOwner && !isManager)
            throw new ChannelException(403, "FORBIDDEN", "Bạn không có quyền xem danh sách lời mời.");

        var invites = await store.GetPendingInvitationsAsync(channelId, ct);
        return invites.Select(i => new ChannelInvitationResponse(
            i.ChannelInvitationId,
            channel.ChannelId,
            channel.Name,
            channel.Handle,
            i.InvitedUserId,
            i.InvitedEmail,
            i.InvitedByUserId,
            i.RoleCode,
            i.Status,
            i.ExpiresAt,
            i.CreatedAt)).ToList();
    }

    public async Task<List<ChannelInvitationResponse>> GetMyInvitationsAsync(Guid actorUserId, CancellationToken ct = default)
    {
        var user = await store.FindUserByIdAsync(actorUserId, ct)
            ?? throw new ChannelException(404, "USER_NOT_FOUND", "Người dùng không tồn tại.");

        var invites = await store.GetUserInvitationsWithChannelAsync(user.Email, actorUserId, ct);
        return invites.Select(i => new ChannelInvitationResponse(
            i.Invitation.ChannelInvitationId,
            i.Invitation.ChannelId,
            i.ChannelName,
            i.ChannelHandle,
            i.Invitation.InvitedUserId,
            i.Invitation.InvitedEmail,
            i.Invitation.InvitedByUserId,
            i.Invitation.RoleCode,
            i.Invitation.Status,
            i.Invitation.ExpiresAt,
            i.Invitation.CreatedAt)).ToList();
    }

    public async Task<ChannelMemberResponse> ChangeMemberRoleAsync(Guid channelId, Guid targetUserId, Guid actorUserId, ChangeMemberRoleRequest request, CancellationToken ct = default)
    {
        var channel = await store.FindChannelAsync(channelId, ct)
            ?? throw new ChannelException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");

        var actorMember = await store.FindMemberAsync(channelId, actorUserId, ct);
        var isOwner = channel.OwnerUserId == actorUserId || actorMember?.RoleCode == ChannelRoles.Owner;
        var isManager = actorMember?.RoleCode == ChannelRoles.Manager;

        if (!isOwner && !isManager)
            throw new ChannelException(403, "FORBIDDEN", "Bạn không có quyền thay đổi vai trò thành viên.");

        if (targetUserId == channel.OwnerUserId)
            throw new ChannelException(400, "CANNOT_CHANGE_OWNER_ROLE", "Không thể thay đổi vai trò của chủ sở hữu.");

        var targetMember = await store.FindMemberAsync(channelId, targetUserId, ct)
            ?? throw new ChannelException(404, "MEMBER_NOT_FOUND", "Không tìm thấy thành viên trong kênh.");

        if (isManager && targetMember.RoleCode == ChannelRoles.Manager)
            throw new ChannelException(403, "FORBIDDEN", "Quản trị viên không thể thay đổi vai trò của quản trị viên khác.");

        var newRole = request.RoleCode.Trim().ToLowerInvariant();
        if (newRole == "moderator") newRole = ChannelRoles.CommentModerator;

        if (!AllowedInvitationRoles.Contains(newRole) || newRole == ChannelRoles.Owner)
            throw new ChannelException(400, "INVALID_ROLE", "Vai trò mới không hợp lệ.");

        targetMember.RoleCode = newRole;
        targetMember.UpdatedAt = DateTimeOffset.UtcNow;
        await store.SaveAsync(ct);

        var targetUser = await store.FindUserByIdAsync(targetUserId, ct);
        return new ChannelMemberResponse(
            targetMember.ChannelMemberId,
            channelId,
            targetUserId,
            targetUser?.Username ?? "",
            targetUser?.Email ?? "",
            targetUser?.DisplayName ?? "",
            targetMember.RoleCode,
            targetMember.Status,
            targetMember.JoinedAt);
    }

    public async Task RemoveMemberAsync(Guid channelId, Guid targetUserId, Guid actorUserId, CancellationToken ct = default)
    {
        var channel = await store.FindChannelAsync(channelId, ct)
            ?? throw new ChannelException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");

        if (targetUserId == channel.OwnerUserId)
            throw new ChannelException(400, "CANNOT_REMOVE_OWNER", "Không thể xóa chủ sở hữu khỏi kênh.");

        var targetMember = await store.FindMemberAsync(channelId, targetUserId, ct)
            ?? throw new ChannelException(404, "MEMBER_NOT_FOUND", "Không tìm thấy thành viên trong kênh.");

        if (actorUserId == targetUserId)
        {
            // Self leave
            store.RemoveMember(targetMember);
            await store.SaveAsync(ct);
            return;
        }

        var actorMember = await store.FindMemberAsync(channelId, actorUserId, ct);
        var isOwner = channel.OwnerUserId == actorUserId || actorMember?.RoleCode == ChannelRoles.Owner;
        var isManager = actorMember?.RoleCode == ChannelRoles.Manager;

        if (!isOwner && !isManager)
            throw new ChannelException(403, "FORBIDDEN", "Bạn không có quyền xóa thành viên.");

        if (isManager && (targetMember.RoleCode == ChannelRoles.Manager || targetMember.RoleCode == ChannelRoles.Owner))
            throw new ChannelException(403, "FORBIDDEN", "Quản trị viên không thể xóa quản trị viên khác hoặc chủ sở hữu.");

        store.RemoveMember(targetMember);
        await store.SaveAsync(ct);
    }

    private static ChannelResponse ToResponse(Channel channel) =>
        new(channel.ChannelId, channel.OwnerUserId, channel.Name, channel.Handle,
            channel.Description, channel.AvatarUrl, channel.BannerUrl, channel.Status, channel.CreatedAt);
}
