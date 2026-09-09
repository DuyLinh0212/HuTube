using HuTube.Application.Auth;
using HuTube.Domain.Rbac;

namespace HuTube.Application.Rbac;

public sealed class RbacService(IRbacStore rbacStore, IAuthStore authStore)
{
    public Task<List<string>> GetUserPermissionsAsync(Guid userId, CancellationToken ct = default) =>
        rbacStore.GetUserPermissionsAsync(userId, ct);

    public Task<bool> HasPermissionAsync(Guid userId, string permissionCode, CancellationToken ct = default) =>
        rbacStore.HasPermissionAsync(userId, permissionCode, ct);

    public async Task<AdminMeResponse> GetAdminMeAsync(Guid userId, CancellationToken ct = default)
    {
        var user = await authStore.FindUserAsync(userId, ct)
            ?? throw new RbacException(401, "UNAUTHORIZED", "Người dùng không tồn tại.");

        if (user.IsBlocked || user.Status != "active")
            throw new RbacException(403, "ACCOUNT_INACTIVE", "Tài khoản bị khóa hoặc vô hiệu hóa.");

        var isAdmin = await authStore.IsAdminAsync(userId, ct);
        if (!isAdmin)
            throw new RbacException(403, "ADMIN_ACCESS_DENIED", "Bạn không có quyền truy cập quản trị.");

        var (roleCode, _) = await rbacStore.GetUserRoleAsync(userId, ct);
        var permissions = await rbacStore.GetUserPermissionsAsync(userId, ct);

        return new AdminMeResponse(
            user.UserId,
            user.Username,
            user.Email,
            user.DisplayName,
            user.EmailVerifiedAt != null,
            isAdmin,
            roleCode ?? "admin",
            permissions);
    }

    public async Task<List<PermissionResponse>> GetAllPermissionsAsync(CancellationToken ct = default)
    {
        var list = await rbacStore.GetAllPermissionsAsync(ct);
        return list.Select(p => new PermissionResponse(p.PermissionId, p.Code, p.Name, p.Description, p.Status)).ToList();
    }

    public async Task<List<RoleResponse>> GetAllRolesAsync(CancellationToken ct = default)
    {
        var list = await rbacStore.GetAllRolesWithPermissionsAsync(ct);
        return list.Select(r => new RoleResponse(r.RoleId, r.Code, r.Name, r.Description, r.Permissions)).ToList();
    }

    public async Task LogAuditAsync(AuditLogEntry entry, CancellationToken ct = default)
    {
        var log = new AuditLog
        {
            AuditLogId = Guid.NewGuid(),
            ActorUserId = entry.ActorUserId,
            Action = entry.Action,
            ResourceType = entry.ResourceType,
            ResourceId = entry.ResourceId,
            Reason = entry.Reason,
            OldValues = entry.OldValues,
            NewValues = entry.NewValues,
            IpAddress = entry.IpAddress,
            UserAgent = entry.UserAgent,
            CreatedAt = DateTimeOffset.UtcNow
        };
        rbacStore.AddAuditLog(log);
        await rbacStore.SaveAsync(ct);
    }

    public async Task<List<AuditLogResponse>> GetAuditLogsAsync(int limit = 50, CancellationToken ct = default)
    {
        var logs = await rbacStore.GetAuditLogsAsync(limit, ct);
        return logs.Select(l => new AuditLogResponse(
            l.AuditLogId,
            l.ActorUserId,
            l.Action,
            l.ResourceType,
            l.ResourceId,
            l.Reason,
            l.CreatedAt)).ToList();
    }
}
