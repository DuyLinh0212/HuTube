using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Application.Notifications;
using HuTube.Application.Plans;
using HuTube.Application.Rbac;
using HuTube.Domain.Channels;

namespace HuTube.Application.Channels;

public sealed class ChannelService(IChannelStore store, RbacService? audit = null, IAuthEmailSender? emailSender = null,
    AuthOptions? authOptions = null, INotificationService? notifications = null, IPlanService? plans = null)
{
    private const int MaxChannelsPerUser = 1;

    public static IReadOnlyList<ChannelRoleResponse> Roles { get; } =
    [
        new(ChannelRoles.Manager, "Quản lý", "Quản lý hồ sơ, nội dung, thành viên và cài đặt kênh; không thể xóa kênh hoặc thay chủ sở hữu.", ChannelPermissions.ForRole(ChannelRoles.Manager)),
        new(ChannelRoles.Editor, "Biên tập viên", "Tải lên, chỉnh sửa nội dung, playlist và xem dữ liệu nội dung.", ChannelPermissions.ForRole(ChannelRoles.Editor)),
        new(ChannelRoles.Moderator, "Kiểm duyệt viên", "Quản lý cộng đồng và bình luận, không được chỉnh sửa video hay cài đặt kênh.", ChannelPermissions.ForRole(ChannelRoles.Moderator)),
        new(ChannelRoles.Viewer, "Người xem", "Chỉ xem dashboard và dữ liệu nội bộ được cấp.", ChannelPermissions.ForRole(ChannelRoles.Viewer))
    ];

    public async Task<ChannelResponse> CreateChannelAsync(Guid userId, CreateChannelRequest request, CancellationToken ct = default)
    {
        var existingCount = await store.CountChannelsByOwnerAsync(userId, ct);
        if (existingCount >= MaxChannelsPerUser)
            throw new ChannelException(409, "CHANNEL_LIMIT_EXCEEDED", "Mỗi tài khoản chỉ được tạo tối đa một kênh.");

        if (string.IsNullOrWhiteSpace(request.Name))
            throw new ChannelException(400, "INVALID_CHANNEL_NAME", "Tên kênh không được để trống.");

        if (!Channel.IsValidHandle(request.Handle))
            throw new ChannelException(400, "INVALID_HANDLE", "Handle cần 3–50 ký tự, chỉ gồm chữ, số, dấu gạch dưới, gạch ngang hoặc dấu chấm.");

        var normalizedHandle = Channel.NormalizeHandle(request.Handle);
        if (await store.FindChannelByHandleAsync(normalizedHandle, ct) != null)
            throw new ChannelException(409, "HANDLE_ALREADY_EXISTS", "Handle này đã có người sử dụng. Vui lòng chọn handle khác.");

        var now = DateTimeOffset.UtcNow;
        var channel = new Channel
        {
            ChannelId = Guid.NewGuid(),
            OwnerUserId = userId,
            Name = request.Name.Trim(),
            Handle = normalizedHandle,
            Description = NormalizeOptional(request.Description),
            AvatarUrl = NormalizeOptional(request.AvatarUrl),
            BannerUrl = NormalizeOptional(request.BannerUrl),
            ContactEmail = NormalizeOptional(request.ContactEmail)?.ToLowerInvariant(),
            Settings = "{}",
            Status = "active",
            CreatedAt = now,
            UpdatedAt = now
        };

        store.AddChannel(channel);
        // Persist the principal first because ChannelQuota intentionally has no domain
        // navigation property and EF cannot infer insert ordering from the FK value alone.
        await store.SaveAsync(ct);
        var storageLimit = plans == null
            ? ChannelQuotaRules.DefaultStorageLimit
            : await plans.GetEffectiveStorageLimitAsync(userId, ct) ?? ChannelQuotaRules.DefaultStorageLimit;
        store.AddChannelQuota(new ChannelQuota
        {
            ChannelQuotaId = Guid.NewGuid(),
            ChannelId = channel.ChannelId,
            StorageLimit = storageLimit,
            StorageUsed = 0,
            UpdatedAt = now
        });
        await store.SaveAsync(ct);
        await WriteAuditAsync(userId, "channel.created", channel.ChannelId, null, ct);

        return ToResponse(channel, ChannelRoles.Owner);
    }

    public async Task<ChannelResponse?> GetMyChannelAsync(Guid userId, CancellationToken ct = default)
    {
        var channel = await store.FindOwnedChannelAsync(userId, ct);
        return channel == null ? null : ToResponse(channel, ChannelRoles.Owner);
    }

    public async Task<ChannelResponse> GetChannelAsync(Guid channelId, Guid? actorUserId = null, CancellationToken ct = default)
    {
        var channel = await RequireChannelAsync(channelId, ct);
        return ToResponse(channel, await ResolveRoleAsync(channel, actorUserId, ct));
    }

    public async Task<ChannelResponse> GetChannelByHandleAsync(string handle, Guid? actorUserId = null, CancellationToken ct = default)
    {
        if (!Channel.IsValidHandle(handle))
            throw new ChannelException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");

        var channel = await store.FindChannelByHandleAsync(Channel.NormalizeHandle(handle), ct)
            ?? throw new ChannelException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");
        return ToResponse(channel, await ResolveRoleAsync(channel, actorUserId, ct));
    }

    public async Task<CheckHandleResponse> CheckHandleAsync(string handle, Guid? currentChannelId = null, CancellationToken ct = default)
    {
        if (!Channel.IsValidHandle(handle))
            return new(handle, false, "Handle không hợp lệ (3–50 ký tự: chữ cái, số, _, -, .).");

        var normalized = Channel.NormalizeHandle(handle);
        var existing = await store.FindChannelByHandleAsync(normalized, ct);
        var available = existing == null || existing.ChannelId == currentChannelId;
        return new(normalized, available, available ? "Handle khả dụng." : "Handle này đã có người sử dụng.");
    }

    public async Task<ChannelResponse> UpdateChannelAsync(Guid channelId, Guid actorUserId, UpdateChannelRequest request, CancellationToken ct = default)
    {
        var channel = await RequireChannelAsync(channelId, ct);
        var role = await RequireRoleAsync(channel, actorUserId, ct);

        var updatesProfile = request.Name != null || request.Handle != null || request.Description != null || request.ContactEmail != null;
        var updatesBranding = request.AvatarUrl != null || request.BannerUrl != null || request.WatermarkUrl != null;
        if (updatesProfile) RequirePermission(role, ChannelPermissions.EditProfile, "Bạn không có quyền chỉnh sửa hồ sơ kênh.");
        if (updatesBranding) RequirePermission(role, ChannelPermissions.EditBranding, "Bạn không có quyền chỉnh sửa thương hiệu kênh.");
        if (request.Settings != null) RequirePermission(role, ChannelPermissions.SettingEdit, "Bạn không có quyền chỉnh sửa cài đặt kênh.");

        if (request.Name != null)
        {
            var name = request.Name.Trim();
            if (name.Length is < 1 or > 100)
                throw new ChannelException(400, "INVALID_CHANNEL_NAME", "Tên kênh không được để trống và tối đa 100 ký tự.");
            channel.Name = name;
        }

        if (request.Handle != null)
        {
            if (!Channel.IsValidHandle(request.Handle))
                throw new ChannelException(400, "INVALID_HANDLE", "Handle cần 3–50 ký tự, chỉ gồm chữ, số, dấu gạch dưới, gạch ngang hoặc dấu chấm.");
            var normalized = Channel.NormalizeHandle(request.Handle);
            var existing = await store.FindChannelByHandleAsync(normalized, ct);
            if (existing != null && existing.ChannelId != channelId)
                throw new ChannelException(409, "HANDLE_ALREADY_EXISTS", "Handle này đã có người sử dụng. Vui lòng chọn handle khác.");
            channel.Handle = normalized;
        }

        if (request.Description != null) channel.Description = NormalizeOptional(request.Description);
        if (request.AvatarUrl != null) channel.AvatarUrl = NormalizeOptional(request.AvatarUrl);
        if (request.BannerUrl != null) channel.BannerUrl = NormalizeOptional(request.BannerUrl);
        if (request.ContactEmail != null) channel.ContactEmail = NormalizeOptional(request.ContactEmail)?.ToLowerInvariant();
        if (request.WatermarkUrl != null) channel.WatermarkUrl = NormalizeOptional(request.WatermarkUrl);
        if (request.Settings != null) channel.Settings = ValidateSettings(request.Settings);

        channel.UpdatedAt = DateTimeOffset.UtcNow;
        await store.SaveAsync(ct);
        await WriteAuditAsync(actorUserId, "channel.updated", channel.ChannelId, null, ct);
        return ToResponse(channel, role);
    }

    public async Task EnsureBrandingPermissionAsync(Guid channelId, Guid actorUserId, CancellationToken ct = default)
    {
        var channel = await RequireChannelAsync(channelId, ct);
        var role = await RequireRoleAsync(channel, actorUserId, ct);
        RequirePermission(role, ChannelPermissions.EditBranding, "Bạn không có quyền chỉnh sửa thương hiệu kênh.");
    }

    public async Task DeleteChannelAsync(Guid channelId, Guid actorUserId, CancellationToken ct = default)
    {
        var channel = await RequireChannelAsync(channelId, ct);
        var role = await RequireRoleAsync(channel, actorUserId, ct);
        RequirePermission(role, ChannelPermissions.Delete, "Chỉ chủ sở hữu kênh mới có quyền xóa kênh.");

        channel.SoftDelete(DateTimeOffset.UtcNow);
        await store.SaveAsync(ct);
        await WriteAuditAsync(actorUserId, "channel.deleted", channel.ChannelId, null, ct);
    }

    public async Task<ChannelInvitationResponse> InviteMemberAsync(Guid channelId, Guid actorUserId, InviteMemberRequest request, CancellationToken ct = default)
    {
        var channel = await RequireActiveChannelAsync(channelId, ct);
        var actorRole = await RequireRoleAsync(channel, actorUserId, ct);
        RequirePermission(actorRole, ChannelPermissions.MemberInvite, "Bạn không có quyền mời thành viên vào kênh.");

        var roleCode = NormalizeRole(request.RoleCode);
        if (!ChannelRoles.AssignableMemberRoles.Contains(roleCode, StringComparer.OrdinalIgnoreCase))
            throw new ChannelException(400, "INVALID_ROLE", "Vai trò mời không hợp lệ.");
        if (actorRole == ChannelRoles.Manager && roleCode == ChannelRoles.Manager)
            throw new ChannelException(403, "ROLE_ESCALATION_DENIED", "Quản lý không thể cấp vai trò quản lý cho người khác.");

        var normalizedEmail = request.Email.Trim().ToLowerInvariant();
        var targetUser = await store.FindUserByEmailAsync(normalizedEmail, ct)
            ?? throw new ChannelException(404, "USER_NOT_FOUND", "Không tìm thấy người dùng với email này.");
        if (targetUser.UserId == channel.OwnerUserId)
            throw new ChannelException(400, "ALREADY_OWNER", "Người dùng này là chủ sở hữu kênh.");

        var existingMember = await store.FindMemberAsync(channelId, targetUser.UserId, ct);
        if (existingMember?.Status == "active")
            throw new ChannelException(409, "ALREADY_MEMBER", "Người dùng đã là thành viên của kênh.");

        var existingInvite = await store.FindPendingInvitationAsync(channelId, normalizedEmail, ct);
        if (existingInvite?.IsPending(DateTimeOffset.UtcNow) == true)
            throw new ChannelException(409, "INVITATION_ALREADY_SENT", "Đã có lời mời đang chờ xử lý cho người dùng này.");

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
        if (emailSender != null)
        {
            var webBaseUrl = string.IsNullOrWhiteSpace(authOptions?.WebBaseUrl)
                ? "http://localhost:4200"
                : authOptions.WebBaseUrl.TrimEnd('/');
            var invitationUrl = $"{webBaseUrl}/channel-invitations?invitation={invitation.ChannelInvitationId}";
            var subject = $"Bạn được mời tham gia kênh {channel.Name} trên HuTube";
            var body = $"Xin chào {targetUser.DisplayName},\n\n" +
                       $"Bạn được mời tham gia kênh \"{channel.Name}\" với vai trò {RoleName(roleCode)}.\n" +
                       $"Lời mời có hiệu lực đến {invitation.ExpiresAt:dd/MM/yyyy HH:mm} (giờ UTC).\n\n" +
                       $"Mở HuTube để xem và phản hồi lời mời:\n{invitationUrl}\n\n" +
                       "Nếu bạn không mong đợi email này, bạn có thể bỏ qua nó.";
            try
            {
                await emailSender.SendAsync(targetUser.Email, subject, body, ct);
            }
            catch
            {
                // Delivery is best-effort; the persisted invitation remains the source of truth.
            }
        }
        await WriteAuditAsync(actorUserId, "channel.member_invited", channel.ChannelId, $"role={roleCode}", ct);
        if (notifications != null)
        {
            try
            {
                await notifications.PublishInvitationAsync(targetUser.UserId,
                    new InvitationSignal(invitation.ChannelInvitationId, channel.ChannelId, channel.Name, roleCode, invitation.ExpiresAt), ct);
            }
            catch
            {
                // Clients can always read the invitation from the backend after reconnecting.
            }
        }
        return ToInvitationResponse(invitation, channel);
    }

    public async Task<ChannelMemberResponse> AcceptInvitationAsync(Guid invitationId, Guid actorUserId, CancellationToken ct = default)
    {
        var invitation = await RequireInvitationAsync(invitationId, ct);
        await RequireActiveChannelAsync(invitation.ChannelId, ct);
        var user = await store.FindUserByIdAsync(actorUserId, ct)
            ?? throw new ChannelException(404, "USER_NOT_FOUND", "Người dùng không tồn tại.");
        RequireInvitationTarget(invitation, user.UserId, user.Email);

        if (invitation.Status == "expired")
            throw new ChannelException(410, "INVITATION_EXPIRED", "Lời mời đã hết hạn.");
        if (invitation.Status == "revoked")
            throw new ChannelException(400, "INVITATION_REVOKED", "Lời mời đã bị thu hồi.");
        if (invitation.Status != "pending")
            throw new ChannelException(409, "INVITATION_ALREADY_PROCESSED", "Lời mời đã được xử lý.");
        if (invitation.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            invitation.Status = "expired";
            invitation.RespondedAt = DateTimeOffset.UtcNow;
            await store.SaveAsync(ct);
            throw new ChannelException(410, "INVITATION_EXPIRED", "Lời mời đã hết hạn.");
        }

        var member = await store.FindMemberAsync(invitation.ChannelId, actorUserId, ct);
        if (member == null)
        {
            member = new ChannelMember
            {
                ChannelMemberId = Guid.NewGuid(), ChannelId = invitation.ChannelId, UserId = actorUserId,
                RoleCode = NormalizeRole(invitation.RoleCode), Status = "active",
                JoinedAt = DateTimeOffset.UtcNow, UpdatedAt = DateTimeOffset.UtcNow
            };
            store.AddMember(member);
        }
        else
        {
            member.RoleCode = NormalizeRole(invitation.RoleCode);
            member.Status = "active";
            member.UpdatedAt = DateTimeOffset.UtcNow;
        }

        invitation.Status = "accepted";
        invitation.RespondedAt = DateTimeOffset.UtcNow;
        await store.SaveAsync(ct);
        await WriteAuditAsync(actorUserId, "channel.invitation_accepted", invitation.ChannelId, $"role={member.RoleCode}", ct);
        return ToMemberResponse(member, user.Username, user.Email, user.DisplayName, user.AvatarUrl);
    }

    public async Task DeclineInvitationAsync(Guid invitationId, Guid actorUserId, CancellationToken ct = default)
    {
        var invitation = await RequireInvitationAsync(invitationId, ct);
        var user = await store.FindUserByIdAsync(actorUserId, ct)
            ?? throw new ChannelException(404, "USER_NOT_FOUND", "Người dùng không tồn tại.");
        RequireInvitationTarget(invitation, user.UserId, user.Email);
        var now = DateTimeOffset.UtcNow;
        if (invitation.Status == "expired" || ExpireIfNeeded(invitation, now))
        {
            if (invitation.Status == "expired") await store.SaveAsync(ct);
            throw new ChannelException(410, "INVITATION_EXPIRED", "Lời mời đã hết hạn.");
        }
        if (invitation.Status != "pending")
            throw new ChannelException(409, "INVITATION_ALREADY_PROCESSED", "Lời mời không ở trạng thái chờ phản hồi.");

        invitation.Status = "declined";
        invitation.RespondedAt = now;
        await store.SaveAsync(ct);
        await WriteAuditAsync(actorUserId, "channel.invitation_declined", invitation.ChannelId, null, ct);
    }

    public async Task RevokeInvitationAsync(Guid channelId, Guid invitationId, Guid actorUserId, CancellationToken ct = default)
    {
        var channel = await RequireActiveChannelAsync(channelId, ct);
        var actorRole = await RequireRoleAsync(channel, actorUserId, ct);
        RequirePermission(actorRole, ChannelPermissions.MemberInvite, "Bạn không có quyền thu hồi lời mời.");
        var invitation = await RequireInvitationAsync(invitationId, ct);
        if (invitation.ChannelId != channelId)
            throw new ChannelException(400, "INVALID_INVITATION", "Lời mời không thuộc kênh này.");
        if (invitation.Status == "expired" || ExpireIfNeeded(invitation, DateTimeOffset.UtcNow))
        {
            if (invitation.Status == "expired") await store.SaveAsync(ct);
            throw new ChannelException(410, "INVITATION_EXPIRED", "Lời mời đã hết hạn.");
        }
        if (invitation.Status != "pending")
            throw new ChannelException(409, "INVITATION_ALREADY_PROCESSED", "Chỉ có thể thu hồi lời mời đang chờ.");

        invitation.Status = "revoked";
        invitation.RespondedAt = DateTimeOffset.UtcNow;
        await store.SaveAsync(ct);
        await WriteAuditAsync(actorUserId, "channel.invitation_revoked", channelId, null, ct);
    }

    public async Task<List<ChannelMemberResponse>> GetMembersAsync(Guid channelId, Guid actorUserId, CancellationToken ct = default)
    {
        var channel = await RequireChannelAsync(channelId, ct);
        var actorRole = await RequireRoleAsync(channel, actorUserId, ct);
        RequirePermission(actorRole, ChannelPermissions.MemberView, "Bạn không có quyền xem thành viên kênh.");
        var members = await store.GetMembersWithUserInfoAsync(channelId, ct);
        return members.Select(m => ToMemberResponse(m.Member, m.Username, m.Email, m.DisplayName, m.AvatarUrl)).ToList();
    }

    public async Task<List<ChannelInvitationResponse>> GetPendingInvitationsAsync(Guid channelId, Guid actorUserId, CancellationToken ct = default)
    {
        var channel = await RequireActiveChannelAsync(channelId, ct);
        var actorRole = await RequireRoleAsync(channel, actorUserId, ct);
        RequirePermission(actorRole, ChannelPermissions.MemberInvite, "Bạn không có quyền xem danh sách lời mời.");
        var invitations = await store.GetPendingInvitationsAsync(channelId, ct);
        var now = DateTimeOffset.UtcNow;
        var changed = false;
        foreach (var invitation in invitations) changed |= ExpireIfNeeded(invitation, now);
        if (changed) await store.SaveAsync(ct);
        return invitations.Where(invitation => invitation.IsPending(now)).Select(i => ToInvitationResponse(i, channel)).ToList();
    }

    public async Task<List<ChannelInvitationResponse>> GetMyInvitationsAsync(Guid actorUserId, CancellationToken ct = default)
    {
        var user = await store.FindUserByIdAsync(actorUserId, ct)
            ?? throw new ChannelException(404, "USER_NOT_FOUND", "Người dùng không tồn tại.");
        var invitations = await store.GetUserInvitationsWithChannelAsync(user.Email, actorUserId, ct);
        var now = DateTimeOffset.UtcNow;
        var changed = false;
        foreach (var item in invitations) changed |= ExpireIfNeeded(item.Invitation, now);
        if (changed) await store.SaveAsync(ct);
        return invitations.Where(item => item.Invitation.IsPending(now))
            .Select(i => ToInvitationResponse(i.Invitation, i.ChannelName, i.ChannelHandle)).ToList();
    }

    public async Task<ChannelMemberResponse> ChangeMemberRoleAsync(Guid channelId, Guid targetUserId, Guid actorUserId, ChangeMemberRoleRequest request, CancellationToken ct = default)
    {
        var channel = await RequireChannelAsync(channelId, ct);
        var actorRole = await RequireRoleAsync(channel, actorUserId, ct);
        RequirePermission(actorRole, ChannelPermissions.MemberChangeRole, "Bạn không có quyền thay đổi vai trò thành viên.");
        if (targetUserId == channel.OwnerUserId)
            throw new ChannelException(400, "CANNOT_CHANGE_OWNER_ROLE", "Không thể thay đổi vai trò của chủ sở hữu.");

        var targetMember = await store.FindMemberAsync(channelId, targetUserId, ct)
            ?? throw new ChannelException(404, "MEMBER_NOT_FOUND", "Không tìm thấy thành viên trong kênh.");
        var newRole = NormalizeRole(request.RoleCode);
        if (!ChannelRoles.AssignableMemberRoles.Contains(newRole, StringComparer.OrdinalIgnoreCase))
            throw new ChannelException(400, "INVALID_ROLE", "Vai trò mới không hợp lệ.");
        if (actorRole == ChannelRoles.Manager && (targetMember.RoleCode == ChannelRoles.Manager || newRole == ChannelRoles.Manager))
            throw new ChannelException(403, "ROLE_ESCALATION_DENIED", "Quản lý không thể thay đổi hoặc cấp vai trò quản lý.");

        targetMember.RoleCode = newRole;
        targetMember.UpdatedAt = DateTimeOffset.UtcNow;
        await store.SaveAsync(ct);
        await WriteAuditAsync(actorUserId, "channel.member_role_changed", channelId, $"target={targetUserId};role={newRole}", ct);
        var user = await store.FindUserByIdAsync(targetUserId, ct);
        return ToMemberResponse(targetMember, user?.Username ?? "", user?.Email ?? "", user?.DisplayName ?? "", user?.AvatarUrl);
    }

    public async Task RemoveMemberAsync(Guid channelId, Guid targetUserId, Guid actorUserId, CancellationToken ct = default)
    {
        var channel = await RequireChannelAsync(channelId, ct);
        if (targetUserId == channel.OwnerUserId)
            throw new ChannelException(400, "CANNOT_REMOVE_OWNER", "Không thể xóa chủ sở hữu khỏi kênh.");
        var target = await store.FindMemberAsync(channelId, targetUserId, ct)
            ?? throw new ChannelException(404, "MEMBER_NOT_FOUND", "Không tìm thấy thành viên trong kênh.");

        if (targetUserId != actorUserId)
        {
            var actorRole = await RequireRoleAsync(channel, actorUserId, ct);
            RequirePermission(actorRole, ChannelPermissions.MemberRemove, "Bạn không có quyền xóa thành viên.");
            if (actorRole == ChannelRoles.Manager && target.RoleCode == ChannelRoles.Manager)
                throw new ChannelException(403, "ROLE_ESCALATION_DENIED", "Quản lý không thể xóa quản lý khác.");
        }

        store.RemoveMember(target);
        await store.SaveAsync(ct);
        await WriteAuditAsync(actorUserId, "channel.member_removed", channelId, $"target={targetUserId}", ct);
    }

    private async Task<Channel> RequireChannelAsync(Guid channelId, CancellationToken ct) =>
        await store.FindChannelAsync(channelId, ct) ?? throw new ChannelException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");

    private async Task<Channel> RequireActiveChannelAsync(Guid channelId, CancellationToken ct)
    {
        var channel = await RequireChannelAsync(channelId, ct);
        if (channel.Status != "active")
            throw new ChannelException(409, "CHANNEL_NOT_ACTIVE", "Kênh không còn hoạt động.");
        return channel;
    }

    private async Task<ChannelInvitation> RequireInvitationAsync(Guid invitationId, CancellationToken ct) =>
        await store.FindInvitationAsync(invitationId, ct) ?? throw new ChannelException(404, "INVITATION_NOT_FOUND", "Không tìm thấy lời mời.");

    private async Task<string?> ResolveRoleAsync(Channel channel, Guid? actorUserId, CancellationToken ct)
    {
        if (!actorUserId.HasValue) return null;
        if (channel.OwnerUserId == actorUserId.Value) return ChannelRoles.Owner;
        var member = await store.FindMemberAsync(channel.ChannelId, actorUserId.Value, ct);
        return member == null ? null : NormalizeRole(member.RoleCode);
    }

    private async Task<string> RequireRoleAsync(Channel channel, Guid actorUserId, CancellationToken ct) =>
        await ResolveRoleAsync(channel, actorUserId, ct)
        ?? throw new ChannelException(403, "CHANNEL_ACCESS_DENIED", "Bạn không phải thành viên của kênh này.");

    private static void RequirePermission(string roleCode, string permission, string message)
    {
        if (!ChannelPermissions.RoleHas(roleCode, permission))
            throw new ChannelException(403, "CHANNEL_PERMISSION_DENIED", message);
    }

    private static void RequireInvitationTarget(ChannelInvitation invitation, Guid userId, string email)
    {
        if (invitation.InvitedUserId != userId && !string.Equals(invitation.InvitedEmail, email, StringComparison.OrdinalIgnoreCase))
            throw new ChannelException(403, "INVITATION_ACCESS_DENIED", "Lời mời này không dành cho bạn.");
    }

    private static bool ExpireIfNeeded(ChannelInvitation invitation, DateTimeOffset now)
    {
        if (invitation.Status != "pending" || invitation.ExpiresAt > now) return false;
        invitation.Status = "expired";
        invitation.RespondedAt = now;
        return true;
    }

    private static string NormalizeRole(string roleCode) => roleCode.Trim().ToLowerInvariant() switch
    {
        "comment_moderator" => ChannelRoles.Moderator,
        var value => value
    };

    private static string RoleName(string roleCode) =>
        Roles.FirstOrDefault(role => string.Equals(role.Code, roleCode, StringComparison.OrdinalIgnoreCase))?.Name ?? roleCode;

    private static string? NormalizeOptional(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static string ValidateSettings(string value)
    {
        try
        {
            using var document = JsonDocument.Parse(value);
            if (document.RootElement.ValueKind != JsonValueKind.Object) throw new JsonException();
            return document.RootElement.GetRawText();
        }
        catch (JsonException)
        {
            throw new ChannelException(400, "INVALID_CHANNEL_SETTINGS", "Cài đặt kênh phải là một JSON object hợp lệ.");
        }
    }

    private async Task WriteAuditAsync(Guid actorUserId, string action, Guid channelId, string? reason, CancellationToken ct)
    {
        if (audit == null) return;
        await audit.LogAuditAsync(new AuditLogEntry(actorUserId, action, "channel", channelId, reason), ct);
    }

    private static ChannelResponse ToResponse(Channel channel, string? roleCode) =>
        new(channel.ChannelId, channel.OwnerUserId, channel.Name, channel.Handle, channel.Description,
            channel.AvatarUrl, channel.BannerUrl, channel.ContactEmail, channel.WatermarkUrl, channel.Settings,
            channel.Status, 0, 0, roleCode == ChannelRoles.Owner, roleCode,
            ChannelPermissions.ForRole(roleCode), channel.CreatedAt);

    private static ChannelMemberResponse ToMemberResponse(ChannelMember member, string username, string email, string displayName, string? avatarUrl) =>
        new(member.ChannelMemberId, member.ChannelId, member.UserId, username, email, displayName, avatarUrl,
            NormalizeRole(member.RoleCode), ChannelPermissions.ForRole(NormalizeRole(member.RoleCode)), member.Status, member.JoinedAt);

    private static ChannelInvitationResponse ToInvitationResponse(ChannelInvitation invitation, Channel channel) =>
        ToInvitationResponse(invitation, channel.Name, channel.Handle);

    private static ChannelInvitationResponse ToInvitationResponse(ChannelInvitation invitation, string channelName, string channelHandle)
    {
        var role = NormalizeRole(invitation.RoleCode);
        return new(invitation.ChannelInvitationId, invitation.ChannelId, channelName, channelHandle,
            invitation.InvitedUserId, invitation.InvitedEmail, invitation.InvitedByUserId, role,
            ChannelPermissions.ForRole(role), invitation.Status, invitation.ExpiresAt, invitation.CreatedAt);
    }
}
