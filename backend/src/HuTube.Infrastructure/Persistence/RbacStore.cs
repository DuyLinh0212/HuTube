using HuTube.Application.Rbac;
using HuTube.Domain.Rbac;
using HuTube.Domain.Users;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Persistence;

public sealed class RbacStore(HuTubeDbContext db) : IRbacStore
{
    public async Task<List<string>> GetUserPermissionsAsync(Guid userId, CancellationToken ct)
    {
        var roleId = await db.Users
            .Where(u => u.UserId == userId && u.DeletedAt == null)
            .Select(u => (Guid?)u.RoleId)
            .SingleOrDefaultAsync(ct);

        if (roleId == null) return [];

        return await db.RolePermissions
            .Where(rp => rp.RoleId == roleId.Value)
            .Join(db.Permissions.Where(p => p.Status == "active"),
                rp => rp.PermissionId,
                p => p.PermissionId,
                (_, p) => p.Code)
            .Distinct()
            .ToListAsync(ct);
    }

    public async Task<(string? RoleCode, string? RoleName)> GetUserRoleAsync(Guid userId, CancellationToken ct)
    {
        var role = await db.Users
            .Where(u => u.UserId == userId && u.DeletedAt == null)
            .Join(db.Roles, u => u.RoleId, r => r.RoleId, (_, r) => new { r.Code, r.Name })
            .SingleOrDefaultAsync(ct);

        return (role?.Code, role?.Name);
    }

    public async Task<bool> HasPermissionAsync(Guid userId, string permissionCode, CancellationToken ct)
    {
        var permissions = await GetUserPermissionsAsync(userId, ct);
        return permissions.Contains(permissionCode, StringComparer.OrdinalIgnoreCase);
    }

    public Task<List<Permission>> GetAllPermissionsAsync(CancellationToken ct) =>
        db.Permissions.OrderBy(p => p.Code).ToListAsync(ct);

    public async Task<List<RoleWithPermissions>> GetAllRolesWithPermissionsAsync(CancellationToken ct)
    {
        var roles = await db.Roles.ToListAsync(ct);
        var rolePermissions = await db.RolePermissions
            .Join(db.Permissions, rp => rp.PermissionId, p => p.PermissionId, (rp, p) => new { rp.RoleId, p.Code })
            .ToListAsync(ct);

        return roles.Select(r => new RoleWithPermissions(
            r.RoleId,
            r.Code,
            r.Name,
            r.Description,
            rolePermissions.Where(rp => rp.RoleId == r.RoleId).Select(rp => rp.Code).ToList())).ToList();
    }

    public Task<Role?> FindRoleAsync(Guid roleId, CancellationToken ct) =>
        db.Roles.SingleOrDefaultAsync(role => role.RoleId == roleId, ct);

    public Task<bool> RoleCodeExistsAsync(string code, CancellationToken ct) =>
        db.Roles.AnyAsync(role => role.Code == code, ct);

    public Task<List<Permission>> GetActivePermissionsByCodesAsync(IReadOnlyCollection<string> codes, CancellationToken ct) =>
        codes.Count == 0
            ? Task.FromResult(new List<Permission>())
            : db.Permissions.Where(permission => permission.Status == "active" && codes.Contains(permission.Code)).ToListAsync(ct);

    public void AddRole(Role role) => db.Roles.Add(role);

    public async Task ReplaceRolePermissionsAsync(Guid roleId, IReadOnlyCollection<Guid> permissionIds, CancellationToken ct)
    {
        var current = await db.RolePermissions.Where(item => item.RoleId == roleId).ToListAsync(ct);
        db.RolePermissions.RemoveRange(current);
        db.RolePermissions.AddRange(permissionIds.Distinct().Select(permissionId => new RolePermission
        {
            RolePermissionId = Guid.NewGuid(),
            RoleId = roleId,
            PermissionId = permissionId,
            AssignedAt = DateTimeOffset.UtcNow
        }));
    }

    public void AddAuditLog(AuditLog log) => db.AuditLogs.Add(log);

    public Task<List<AuditLog>> GetAuditLogsAsync(int limit, CancellationToken ct) =>
        db.AuditLogs.OrderByDescending(a => a.CreatedAt).Take(limit).ToListAsync(ct);

    public Task SaveAsync(CancellationToken ct) => db.SaveChangesAsync(ct);
}
