using HuTube.Application.Auth;
using HuTube.Application.Notifications;
using HuTube.Application.Rbac;
using HuTube.Application.Serialization;
using HuTube.Application.Storage;
using HuTube.Application.Videos;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace HuTube.Infrastructure.Videos;

public sealed class AdminContentService(HuTubeDbContext db, RbacService rbac, INotificationService notifications,
    IAuthEmailSender emailSender, IObjectStorage storage, ILogger<AdminContentService> logger)
{
    public async Task<PageResult<AdminChannelListItem>> GetChannelsAsync(string? search, string? status,
        string? sortBy, bool? sortDescending, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(page, 1); pageSize = Math.Clamp(pageSize, 1, 100);
        var query = from channel in db.Channels.IgnoreQueryFilters().AsNoTracking()
                    join owner in db.Users.IgnoreQueryFilters().AsNoTracking() on channel.OwnerUserId equals owner.UserId
                    select new { channel, owner };
        if (!string.IsNullOrWhiteSpace(search))
        {
            var term = search.Trim().ToLowerInvariant();
            query = query.Where(x => x.channel.Name.ToLower().Contains(term) || x.channel.Handle.ToLower().Contains(term)
                || x.owner.Email.ToLower().Contains(term) || x.owner.Username.ToLower().Contains(term));
        }
        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(x => x.channel.Status == status.Trim().ToLowerInvariant());
        var total = await query.CountAsync(ct);

        var isDesc = sortDescending ?? true;
        query = (sortBy?.ToLowerInvariant()) switch
        {
            "name" => isDesc ? query.OrderByDescending(x => x.channel.Name) : query.OrderBy(x => x.channel.Name),
            "owner" => isDesc ? query.OrderByDescending(x => x.owner.DisplayName) : query.OrderBy(x => x.owner.DisplayName),
            "videocount" or "videos" => isDesc ? query.OrderByDescending(x => db.Videos.Count(v => v.ChannelId == x.channel.ChannelId)) : query.OrderBy(x => db.Videos.Count(v => v.ChannelId == x.channel.ChannelId)),
            "subscribercount" or "subscribers" => isDesc ? query.OrderByDescending(x => db.Subscriptions.Count(s => s.ChannelId == x.channel.ChannelId && s.Status == "active")) : query.OrderBy(x => db.Subscriptions.Count(s => s.ChannelId == x.channel.ChannelId && s.Status == "active")),
            "status" => isDesc ? query.OrderByDescending(x => x.channel.Status) : query.OrderBy(x => x.channel.Status),
            "createdat" or "date" => isDesc ? query.OrderByDescending(x => x.channel.CreatedAt) : query.OrderBy(x => x.channel.CreatedAt),
            _ => isDesc ? query.OrderByDescending(x => x.channel.CreatedAt) : query.OrderBy(x => x.channel.CreatedAt)
        };

        var rows = await query.Skip((page - 1) * pageSize).Take(pageSize)
            .Select(x => new
            {
                x.channel.ChannelId, x.channel.Name, x.channel.Handle, x.channel.OwnerUserId,
                OwnerName = x.owner.DisplayName, OwnerEmail = x.owner.Email, x.channel.Status, x.channel.CreatedAt,
                VideoCount = db.Videos.Count(v => v.ChannelId == x.channel.ChannelId),
                SubscriberCount = db.Subscriptions.Count(s => s.ChannelId == x.channel.ChannelId && s.Status == "active"),
                ActiveStrikeCount = db.ChannelStrikes.Count(s => s.ChannelId == x.channel.ChannelId && s.StrikeNumber > 0 && s.Status == "active" && s.ExpiresAt > DateTimeOffset.UtcNow),
                x.channel.StatusReason
            }).ToListAsync(ct);

        var channelIds = rows.Select(x => x.ChannelId).ToList();
        var channelViews = await (from v in db.Videos.AsNoTracking().Where(v => channelIds.Contains(v.ChannelId))
                                  join h in db.ViewingHistories.AsNoTracking() on v.VideoId equals h.VideoId
                                  group h by v.ChannelId into g
                                  select new { ChannelId = g.Key, Views = g.LongCount() })
                                 .ToDictionaryAsync(x => x.ChannelId, x => x.Views, ct);

        return new(rows.Select(x => new AdminChannelListItem(x.ChannelId, x.Name, x.Handle, x.OwnerUserId,
            x.OwnerName, x.OwnerEmail, x.Status, x.CreatedAt, x.VideoCount, x.SubscriberCount, x.ActiveStrikeCount,
            channelViews.GetValueOrDefault(x.ChannelId, 0), x.StatusReason)).ToList(), page, pageSize, total);
    }

    public async Task<AdminChannelDetailResponse> GetChannelAsync(Guid channelId, CancellationToken ct)
    {
        var channel = await db.Channels.IgnoreQueryFilters().AsNoTracking().FirstOrDefaultAsync(c => c.ChannelId == channelId, ct)
            ?? throw new AuthException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");
        var owner = await db.Users.IgnoreQueryFilters().AsNoTracking().FirstOrDefaultAsync(u => u.UserId == channel.OwnerUserId, ct);
        var totalChannelViews = await (from v in db.Videos.AsNoTracking().Where(v => v.ChannelId == channelId)
                                       join h in db.ViewingHistories.AsNoTracking() on v.VideoId equals h.VideoId
                                       select h).LongCountAsync(ct);
        var summary = new AdminChannelListItem(channel.ChannelId, channel.Name, channel.Handle, channel.OwnerUserId,
            owner?.DisplayName ?? owner?.Username ?? "Người dùng đã xóa", owner?.Email ?? "", channel.Status, channel.CreatedAt,
            await db.Videos.CountAsync(v => v.ChannelId == channelId, ct),
            await db.Subscriptions.CountAsync(s => s.ChannelId == channelId && s.Status == "active", ct),
            await db.ChannelStrikes.CountAsync(s => s.ChannelId == channelId && s.StrikeNumber > 0 && s.Status == "active" && s.ExpiresAt > DateTimeOffset.UtcNow, ct),
            totalChannelViews,
            channel.StatusReason);
        var videoRows = await AdminVideoQuery(false).Where(x => x.ChannelId == channelId)
            .OrderByDescending(x => x.CreatedAt).Take(25).ToListAsync(ct);
        var videoIds = videoRows.Select(x => x.VideoId).ToList();
        var videoViews = await db.ViewingHistories.AsNoTracking().Where(h => videoIds.Contains(h.VideoId))
            .GroupBy(h => h.VideoId).Select(g => new { VideoId = g.Key, Count = g.LongCount() }).ToDictionaryAsync(x => x.VideoId, x => x.Count, ct);
        var videoReports = await db.Reports.AsNoTracking().Where(r => r.VideoId.HasValue && videoIds.Contains(r.VideoId.Value))
            .GroupBy(r => r.VideoId!.Value).Select(g => new { VideoId = g.Key, Count = g.Count() }).ToDictionaryAsync(x => x.VideoId, x => x.Count, ct);
        var videos = videoRows.Select(r => new AdminVideoListItem(
            r.VideoId,
            r.ChannelId,
            r.ChannelName,
            r.ChannelHandle,
            r.ChannelAvatarUrl,
            summary.SubscriberCount,
            r.Title,
            r.ThumbnailUrl,
            r.Duration,
            FormatDuration(r.Duration),
            r.CategoryId,
            r.CategoryName,
            r.Visibility,
            r.Status,
            r.ModerationStatus,
            videoReports.GetValueOrDefault(r.VideoId, 0),
            r.AgeRestricted,
            r.CreatedAt,
            r.PublishedAt,
            videoViews.GetValueOrDefault(r.VideoId, 0)
        )).ToList();
        var history = await GetHistoryAsync("channel", channelId, ct);
        return new(summary, channel.Description, channel.ContactEmail, channel.AvatarUrl, channel.BannerUrl, channel.WatermarkUrl, videos, history);
    }

    public async Task<PageResult<AdminVideoListItem>> GetVideosAsync(string? search, string? status, string? visibility,
        Guid? categoryId, string? timeRange, DateTimeOffset? fromDate, DateTimeOffset? toDate,
        string? sortBy, bool? sortDescending,
        Guid? channelId, bool includePrivate, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(page, 1); pageSize = Math.Clamp(pageSize, 1, 100);
        var query = AdminVideoQuery(includePrivate);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var term = search.Trim().ToLowerInvariant();
            query = query.Where(x => x.Title.ToLower().Contains(term) || x.ChannelName.ToLower().Contains(term) || x.ChannelHandle.ToLower().Contains(term));
        }
        if (!string.IsNullOrWhiteSpace(status) && status != "all")
        {
            var normalizedStatus = status.Trim().ToLowerInvariant();
            if (normalizedStatus == "published")
                query = query.Where(x => x.Status == "published" && x.ModerationStatus != "rejected");
            else if (normalizedStatus == "processing")
                query = query.Where(x => x.Status == "processing" || x.ModerationStatus == "pending");
            else if (normalizedStatus == "blocked")
                query = query.Where(x => x.Status == "blocked" || x.ModerationStatus == "rejected");
            else if (normalizedStatus == "rejected")
                query = query.Where(x => x.ModerationStatus == "rejected");
            else if (normalizedStatus == "pending")
                query = query.Where(x => x.ModerationStatus == "pending");
            else if (normalizedStatus == "hidden")
                query = query.Where(x => x.Status == "blocked" && x.ModerationStatus != "rejected");
            else
                query = query.Where(x => x.Status == normalizedStatus);
        }
        if (!string.IsNullOrWhiteSpace(visibility) && visibility != "all")
        {
            query = query.Where(x => x.Visibility == visibility.Trim().ToLowerInvariant());
        }
        if (categoryId.HasValue)
        {
            query = query.Where(x => x.CategoryId == categoryId.Value);
        }
        if (!string.IsNullOrWhiteSpace(timeRange) && timeRange != "all")
        {
            var nowUtc = DateTimeOffset.UtcNow;
            if (timeRange == "today")
            {
                var todayUtc = new DateTimeOffset(nowUtc.Year, nowUtc.Month, nowUtc.Day, 0, 0, 0, TimeSpan.Zero);
                query = query.Where(x => x.CreatedAt >= todayUtc);
            }
            else if (timeRange == "7days")
            {
                var sevenDays = nowUtc.AddDays(-7);
                query = query.Where(x => x.CreatedAt >= sevenDays);
            }
            else if (timeRange == "30days")
            {
                var thirtyDays = nowUtc.AddDays(-30);
                query = query.Where(x => x.CreatedAt >= thirtyDays);
            }
            else if (timeRange == "thisYear")
            {
                var yearStart = new DateTimeOffset(nowUtc.Year, 1, 1, 0, 0, 0, TimeSpan.Zero);
                query = query.Where(x => x.CreatedAt >= yearStart);
            }
        }
        if (fromDate.HasValue)
        {
            query = query.Where(x => x.CreatedAt >= fromDate.Value);
        }
        if (toDate.HasValue)
        {
            query = query.Where(x => x.CreatedAt <= toDate.Value);
        }
        if (channelId.HasValue)
        {
            query = query.Where(x => x.ChannelId == channelId.Value);
        }

        var total = await query.CountAsync(ct);

        var isDesc = sortDescending ?? true;
        query = (sortBy?.ToLowerInvariant()) switch
        {
            "title" or "video" => isDesc ? query.OrderByDescending(x => x.Title) : query.OrderBy(x => x.Title),
            "channel" or "channelname" => isDesc ? query.OrderByDescending(x => x.ChannelName) : query.OrderBy(x => x.ChannelName),
            "category" or "categoryname" => isDesc ? query.OrderByDescending(x => x.CategoryName) : query.OrderBy(x => x.CategoryName),
            "status" => isDesc ? query.OrderByDescending(x => x.Status) : query.OrderBy(x => x.Status),
            "visibility" => isDesc ? query.OrderByDescending(x => x.Visibility) : query.OrderBy(x => x.Visibility),
            "views" => isDesc ? query.OrderByDescending(x => db.ViewingHistories.Count(h => h.VideoId == x.VideoId)) : query.OrderBy(x => db.ViewingHistories.Count(h => h.VideoId == x.VideoId)),
            "reports" or "reportcount" => isDesc ? query.OrderByDescending(x => db.Reports.Count(r => r.VideoId == x.VideoId)) : query.OrderBy(x => db.Reports.Count(r => r.VideoId == x.VideoId)),
            "createdat" or "date" => isDesc ? query.OrderByDescending(x => x.CreatedAt) : query.OrderBy(x => x.CreatedAt),
            _ => isDesc ? query.OrderByDescending(x => x.CreatedAt) : query.OrderBy(x => x.CreatedAt)
        };

        var rows = await query.Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        var videoIds = rows.Select(x => x.VideoId).ToList();
        var channelIds = rows.Select(x => x.ChannelId).Distinct().ToList();

        var views = await db.ViewingHistories.AsNoTracking().Where(h => videoIds.Contains(h.VideoId))
            .GroupBy(h => h.VideoId).Select(g => new { VideoId = g.Key, Count = g.LongCount() }).ToDictionaryAsync(x => x.VideoId, x => x.Count, ct);

        var reportCounts = await db.Reports.AsNoTracking().Where(r => r.VideoId.HasValue && videoIds.Contains(r.VideoId.Value))
            .GroupBy(r => r.VideoId!.Value).Select(g => new { VideoId = g.Key, Count = g.Count() }).ToDictionaryAsync(x => x.VideoId, x => x.Count, ct);

        var subscriberCounts = await db.Subscriptions.AsNoTracking()
            .Where(s => channelIds.Contains(s.ChannelId) && s.Status == "active")
            .GroupBy(s => s.ChannelId).Select(g => new { ChannelId = g.Key, Count = g.Count() }).ToDictionaryAsync(x => x.ChannelId, x => x.Count, ct);

        var items = rows.Select(r => new AdminVideoListItem(
            r.VideoId,
            r.ChannelId,
            r.ChannelName,
            r.ChannelHandle,
            r.ChannelAvatarUrl,
            subscriberCounts.GetValueOrDefault(r.ChannelId, 0),
            r.Title,
            r.ThumbnailUrl,
            r.Duration,
            FormatDuration(r.Duration),
            r.CategoryId,
            r.CategoryName,
            r.Visibility,
            r.Status,
            r.ModerationStatus,
            reportCounts.GetValueOrDefault(r.VideoId, 0),
            r.AgeRestricted,
            r.CreatedAt,
            r.PublishedAt,
            views.GetValueOrDefault(r.VideoId, 0)
        )).ToList();

        return new(items, page, pageSize, total);
    }

    public async Task<AdminVideoDetailResponse> GetVideoAsync(Guid videoId, bool includePrivate, CancellationToken ct)
    {
        var row = await AdminVideoQuery(includePrivate).FirstOrDefaultAsync(x => x.VideoId == videoId, ct)
            ?? throw new AuthException(404, "VIDEO_NOT_FOUND", "Không tìm thấy video hoặc bạn chưa có quyền xem video riêng tư.");

        var history = await GetHistoryAsync("video", videoId, ct);

        // Fetch reports for this video
        var reports = await (from r in db.Reports.AsNoTracking().Where(r => r.VideoId == videoId)
                             join v in db.ViolationTypes.AsNoTracking() on r.ViolationTypeId equals v.ViolationTypeId into vJoin
                             from vt in vJoin.DefaultIfEmpty()
                             join u in db.Users.IgnoreQueryFilters().AsNoTracking() on r.UserId equals u.UserId into uJoin
                             from usr in uJoin.DefaultIfEmpty()
                             orderby r.CreatedAt descending
                             select new AdminVideoReportSummary(
                                 r.ReportId,
                                 usr.DisplayName ?? usr.Username ?? "Người dùng ẩn danh",
                                 usr.Email ?? "",
                                 vt.Code ?? "OTHER",
                                 vt.Name ?? "Vi phạm khác",
                                 r.Description,
                                 r.Status,
                                 r.CreatedAt
                             )).ToListAsync(ct);

        var views = await db.ViewingHistories.AsNoTracking().Where(h => h.VideoId == videoId).LongCountAsync(ct);
        var subCount = await db.Subscriptions.AsNoTracking().CountAsync(s => s.ChannelId == row.ChannelId && s.Status == "active", ct);

        var item = new AdminVideoListItem(
            row.VideoId,
            row.ChannelId,
            row.ChannelName,
            row.ChannelHandle,
            row.ChannelAvatarUrl,
            subCount,
            row.Title,
            row.ThumbnailUrl,
            row.Duration,
            FormatDuration(row.Duration),
            row.CategoryId,
            row.CategoryName,
            row.Visibility,
            row.Status,
            row.ModerationStatus,
            reports.Count,
            row.AgeRestricted,
            row.CreatedAt,
            row.PublishedAt,
            views
        );

        // Resolve playable streaming URL via storage service
        var playableUrl = !string.IsNullOrWhiteSpace(row.VideoUrl)
            ? await storage.GetReadUrlAsync(row.VideoUrl, TimeSpan.FromMinutes(60), ct)
            : "";

        return new(item, row.Description, row.CategoryId, row.CategoryName, playableUrl,
            row.FileSize, row.Duration, history, reports);
    }

    public async Task<AdminVideoStatisticsResponse> GetVideoStatisticsAsync(CancellationToken ct)
    {
        var nowUtc = DateTimeOffset.UtcNow;
        var sevenDaysAgo = new DateTimeOffset(nowUtc.Year, nowUtc.Month, nowUtc.Day, 0, 0, 0, TimeSpan.Zero).AddDays(-6);
        var fourteenDaysAgo = sevenDaysAgo.AddDays(-7);

        var recentVideos = await db.Videos.AsNoTracking()
            .Where(v => v.CreatedAt >= sevenDaysAgo)
            .Select(v => new { v.CreatedAt, v.FileSize })
            .ToListAsync(ct);

        var prevWeekCount = await db.Videos.AsNoTracking()
            .Where(v => v.CreatedAt >= fourteenDaysAgo && v.CreatedAt < sevenDaysAgo)
            .CountAsync(ct);

        var dayCodes = new[] { "T2", "T3", "T4", "T5", "T6", "T7", "CN" };
        var dayLabels = new[] { "Thứ 2", "Thứ 3", "Thứ 4", "Thứ 5", "Thứ 6", "Thứ 7", "Chủ nhật" };
        var dayCounts = new int[7];

        foreach (var v in recentVideos)
        {
            var dayOfWeek = v.CreatedAt.DayOfWeek;
            var index = dayOfWeek == DayOfWeek.Sunday ? 6 : ((int)dayOfWeek - 1);
            dayCounts[index]++;
        }

        var maxCount = dayCounts.Max();
        if (maxCount == 0) maxCount = 1;

        var days = new List<VideoDailyUploadStat>();
        for (int i = 0; i < 7; i++)
        {
            var pct = (int)Math.Round((double)dayCounts[i] / maxCount * 100);
            if (dayCounts[i] > 0 && pct < 15) pct = 15;
            days.Add(new VideoDailyUploadStat(dayCodes[i], dayLabels[i], dayCounts[i], pct));
        }

        var totalWeekly = recentVideos.Count;
        double growthPct = 0;
        if (prevWeekCount > 0)
        {
            growthPct = Math.Round(((double)(totalWeekly - prevWeekCount) / prevWeekCount) * 100, 1);
        }
        else if (totalWeekly > 0)
        {
            growthPct = 100.0;
        }

        var weeklyUploads = new VideoWeeklyUploadsResponse(totalWeekly, growthPct, days);

        var totalVideos = await db.Videos.CountAsync(ct);
        var totalStorageUsed = await db.Videos.SumAsync(v => (long?)v.FileSize, ct) ?? 0;
        var weeklyAddedStorage = recentVideos.Sum(v => v.FileSize);

        long totalCapacity = 5L * 1024 * 1024 * 1024 * 1024; // 5 TB
        var storagePercent = totalCapacity > 0 ? (int)Math.Clamp((totalStorageUsed * 100.0) / totalCapacity, 0, 100) : 0;

        static string FormatBytes(long bytes)
        {
            if (bytes >= 1024L * 1024 * 1024 * 1024)
                return $"{(bytes / (1024.0 * 1024 * 1024 * 1024)):0.#} TB";
            if (bytes >= 1024L * 1024 * 1024)
                return $"{(bytes / (1024.0 * 1024 * 1024)):0.#} GB";
            if (bytes >= 1024L * 1024)
                return $"{(bytes / (1024.0 * 1024)):0.#} MB";
            return $"{bytes} B";
        }

        static string FormatCount(int count)
        {
            if (count >= 1_000_000)
                return $"{(count / 1_000_000.0):0.#}M";
            if (count >= 1_000)
                return $"{(count / 1_000.0):0.#}K";
            return count.ToString();
        }

        var storage = new VideoStorageResponse(
            storagePercent,
            totalStorageUsed,
            totalCapacity,
            FormatBytes(totalStorageUsed),
            "5 TB",
            $"+ {FormatBytes(weeklyAddedStorage)}",
            totalVideos,
            FormatCount(totalVideos)
        );

        return new AdminVideoStatisticsResponse(weeklyUploads, storage);
    }

    public async Task ChangeChannelStatusAsync(Guid actorId, Guid channelId, string status, AdminContentActionRequest request, CancellationToken ct)
    {
        ValidateReason(request.Reason);
        if (status is not ("active" or "suspended" or "banned" or "deleted")) throw new AuthException(400, "INVALID_CHANNEL_STATUS", "Trạng thái kênh không hợp lệ.");
        var channel = await db.Channels.IgnoreQueryFilters().FirstOrDefaultAsync(c => c.ChannelId == channelId, ct)
            ?? throw new AuthException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");
        var oldStatus = channel.Status;
        if (oldStatus == status) return;
        channel.Status = status;
        channel.StatusReason = status is "suspended" or "banned" ? request.Reason.Trim() : null;
        channel.UpdatedAt = DateTimeOffset.UtcNow;
        await rbac.LogAuditAsync(new AuditLogEntry(actorId, $"admin.channel.{status}", "channel", channelId,
            request.Reason.Trim(), OldValues: PersistenceJson.Serialize(new { status = oldStatus }), NewValues: PersistenceJson.Serialize(new { status })), ct);
        if (request.NotifyOwner && (status is "suspended" or "banned"))
            await notifications.PublishAsync(channel.OwnerUserId, "channel_status_changed", "Trạng thái kênh đã thay đổi",
                $"Kênh của bạn đã bị { (status == "banned" ? "cấm" : "tạm ngưng") }. Lý do: {request.Reason.Trim()}", "/studio/channel", "channel", channelId, ct);
    }

    public async Task UpdateVideoAsync(Guid actorId, Guid videoId, UpdateAdminVideoRequest request, CancellationToken ct)
    {
        ValidateReason(request.Reason);
        var video = await db.Videos.FirstOrDefaultAsync(v => v.VideoId == videoId, ct)
            ?? throw new AuthException(404, "VIDEO_NOT_FOUND", "Không tìm thấy video.");
        var oldValues = PersistenceJson.Serialize(new { video.Title, video.Description, video.CategoryId });
        if (request.Title != null)
        {
            var title = request.Title.Trim();
            if (title.Length is < 1 or > 100) throw new AuthException(400, "INVALID_TITLE", "Tiêu đề cần từ 1 đến 100 ký tự.");
            video.Title = title;
        }
        if (request.Description != null) video.Description = string.IsNullOrWhiteSpace(request.Description) ? null : request.Description.Trim();
        if (request.ClearCategory) video.CategoryId = null;
        else if (request.CategoryId.HasValue)
        {
            if (!await db.Categories.AnyAsync(c => c.CategoryId == request.CategoryId && c.Status == "active", ct))
                throw new AuthException(400, "INVALID_CATEGORY", "Danh mục không hợp lệ.");
            video.CategoryId = request.CategoryId;
        }
        video.UpdatedAt = DateTimeOffset.UtcNow;
        await rbac.LogAuditAsync(new AuditLogEntry(actorId, "admin.video.edit_metadata", "video", videoId, request.Reason.Trim(),
            OldValues: oldValues, NewValues: PersistenceJson.Serialize(new { video.Title, video.Description, video.CategoryId })), ct);
    }

    public async Task ChangeVideoStatusAsync(Guid actorId, Guid videoId, string action, AdminContentActionRequest request, CancellationToken ct)
    {
        ValidateReason(request.Reason);
        if (action is not ("hide" or "unhide" or "remove" or "restore")) throw new AuthException(400, "INVALID_VIDEO_ACTION", "Thao tác video không hợp lệ.");
        var video = await db.Videos.FirstOrDefaultAsync(v => v.VideoId == videoId, ct)
            ?? throw new AuthException(404, "VIDEO_NOT_FOUND", "Không tìm thấy video.");
        var oldValues = PersistenceJson.Serialize(new { video.Status, video.Visibility, video.ModerationStatus });
        if (action is "hide" or "remove")
        {
            video.AdminOriginalStatus ??= video.Status;
            video.AdminOriginalVisibility ??= video.Visibility;
            video.AdminOriginalModerationStatus ??= video.ModerationStatus;
            video.Status = "blocked";
            if (action == "remove")
            {
                video.ModerationStatus = "rejected";
                video.ModerationReason = request.Reason.Trim();
                video.MediaRetentionUntil ??= DateTimeOffset.UtcNow.AddDays(30);
            }
        }
        else
        {
            if (video.AdminOriginalStatus == null) throw new AuthException(409, "VIDEO_NOT_ADMIN_BLOCKED", "Video không có trạng thái ẩn hoặc gỡ để khôi phục.");
            if (video.MediaPurgedAt.HasValue) throw new AuthException(409, "VIDEO_MEDIA_PURGED", "Tệp video đã hết thời hạn lưu trữ và không thể khôi phục.");
            video.Status = video.AdminOriginalStatus;
            video.Visibility = video.AdminOriginalVisibility ?? video.Visibility;
            video.ModerationStatus = video.AdminOriginalModerationStatus ?? video.ModerationStatus;
            if (video.ModerationStatus == "approved") { video.ModerationReason = null; video.MediaRetentionUntil = null; }
            video.AdminOriginalStatus = null; video.AdminOriginalVisibility = null; video.AdminOriginalModerationStatus = null;
        }
        video.UpdatedAt = DateTimeOffset.UtcNow;
        await rbac.LogAuditAsync(new AuditLogEntry(actorId, $"admin.video.{action}", "video", videoId, request.Reason.Trim(),
            OldValues: oldValues, NewValues: PersistenceJson.Serialize(new { video.Status, video.Visibility, video.ModerationStatus })), ct);
        if (action == "remove" && request.NotifyOwner)
        {
            var channel = await db.Channels.AsNoTracking().FirstOrDefaultAsync(c => c.ChannelId == video.ChannelId, ct);
            if (channel != null)
            {
                var notice = $"Video “{video.Title}” đã bị gỡ khỏi HuTube. Lý do: {request.Reason.Trim()}. Bạn có thể gửi khiếu nại trong 30 ngày.";
                try { await notifications.PublishAsync(channel.OwnerUserId, "video_removed", "Video đã bị gỡ", notice, "/studio/content", "video", videoId, ct); }
                catch (Exception ex) when (ex is not OperationCanceledException) { logger.LogWarning(ex, "Không gửi được thông báo gỡ video {VideoId}", videoId); }
                var email = await db.Users.IgnoreQueryFilters().AsNoTracking().Where(u => u.UserId == channel.OwnerUserId)
                    .Select(u => u.Email).FirstOrDefaultAsync(ct);
                if (!string.IsNullOrWhiteSpace(email))
                {
                    try { await emailSender.SendAsync(email, "Video đã bị gỡ khỏi HuTube", notice + " Mở Creator Studio để xem quyết định và gửi khiếu nại.", ct); }
                    catch (Exception ex) when (ex is not OperationCanceledException) { logger.LogWarning(ex, "Không gửi được email gỡ video {VideoId}", videoId); }
                }
            }
        }
    }

    private static string FormatDuration(int seconds)
    {
        if (seconds <= 0) return "00:00";
        var ts = TimeSpan.FromSeconds(seconds);
        return ts.Hours > 0
            ? $"{ts.Hours}:{ts.Minutes:D2}:{ts.Seconds:D2}"
            : $"{ts.Minutes:D2}:{ts.Seconds:D2}";
    }

    private IQueryable<AdminVideoProjection> AdminVideoQuery(bool includePrivate) =>
        from video in db.Videos.AsNoTracking()
        join channel in db.Channels.IgnoreQueryFilters().AsNoTracking() on video.ChannelId equals channel.ChannelId
        join cat in db.Categories.AsNoTracking() on video.CategoryId equals cat.CategoryId into catJoin
        from category in catJoin.DefaultIfEmpty()
        where includePrivate || video.Visibility == "public"
        select new AdminVideoProjection
        {
            VideoId = video.VideoId,
            ChannelId = video.ChannelId,
            ChannelName = channel.Name,
            ChannelHandle = channel.Handle,
            ChannelAvatarUrl = channel.AvatarUrl,
            Title = video.Title,
            ThumbnailUrl = video.ThumbnailUrl,
            Visibility = video.Visibility,
            Status = video.Status,
            ModerationStatus = video.ModerationStatus,
            AgeRestricted = video.AgeRestricted,
            CreatedAt = video.CreatedAt,
            PublishedAt = video.PublishedAt,
            Description = video.Description,
            CategoryId = video.CategoryId,
            CategoryName = category != null ? category.Name : null,
            VideoUrl = video.VideoUrl,
            FileSize = video.FileSize,
            Duration = video.Duration
        };

    private async Task<IReadOnlyList<AdminAuditItem>> GetHistoryAsync(string resourceType, Guid resourceId, CancellationToken ct)
    {
        var logs = await db.AuditLogs.AsNoTracking().Where(l => l.ResourceId == resourceId && l.ResourceType == resourceType)
            .OrderByDescending(l => l.CreatedAt).Take(30).ToListAsync(ct);
        var actorIds = logs.Where(l => l.ActorUserId.HasValue).Select(l => l.ActorUserId!.Value).Distinct().ToList();
        var actors = await db.Users.IgnoreQueryFilters().AsNoTracking().Where(u => actorIds.Contains(u.UserId))
            .ToDictionaryAsync(u => u.UserId, u => u.DisplayName ?? u.Username, ct);
        return logs.Select(l => new AdminAuditItem(l.AuditLogId, l.Action, l.Reason,
            l.ActorUserId.HasValue ? actors.GetValueOrDefault(l.ActorUserId.Value) : null, l.CreatedAt)).ToList();
    }

    private static void ValidateReason(string reason)
    {
        if (string.IsNullOrWhiteSpace(reason) || reason.Trim().Length is < 3 or > 300)
            throw new AuthException(400, "INVALID_AUDIT_REASON", "Lý do cần có từ 3 đến 300 ký tự.");
    }

    private sealed class AdminVideoProjection
    {
        public Guid VideoId { get; init; }
        public Guid ChannelId { get; init; }
        public string ChannelName { get; init; } = "";
        public string ChannelHandle { get; init; } = "";
        public string? ChannelAvatarUrl { get; init; }
        public string Title { get; init; } = "";
        public string? ThumbnailUrl { get; init; }
        public string Visibility { get; init; } = "";
        public string Status { get; init; } = "";
        public string ModerationStatus { get; init; } = "";
        public bool AgeRestricted { get; init; }
        public DateTimeOffset CreatedAt { get; init; }
        public DateTimeOffset? PublishedAt { get; init; }
        public string? Description { get; init; }
        public Guid? CategoryId { get; init; }
        public string? CategoryName { get; init; }
        public string VideoUrl { get; init; } = "";
        public long FileSize { get; init; }
        public int Duration { get; init; }
    }
}
