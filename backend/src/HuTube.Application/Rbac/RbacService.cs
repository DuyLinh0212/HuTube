using HuTube.Application.Auth;
using HuTube.Application.Serialization;
using HuTube.Domain.Rbac;
using HuTube.Domain.Users;

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

    public async Task<RoleResponse> CreateRoleAsync(Guid actorUserId, CreateRoleRequest request, CancellationToken ct = default)
    {
        var code = NormalizeCode(request.Code);
        ValidateRoleDetails(code, request.Name, request.Description, request.Reason, rejectSystemCode: true);

        if (await rbacStore.RoleCodeExistsAsync(code, ct))
            throw new RbacException(409, "ROLE_CODE_EXISTS", "Mã vai trò đã tồn tại.");

        var permissions = await ResolveAssignablePermissionsAsync(actorUserId, request.PermissionCodes, ct);
        var role = new Role
        {
            RoleId = Guid.NewGuid(),
            Code = code,
            Name = request.Name.Trim(),
            Description = NormalizeDescription(request.Description),
            Status = "active"
        };

        rbacStore.AddRole(role);
        // RolePermission only carries RoleId, so persist the principal first.
        // This keeps PostgreSQL from receiving the dependent row before roles.
        await rbacStore.SaveAsync(ct);
        await rbacStore.ReplaceRolePermissionsAsync(role.RoleId, permissions.Select(permission => permission.PermissionId).ToList(), ct);
        await LogAuditAsync(new AuditLogEntry(
            actorUserId,
            "rbac.role_created",
            "role",
            role.RoleId,
            request.Reason.Trim(),
            NewValues: PersistenceJson.Serialize(new { role.Code, role.Name, role.Description, permissions = permissions.Select(p => p.Code) })), ct);
        await rbacStore.SaveAsync(ct);
        return new RoleResponse(role.RoleId, role.Code, role.Name, role.Description, permissions.Select(permission => permission.Code).ToList());
    }

    public async Task<RoleResponse> UpdateRoleAsync(Guid actorUserId, Guid roleId, UpdateRoleRequest request, CancellationToken ct = default)
    {
        var role = await rbacStore.FindRoleAsync(roleId, ct)
            ?? throw new RbacException(404, "ROLE_NOT_FOUND", "Không tìm thấy vai trò.");

        ValidateRoleDetails(role.Code, request.Name, request.Description, request.Reason, rejectSystemCode: false);
        await EnsureRoleCanBeManagedAsync(actorUserId, role.Code, ct);

        var permissions = await ResolveAssignablePermissionsAsync(actorUserId, request.PermissionCodes, ct);
        var previousPermissions = (await rbacStore.GetAllRolesWithPermissionsAsync(ct))
            .SingleOrDefault(item => item.RoleId == roleId)?.Permissions ?? [];

        role.Name = request.Name.Trim();
        role.Description = NormalizeDescription(request.Description);
        await rbacStore.ReplaceRolePermissionsAsync(role.RoleId, permissions.Select(permission => permission.PermissionId).ToList(), ct);
        await LogAuditAsync(new AuditLogEntry(
            actorUserId,
            "rbac.role_updated",
            "role",
            role.RoleId,
            request.Reason.Trim(),
            OldValues: PersistenceJson.Serialize(new { role.Code, previousPermissions }),
            NewValues: PersistenceJson.Serialize(new { role.Code, role.Name, role.Description, permissions = permissions.Select(p => p.Code) })), ct);
        await rbacStore.SaveAsync(ct);
        return new RoleResponse(role.RoleId, role.Code, role.Name, role.Description, permissions.Select(permission => permission.Code).ToList());
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

    private async Task<List<Permission>> ResolveAssignablePermissionsAsync(
        Guid actorUserId,
        IReadOnlyList<string>? requestedCodes,
        CancellationToken ct)
    {
        var codes = (requestedCodes ?? [])
            .Where(code => !string.IsNullOrWhiteSpace(code))
            .Select(code => code.Trim().ToLowerInvariant())
            .Distinct(StringComparer.Ordinal)
            .ToList();
        var permissions = await rbacStore.GetActivePermissionsByCodesAsync(codes, ct);
        if (permissions.Count != codes.Count)
            throw new RbacException(400, "INVALID_PERMISSION", "Có permission không tồn tại hoặc đã bị vô hiệu hóa.");

        var (actorRoleCode, _) = await rbacStore.GetUserRoleAsync(actorUserId, ct);
        if (!string.Equals(actorRoleCode, "super_admin", StringComparison.Ordinal))
        {
            var actorPermissions = await rbacStore.GetUserPermissionsAsync(actorUserId, ct);
            if (codes.Except(actorPermissions, StringComparer.OrdinalIgnoreCase).Any())
                throw new RbacException(403, "PERMISSION_DELEGATION_DENIED", "Bạn chỉ có thể gán permission mà chính bạn đang có.");
        }
        return permissions;
    }

    private async Task EnsureRoleCanBeManagedAsync(Guid actorUserId, string targetRoleCode, CancellationToken ct)
    {
        if (string.Equals(targetRoleCode, "user", StringComparison.Ordinal))
            throw new RbacException(403, "ROLE_PROTECTED", "Không thể chỉnh sửa vai trò người dùng mặc định tại khu vực quản trị.");

        var (actorRoleCode, _) = await rbacStore.GetUserRoleAsync(actorUserId, ct);
        var protectedRole = targetRoleCode is "admin" or "super_admin";
        if (protectedRole && !string.Equals(actorRoleCode, "super_admin", StringComparison.Ordinal))
            throw new RbacException(403, "ROLE_PROTECTED", "Chỉ Super Administrator có thể chỉnh sửa vai trò hệ thống này.");
    }

    private static string NormalizeCode(string? value) => (value ?? "").Trim().ToLowerInvariant();

    private static string? NormalizeDescription(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static void ValidateRoleDetails(string code, string? name, string? description, string? reason, bool rejectSystemCode)
    {
        if (!System.Text.RegularExpressions.Regex.IsMatch(code, "^[a-z][a-z0-9_]{2,47}$"))
            throw new RbacException(400, "INVALID_ROLE_CODE", "Mã vai trò gồm 3–48 ký tự chữ thường, số hoặc dấu gạch dưới.");
        if (string.IsNullOrWhiteSpace(name) || name.Trim().Length is < 2 or > 80)
            throw new RbacException(400, "INVALID_ROLE_NAME", "Tên vai trò phải có từ 2 đến 80 ký tự.");
        if (description?.Trim().Length > 500)
            throw new RbacException(400, "INVALID_ROLE_DESCRIPTION", "Mô tả vai trò tối đa 500 ký tự.");
        if (string.IsNullOrWhiteSpace(reason) || reason.Trim().Length is < 3 or > 300)
            throw new RbacException(400, "INVALID_AUDIT_REASON", "Lý do thay đổi phải có từ 3 đến 300 ký tự.");
        if (rejectSystemCode && (code is "user" or "admin" or "super_admin"))
            throw new RbacException(403, "ROLE_PROTECTED", "Không thể tạo hoặc đổi mã vai trò hệ thống.");
    }
}
