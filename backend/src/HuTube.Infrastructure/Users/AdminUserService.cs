using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Application.Notifications;
using HuTube.Application.Recommendations;
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
    INotificationService notifications,
    IRecommendationClient recommendationClient)
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
            query = query.Where(row => EF.Functions.ILike(row.user.DisplayName, $"%{normalizedSearch}%")
                || EF.Functions.ILike(row.user.Username, $"%{normalizedSearch}%")
                || EF.Functions.ILike(row.user.Email, $"%{normalizedSearch}%"));
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

        var totalUserCount = await db.Users.AsNoTracking().CountAsync(ct);
        var activeUserCount = await db.Users.AsNoTracking().CountAsync(user => user.Status == "active", ct);
        var restrictedUserCount = await db.Users.AsNoTracking().CountAsync(user => user.Status == "banned" || user.Status == "suspended", ct);
        var proUserCount = await (from user in db.Users.AsNoTracking()
                                  join plan in db.Plans.AsNoTracking() on user.PlanId equals plan.PlanId
                                  where user.Status == "active" && EF.Functions.ILike(plan.Code, "%pro%")
                                  select user.UserId).CountAsync(ct);
        var stats = new AdminUserStats(
            totalUserCount,
            activeUserCount,
            restrictedUserCount,
            proUserCount);

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

    public async Task<AdminUserStatisticsResponse> GetStatisticsAsync(
        Guid userId,
        DateTimeOffset? from,
        DateTimeOffset? to,
        CancellationToken ct = default)
    {
        if (!await db.Users.AsNoTracking().AnyAsync(user => user.UserId == userId, ct))
            throw new AuthException(404, "USER_NOT_FOUND", "Không tìm thấy tài khoản.");

        var (fromUtc, toUtc) = NormalizeStatisticsRange(from, to);
        // Reduce each interaction stream in PostgreSQL first. Statistics pages
        // can span months, so returning one row per view/reaction to the app is
        // much more expensive than returning one row per affected video.
        var viewRows = await db.ViewingHistories.AsNoTracking()
            .Where(item => item.UserId == userId && item.ViewedAt >= fromUtc && item.ViewedAt < toUtc)
            .GroupBy(item => item.VideoId)
            .Select(group => new
            {
                VideoId = group.Key,
                WatchSeconds = group.Sum(item => (long)item.WatchDuration),
                ViewCount = group.Count(),
                CompletedCount = group.Count(item => item.Progress >= 95m)
            }).ToListAsync(ct);
        var reactionRows = await db.VideoReactions.AsNoTracking()
            .Where(item => item.UserId == userId && item.UpdatedAt >= fromUtc && item.UpdatedAt < toUtc)
            .GroupBy(item => new { item.VideoId, item.Type })
            .Select(group => new { group.Key.VideoId, group.Key.Type, Count = group.Count() })
            .ToListAsync(ct);
        var commentRows = await db.Comments.AsNoTracking()
            .Where(item => item.UserId == userId && item.CreatedAt >= fromUtc && item.CreatedAt < toUtc)
            .GroupBy(item => item.VideoId)
            .Select(group => new { VideoId = group.Key, Count = group.Count() })
            .ToListAsync(ct);
        var ratingRows = await db.VideoRatings.AsNoTracking()
            .Where(item => item.UserId == userId && item.UpdatedAt >= fromUtc && item.UpdatedAt < toUtc)
            .GroupBy(item => item.VideoId)
            .Select(group => new { VideoId = group.Key, Sum = group.Sum(item => (int)item.Score), Count = group.Count() })
            .ToListAsync(ct);

        var behaviorVideoIds = viewRows.Select(row => row.VideoId)
            .Concat(reactionRows.Select(row => row.VideoId))
            .Concat(ratingRows.Select(row => row.VideoId))
            .Concat(commentRows.Select(row => row.VideoId))
            .Distinct()
            .ToArray();
        var behaviorVideoCategories = await (from video in db.Videos.AsNoTracking()
                                             join categoryRow in db.Categories.AsNoTracking() on video.CategoryId equals categoryRow.CategoryId into categoryRows
                                             from categoryRow in categoryRows.DefaultIfEmpty()
                                             where behaviorVideoIds.Contains(video.VideoId)
                                             select new
                                             {
                                                 video.VideoId,
                                                 CategoryId = video.CategoryId,
                                                 CategoryName = categoryRow == null ? null : categoryRow.Name
                                             }).ToListAsync(ct);
        var categoryByVideo = behaviorVideoCategories.ToDictionary(
            row => row.VideoId,
            row => (row.CategoryId, row.CategoryName));
        var categoryCounts = new Dictionary<(Guid? CategoryId, string? CategoryName), int>();
        void AddCategoryInteraction(Guid videoId, int count = 1)
        {
            if (!categoryByVideo.TryGetValue(videoId, out var category)) return;
            var key = (category.CategoryId, category.CategoryName);
            categoryCounts[key] = categoryCounts.GetValueOrDefault(key) + count;
        }
        foreach (var row in viewRows) AddCategoryInteraction(row.VideoId, row.ViewCount);
        foreach (var row in reactionRows) AddCategoryInteraction(row.VideoId, row.Count);
        foreach (var row in ratingRows) AddCategoryInteraction(row.VideoId, row.Count);
        foreach (var row in commentRows) AddCategoryInteraction(row.VideoId, row.Count);

        var totalInteractions = categoryCounts.Values.Sum();
        var totalViews = viewRows.Sum(row => row.ViewCount);
        var categoryStats = categoryCounts
            .OrderByDescending(item => item.Value)
            .ThenBy(item => item.Key.CategoryName)
            .Select(item => new AdminUserCategoryStatistic(
                item.Key.CategoryId,
                item.Key.CategoryName,
                item.Value,
                totalInteractions == 0 ? 0 : Math.Round(item.Value * 100m / totalInteractions, 1)))
            .ToList();

        var summary = new AdminUserStatisticsSummary(
            TotalWatchSeconds: viewRows.Sum(row => row.WatchSeconds),
            VideosWatched: viewRows.Count,
            CompletionRate: totalViews == 0
                ? 0
                : Math.Round(viewRows.Sum(row => row.CompletedCount) * 100m / totalViews, 1),
            Likes: reactionRows.Where(row => row.Type == "like").Sum(row => row.Count),
            Dislikes: reactionRows.Where(row => row.Type == "dislike").Sum(row => row.Count),
            Comments: commentRows.Sum(row => row.Count),
            AverageRating: ratingRows.Sum(row => row.Count) == 0 ? null
                : Math.Round((decimal)ratingRows.Sum(row => row.Sum) / ratingRows.Sum(row => row.Count), 2),
            Ratings: ratingRows.Sum(row => row.Count));

        var viewedVideoIds = await db.ViewingHistories.AsNoTracking()
            .Where(item => item.UserId == userId)
            .Select(item => item.VideoId)
            .Distinct()
            .Take(5000)
            .ToListAsync(ct);
        IReadOnlyList<RecommendedItem>? modelItems = await recommendationClient.GetRecommendationsAsync(
            userId,
            limit: 10,
            excludeVideoIds: viewedVideoIds,
            ct);
        var recommendationItems = modelItems?.ToList() ?? [];
        var recommendationIds = recommendationItems
            .Select(item => item.VideoId)
            .Distinct()
            .ToArray();

        var recommendationVideos = await (from video in db.Videos.AsNoTracking()
                                           join categoryRow in db.Categories.AsNoTracking() on video.CategoryId equals categoryRow.CategoryId into categoryRows
                                           from categoryRow in categoryRows.DefaultIfEmpty()
                                           where recommendationIds.Contains(video.VideoId)
                                           select new
                                           {
                                               video.VideoId,
                                               video.Title,
                                               video.ThumbnailUrl,
                                               CategoryId = video.CategoryId,
                                               CategoryName = categoryRow == null ? null : categoryRow.Name
                                           }).ToListAsync(ct);
        var recommendationVideoById = recommendationVideos.ToDictionary(video => video.VideoId);

        var latestRecommendationViews = await db.ViewingHistories.AsNoTracking()
            .Where(item => item.UserId == userId && recommendationIds.Contains(item.VideoId))
            .Where(item => !db.ViewingHistories.Any(other => other.UserId == userId && other.VideoId == item.VideoId
                && (other.ViewedAt > item.ViewedAt
                    || (other.ViewedAt == item.ViewedAt && other.ViewingHistoryId > item.ViewingHistoryId))))
            .Select(item => new { item.VideoId, item.Progress, item.ViewedAt })
            .ToListAsync(ct);
        var latestViewByVideo = latestRecommendationViews.ToDictionary(item => item.VideoId);

        var recommendationReactions = await db.VideoReactions.AsNoTracking()
            .Where(item => item.UserId == userId && recommendationIds.Contains(item.VideoId))
            .Select(item => new { item.VideoId, item.Type, item.UpdatedAt })
            .ToListAsync(ct);
        var reactionByVideo = recommendationReactions.ToDictionary(item => item.VideoId, item => item.Type);

        var recommendationRatings = await db.VideoRatings.AsNoTracking()
            .Where(item => item.UserId == userId && recommendationIds.Contains(item.VideoId))
            .Select(item => new { item.VideoId, item.Score, item.UpdatedAt })
            .ToListAsync(ct);
        var ratingByVideo = recommendationRatings.ToDictionary(item => item.VideoId, item => item.Score);

        var comparison = recommendationItems
            .Select((item, index) =>
            {
                if (!recommendationVideoById.TryGetValue(item.VideoId, out var video)) return null;
                var category = categoryStats.FirstOrDefault(stat => stat.CategoryId == video.CategoryId);
                latestViewByVideo.TryGetValue(item.VideoId, out var latestView);
                return new AdminUserRecommendationComparison(
                    item.VideoId,
                    video.Title,
                    video.ThumbnailUrl,
                    video.CategoryName,
                    index + 1,
                    Convert.ToDecimal(item.Score),
                    item.Source,
                    item.ModelVersion,
                    latestView != null,
                    latestView?.Progress,
                    reactionByVideo.GetValueOrDefault(item.VideoId),
                    ratingByVideo.GetValueOrDefault(item.VideoId),
                    category?.InteractionCount ?? 0,
                    category?.Percentage ?? 0);
            })
            .Where(item => item != null)
            .Select(item => item!)
            .ToList();

        var modelVersion = recommendationItems
            .Select(item => item.ModelVersion)
            .FirstOrDefault(version => !string.IsNullOrWhiteSpace(version));

        return new AdminUserStatisticsResponse(
            userId,
            fromUtc,
            toUtc.AddTicks(-1),
            summary,
            categoryStats,
            comparison,
            modelItems is not null,
            modelVersion);
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

    private (DateTimeOffset From, DateTimeOffset To) NormalizeStatisticsRange(DateTimeOffset? from, DateTimeOffset? to)
    {
        var now = Now.ToUniversalTime();
        var fromValue = from?.ToUniversalTime() ?? now.AddDays(-29);
        var toValue = to?.ToUniversalTime() ?? now;
        var fromUtc = new DateTimeOffset(fromValue.UtcDateTime.Date, TimeSpan.Zero);
        var toUtc = new DateTimeOffset(toValue.UtcDateTime.Date.AddDays(1), TimeSpan.Zero);

        if (toUtc <= fromUtc)
            throw new AuthException(400, "INVALID_STATISTICS_RANGE", "Khoảng thời gian thống kê không hợp lệ.");
        if (toUtc - fromUtc > TimeSpan.FromDays(366))
            throw new AuthException(400, "STATISTICS_RANGE_TOO_LARGE", "Khoảng thời gian thống kê tối đa là 366 ngày.");

        return (fromUtc, toUtc);
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
