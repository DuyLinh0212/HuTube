using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Application.Notifications;
using HuTube.Application.Serialization;
using HuTube.Application.Users;
using HuTube.Domain.Rbac;
using HuTube.Domain.Users;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Users;

public sealed class AdminUserService(
    HuTubeDbContext db,
    TimeProvider clock,
    INotificationService notifications)
{
    private DateTimeOffset Now => clock.GetUtcNow();

    public async Task<AdminUserListResponse> GetUsersAsync(
        string? search,
        string? role,
        string? status,
        int page = 1,
        int pageSize = 10,
        CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var normalizedSearch = string.IsNullOrWhiteSpace(search) ? null : search.Trim();
        var normalizedRole = NormalizeFilter(role);
        var normalizedStatus = NormalizeFilter(status);

        var query = from user in db.Users.AsNoTracking()
                    join roleRow in db.Roles.AsNoTracking() on user.RoleId equals roleRow.RoleId
                    join planRow in db.Plans.AsNoTracking() on user.PlanId equals planRow.PlanId into planRows
                    from planRow in planRows.DefaultIfEmpty()
                    select new { user, roleRow, planRow };

        if (normalizedSearch != null)
            query = query.Where(row => row.user.DisplayName.Contains(normalizedSearch)
                || row.user.Username.Contains(normalizedSearch)
                || row.user.Email.Contains(normalizedSearch));
        if (normalizedRole != null && normalizedRole != "all")
            query = query.Where(row => row.roleRow.Code == normalizedRole);
        if (normalizedStatus != null && normalizedStatus != "all")
            query = query.Where(row => row.user.Status == normalizedStatus);

        var total = await query.CountAsync(ct);
        var rows = await query
            .OrderByDescending(row => row.user.LastLoginAt ?? row.user.CreatedAt)
            .ThenBy(row => row.user.DisplayName)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(row => new
            {
                row.user.UserId,
                row.user.DisplayName,
                row.user.Username,
                row.user.Email,
                row.user.AvatarUrl,
                RoleCode = row.roleRow.Code,
                RoleName = row.roleRow.Name,
                PlanCode = row.planRow == null ? null : row.planRow.Code,
                PlanName = row.planRow == null ? null : row.planRow.Name,
                row.user.LastLoginAt,
                row.user.CreatedAt,
                row.user.Status,
                EmailVerified = row.user.EmailVerifiedAt != null,
                row.user.LockedUntil
            })
            .ToListAsync(ct);

        var userIds = rows.Select(row => row.UserId).ToArray();
        var channelCounts = await db.Channels.AsNoTracking()
            .Where(channel => userIds.Contains(channel.OwnerUserId))
            .GroupBy(channel => channel.OwnerUserId)
            .Select(group => new { UserId = group.Key, Count = group.Count() })
            .ToDictionaryAsync(item => item.UserId, item => item.Count, ct);
        var nowUtc = DateTimeOffset.UtcNow;
        var strikeCounts = await db.ChannelStrikes.AsNoTracking()
            .Where(s => userIds.Contains(s.UserId) && s.Status == "active" && s.ExpiresAt > nowUtc)
            .GroupBy(s => s.UserId)
            .Select(group => new { UserId = group.Key, Count = group.Count() })
            .ToDictionaryAsync(item => item.UserId, item => item.Count, ct);
        var auditCounts = await GetAuditCountsAsync(userIds, ct);

        var warningCounts = userIds.ToDictionary(
            uid => uid,
            uid => strikeCounts.GetValueOrDefault(uid) + auditCounts.GetValueOrDefault(uid)
        );

        var items = rows.Select(row => new AdminUserListItem(
            row.UserId,
            row.DisplayName,
            row.Username,
            row.Email,
            row.AvatarUrl,
            row.RoleCode,
            row.RoleName,
            row.PlanCode,
            row.PlanName,
            channelCounts.GetValueOrDefault(row.UserId),
            warningCounts.GetValueOrDefault(row.UserId),
            row.LastLoginAt,
            row.CreatedAt,
            row.Status,
            row.EmailVerified,
            row.LockedUntil)).ToList();

        var statsRows = await db.Users.AsNoTracking()
            .Join(db.Plans.AsNoTracking(), user => user.PlanId, plan => plan.PlanId, (user, plan) => new { user.Status, PlanCode = plan.Code })
            .ToListAsync(ct);
        var allUsers = await db.Users.AsNoTracking().Select(user => new { user.Status, user.PlanId }).ToListAsync(ct);
        var proPlanCodes = statsRows.Where(row => row.PlanCode.Contains("pro", StringComparison.OrdinalIgnoreCase))
            .Select(row => row.PlanCode).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var stats = new AdminUserStats(
            allUsers.Count,
            allUsers.Count(row => row.Status == "active"),
            allUsers.Count(row => row.Status is "banned" or "suspended"),
            statsRows.Count(row => proPlanCodes.Contains(row.PlanCode) && row.Status == "active"));

        return new AdminUserListResponse(items, page, pageSize, total, page * pageSize < total, stats);
    }

    public async Task<AdminUserDetailResponse> GetUserAsync(Guid userId, CancellationToken ct = default)
    {
        var row = await (from user in db.Users.AsNoTracking()
                         join role in db.Roles.AsNoTracking() on user.RoleId equals role.RoleId
                         join planRow in db.Plans.AsNoTracking() on user.PlanId equals planRow.PlanId into planRows
                         from planRow in planRows.DefaultIfEmpty()
                         where user.UserId == userId
                         select new { user, role, planRow }).SingleOrDefaultAsync(ct)
            ?? throw new AuthException(404, "USER_NOT_FOUND", "Không tìm thấy tài khoản.");

        var permissions = await db.RolePermissions.AsNoTracking()
            .Where(item => item.RoleId == row.role.RoleId)
            .Join(db.Permissions.AsNoTracking().Where(item => item.Status == "active"), item => item.PermissionId, permission => permission.PermissionId,
                (_, permission) => permission.Code)
            .OrderBy(code => code)
            .ToListAsync(ct);
        var auditLogs = await db.AuditLogs.AsNoTracking()
            .Where(item => item.ResourceType == "user" && item.ResourceId == userId)
            .OrderByDescending(item => item.CreatedAt)
            .Take(10)
            .Select(item => new AdminUserAuditItem(item.Action, item.Reason, item.CreatedAt))
            .ToListAsync(ct);

        var userStrikes = await db.ChannelStrikes.AsNoTracking()
            .Where(s => s.UserId == userId)
            .OrderByDescending(s => s.CreatedAt)
            .Take(10)
            .ToListAsync(ct);

        var strikeAuditItems = userStrikes.Select(s =>
        {
            var policyPart = !string.IsNullOrWhiteSpace(s.PolicyCode) ? $" [{s.PolicyCode}]" : "";
            if (s.Status == "revoked")
            {
                return new AdminUserAuditItem(
                    "strike.revoked",
                    $"Thu hồi Strike #{s.StrikeNumber} ({s.Severity}): {s.RevocationReason ?? "Đã thu hồi"}",
                    s.RevokedAt ?? s.CreatedAt
                );
            }
            return new AdminUserAuditItem(
                s.Severity == "low" ? "moderation.warned" : "strike.issued",
                $"Strike #{s.StrikeNumber} ({s.Severity}){policyPart}: {s.Reason}",
                s.CreatedAt
            );
        });

        var auditHistory = auditLogs.Concat(strikeAuditItems)
            .OrderByDescending(item => item.CreatedAt)
            .Take(15)
            .ToList();
        var channels = await db.Channels.AsNoTracking()
            .Where(channel => channel.OwnerUserId == userId)
            .OrderBy(channel => channel.Name)
            .Select(channel => new AdminUserChannelItem(channel.ChannelId, channel.Name, channel.Handle, channel.Status))
            .ToListAsync(ct);

        return new AdminUserDetailResponse(
            row.user.UserId,
            row.user.DisplayName,
            row.user.Username,
            row.user.Email,
            row.user.AvatarUrl,
            row.role.Code,
            row.role.Name,
            row.planRow?.Code,
            row.planRow?.Name,
            row.user.Status,
            row.user.EmailVerifiedAt != null,
            row.user.LastLoginAt,
            row.user.CreatedAt,
            row.user.LockedUntil,
            permissions,
            auditHistory,
            channels);
    }

    public Task<AdminUserDetailResponse> LockAsync(Guid actorUserId, Guid targetUserId, AdminUserActionRequest request, CancellationToken ct = default) =>
        ChangeStatusAsync(actorUserId, targetUserId, request, "banned", "admin.user_locked", "Tài khoản của bạn đã bị khóa bởi quản trị viên.", ct);

    public Task<AdminUserDetailResponse> UnlockAsync(Guid actorUserId, Guid targetUserId, AdminUserActionRequest request, CancellationToken ct = default) =>
        ChangeStatusAsync(actorUserId, targetUserId, request, "active", "admin.user_unlocked", "Tài khoản của bạn đã được mở khóa.", ct);

    public async Task<AdminUserDetailResponse> UpdateRoleAsync(Guid actorUserId, Guid targetUserId, UpdateAdminUserRoleRequest request, CancellationToken ct = default)
    {
        ValidateReason(request.Reason);
        if (actorUserId == targetUserId)
            throw new AuthException(400, "SELF_ROLE_CHANGE_DENIED", "Không thể tự thay đổi vai trò của chính mình.");

        var actorRole = await GetRoleCodeAsync(actorUserId, ct);
        var target = await db.Users.SingleOrDefaultAsync(user => user.UserId == targetUserId, ct)
            ?? throw new AuthException(404, "USER_NOT_FOUND", "Không tìm thấy tài khoản.");
        var currentRole = await db.Roles.SingleAsync(role => role.RoleId == target.RoleId, ct);
        var newRoleCode = request.RoleCode.Trim().ToLowerInvariant();
        var newRole = await db.Roles.SingleOrDefaultAsync(role => role.Code == newRoleCode && role.Status == "active", ct)
            ?? throw new AuthException(404, "ROLE_NOT_FOUND", "Không tìm thấy vai trò đang hoạt động.");

        EnsureRoleCanBeManaged(actorRole, currentRole.Code);
        EnsureRoleCanBeManaged(actorRole, newRole.Code);
        if (currentRole.RoleId == newRole.RoleId) return await GetUserAsync(targetUserId, ct);

        target.RoleId = newRole.RoleId;
        target.UpdatedAt = Now;
        AddAudit(actorUserId, targetUserId, "admin.user_role_updated", request.Reason.Trim(),
            new { oldRole = currentRole.Code, newRole = newRole.Code });
        await db.SaveChangesAsync(ct);
        return await GetUserAsync(targetUserId, ct);
    }

    private async Task<AdminUserDetailResponse> ChangeStatusAsync(
        Guid actorUserId,
        Guid targetUserId,
        AdminUserActionRequest request,
        string status,
        string auditAction,
        string notificationMessage,
        CancellationToken ct)
    {
        ValidateReason(request.Reason);
        if (actorUserId == targetUserId)
            throw new AuthException(400, "SELF_LOCK_DENIED", "Không thể khóa hoặc mở khóa tài khoản đang đăng nhập.");

        var actorRole = await GetRoleCodeAsync(actorUserId, ct);
        var target = await db.Users.SingleOrDefaultAsync(user => user.UserId == targetUserId, ct)
            ?? throw new AuthException(404, "USER_NOT_FOUND", "Không tìm thấy tài khoản.");
        var targetRole = await db.Roles.SingleAsync(role => role.RoleId == target.RoleId, ct);
        EnsureRoleCanBeManaged(actorRole, targetRole.Code);

        var now = Now;
        var oldStatus = target.Status;
        target.Status = status;
        target.LockedUntil = null;
        target.FailedLoginAttempts = 0;
        target.UpdatedAt = now;
        if (status == "banned")
        {
            var sessions = await db.Sessions.Where(session => session.UserId == targetUserId && session.RevokedAt == null).ToListAsync(ct);
            foreach (var session in sessions) session.Revoke(now, auditAction);
        }

        AddAudit(actorUserId, targetUserId, auditAction, request.Reason.Trim(), new { oldStatus, newStatus = status });
        await db.SaveChangesAsync(ct);
        if (request.Notify)
            await notifications.PublishInAppAsync(targetUserId, "account_status_changed", "Cập nhật tài khoản", notificationMessage, "/account", "user", targetUserId, ct);
        return await GetUserAsync(targetUserId, ct);
    }

    private async Task<Dictionary<Guid, int>> GetAuditCountsAsync(Guid[] userIds, CancellationToken ct)
    {
        if (userIds.Length == 0) return [];
        return await db.AuditLogs.AsNoTracking()
            .Where(item => item.ResourceType == "user" && item.ResourceId.HasValue && userIds.Contains(item.ResourceId.Value))
            .GroupBy(item => item.ResourceId!.Value)
            .Select(group => new { UserId = group.Key, Count = group.Count() })
            .ToDictionaryAsync(item => item.UserId, item => item.Count, ct);
    }

    private async Task<string> GetRoleCodeAsync(Guid userId, CancellationToken ct) =>
        await (from user in db.Users.AsNoTracking()
               join role in db.Roles.AsNoTracking() on user.RoleId equals role.RoleId
               where user.UserId == userId
               select role.Code).SingleOrDefaultAsync(ct)
            ?? throw new AuthException(403, "ADMIN_ACCESS_DENIED", "Không xác định được vai trò quản trị.");

    private void AddAudit(Guid actorUserId, Guid targetUserId, string action, string reason, object? newValues = null)
    {
        db.AuditLogs.Add(new AuditLog
        {
            AuditLogId = Guid.NewGuid(),
            ActorUserId = actorUserId,
            Action = action,
            ResourceType = "user",
            ResourceId = targetUserId,
            Reason = reason,
            NewValues = newValues == null ? null : PersistenceJson.Serialize(newValues),
            CreatedAt = Now
        });
    }

    private static string? NormalizeFilter(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim().ToLowerInvariant();

    private static void ValidateReason(string? reason)
    {
        if (string.IsNullOrWhiteSpace(reason) || reason.Trim().Length is < 3 or > 300)
            throw new AuthException(400, "INVALID_AUDIT_REASON", "Lý do phải có từ 3 đến 300 ký tự.");
    }

    private static void EnsureRoleCanBeManaged(string actorRole, string targetRole)
    {
        if (targetRole == "super_admin" && actorRole != "super_admin")
            throw new AuthException(403, "ROLE_PROTECTED", "Chỉ Super Administrator có thể quản lý tài khoản Super Administrator.");
    }
}
