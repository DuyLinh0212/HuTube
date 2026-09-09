using HuTube.Domain.Rbac;

namespace HuTube.Application.Rbac;

public interface IRbacStore
{
    Task<List<string>> GetUserPermissionsAsync(Guid userId, CancellationToken ct);
    Task<(string? RoleCode, string? RoleName)> GetUserRoleAsync(Guid userId, CancellationToken ct);
    Task<bool> HasPermissionAsync(Guid userId, string permissionCode, CancellationToken ct);
    Task<List<Permission>> GetAllPermissionsAsync(CancellationToken ct);
    Task<List<RoleWithPermissions>> GetAllRolesWithPermissionsAsync(CancellationToken ct);
    void AddAuditLog(AuditLog log);
    Task<List<AuditLog>> GetAuditLogsAsync(int limit, CancellationToken ct);
    Task SaveAsync(CancellationToken ct);
}

public sealed record RoleWithPermissions(
    Guid RoleId,
    string Code,
    string Name,
    string? Description,
    List<string> Permissions);
