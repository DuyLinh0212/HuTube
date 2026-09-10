using HuTube.Domain.Rbac;
using HuTube.Domain.Users;

namespace HuTube.Application.Rbac;

public interface IRbacStore
{
    Task<List<string>> GetUserPermissionsAsync(Guid userId, CancellationToken ct);
    Task<(string? RoleCode, string? RoleName)> GetUserRoleAsync(Guid userId, CancellationToken ct);
    Task<bool> HasPermissionAsync(Guid userId, string permissionCode, CancellationToken ct);
    Task<List<Permission>> GetAllPermissionsAsync(CancellationToken ct);
    Task<List<RoleWithPermissions>> GetAllRolesWithPermissionsAsync(CancellationToken ct);
    Task<Role?> FindRoleAsync(Guid roleId, CancellationToken ct);
    Task<bool> RoleCodeExistsAsync(string code, CancellationToken ct);
    Task<List<Permission>> GetActivePermissionsByCodesAsync(IReadOnlyCollection<string> codes, CancellationToken ct);
    void AddRole(Role role);
    Task ReplaceRolePermissionsAsync(Guid roleId, IReadOnlyCollection<Guid> permissionIds, CancellationToken ct);
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
