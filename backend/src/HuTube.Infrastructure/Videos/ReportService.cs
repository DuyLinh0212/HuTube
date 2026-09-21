using HuTube.Application.Auth;
using HuTube.Application.Notifications;
using HuTube.Application.Rbac;
using HuTube.Application.Videos;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Videos;

public sealed class ReportService(
    HuTubeDbContext db,
    RbacService rbac,
    INotificationService notifications,
    StrikeService strikeService)
{
    public async Task<ReportDto> CreateReportAsync(Guid userId, CreateContentReportRequest request, CancellationToken ct = default)
    {
        var targetType = request.TargetType?.Trim().ToLowerInvariant();
        if (targetType is not ("video" or "comment" or "channel"))
            throw new AuthException(400, "INVALID_TARGET_TYPE", "Đối tượng báo cáo chỉ chấp nhận video, comment, hoặc channel.");

        if (string.IsNullOrWhiteSpace(request.Description))
            throw new AuthException(400, "DESCRIPTION_REQUIRED", "Vui lòng nhập mô tả chi tiết lý do báo cáo.");

        var violationType = await db.ViolationTypes.AsNoTracking()
            .FirstOrDefaultAsync(v => v.ViolationTypeId == request.ViolationTypeId && v.Status == "active", ct);
        if (violationType is null)
        {
            violationType = await db.ViolationTypes.AsNoTracking()
                .FirstOrDefaultAsync(v => v.Status == "active", ct);
            if (violationType is null)
            {
                var fallbackVt = new ViolationType
                {
                    ViolationTypeId = request.ViolationTypeId != Guid.Empty ? request.ViolationTypeId : Guid.Parse("00000000-0000-0002-0000-000000000008"),
                    Code = "other",
                    Name = "Vi phạm khác",
                    Description = "Các hành vi vi phạm điều khoản dịch vụ hoặc tiêu chuẩn cộng đồng khác.",
                    Status = "active",
                    CreatedAt = DateTimeOffset.UtcNow,
                    UpdatedAt = DateTimeOffset.UtcNow
                };
                try
                {
                    db.ViolationTypes.Add(fallbackVt);
                    await db.SaveChangesAsync(ct);
                    violationType = fallbackVt;
                }
                catch
                {
                    violationType = await db.ViolationTypes.AsNoTracking().FirstOrDefaultAsync(ct) ?? fallbackVt;
                }
            }
        }

        Guid? videoId = null;
        Guid? commentId = null;
        Guid? channelId = null;
        string? targetTitle = null;

        switch (targetType)
        {
            case "video":
                var video = await db.Videos.AsNoTracking().FirstOrDefaultAsync(v => v.VideoId == request.TargetId, ct)
                    ?? throw new AuthException(404, "VIDEO_NOT_FOUND", "Không tìm thấy video cần báo cáo.");
                videoId = video.VideoId;
                targetTitle = video.Title;
                break;

            case "comment":
                var comment = await db.Comments.AsNoTracking().FirstOrDefaultAsync(c => c.CommentId == request.TargetId, ct)
                    ?? throw new AuthException(404, "COMMENT_NOT_FOUND", "Không tìm thấy bình luận cần báo cáo.");
                commentId = comment.CommentId;
                targetTitle = comment.Content.Length > 50 ? comment.Content[..50] + "..." : comment.Content;
                break;

            case "channel":
                var channel = await db.Channels.AsNoTracking().FirstOrDefaultAsync(c => c.ChannelId == request.TargetId, ct)
                    ?? throw new AuthException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh cần báo cáo.");
                channelId = channel.ChannelId;
                targetTitle = channel.Name;
                break;
        }

        // Idempotency: Prevent duplicate pending reports from the same user for the same target
        var existingPending = await db.Reports.AsNoTracking().FirstOrDefaultAsync(r =>
            r.UserId == userId &&
            r.Status == "pending" &&
            ((videoId != null && r.VideoId == videoId) ||
             (commentId != null && r.CommentId == commentId) ||
             (channelId != null && r.ChannelId == channelId)), ct);

        if (existingPending != null)
        {
            return new ReportDto(
                existingPending.ReportId,
                existingPending.UserId,
                null,
                targetType,
                request.TargetId,
                targetTitle,
                existingPending.ViolationTypeId,
                violationType.Code,
                violationType.Name,
                existingPending.Description,
                existingPending.Status,
                null,
                null,
                existingPending.CreatedAt,
                existingPending.UpdatedAt
            );
        }

        var now = DateTimeOffset.UtcNow;
        var report = new Report
        {
            UserId = userId,
            ViolationTypeId = request.ViolationTypeId,
            VideoId = videoId,
            CommentId = commentId,
            ChannelId = channelId,
            Description = request.Description.Trim(),
            Status = "pending",
            CreatedAt = now,
            UpdatedAt = now
        };

        db.Reports.Add(report);
        await db.SaveChangesAsync(ct);

        var moderationCase = new ModerationCase
        {
            ReportId = report.ReportId,
            CaseType = "report_review",
            Status = "pending",
            SubmittedAt = now,
            UpdatedAt = now
        };
        db.ModerationCases.Add(moderationCase);
        await db.SaveChangesAsync(ct);

        var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.UserId == userId, ct);

        return new ReportDto(
            report.ReportId,
            report.UserId,
            user?.DisplayName ?? user?.Username,
            targetType,
            request.TargetId,
            targetTitle,
            report.ViolationTypeId,
            violationType.Code,
            violationType.Name,
            report.Description,
            report.Status,
            null,
            null,
            report.CreatedAt,
            report.UpdatedAt
        );
    }

    public async Task<List<ReportDto>> GetReportsQueueAsync(
        string? targetType = null,
        string? status = null,
        int page = 1,
        int pageSize = 50,
        CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);

        var query = db.Reports.AsNoTracking();

        if (!string.IsNullOrWhiteSpace(targetType))
        {
            var t = targetType.Trim().ToLowerInvariant();
            query = t switch
            {
                "video" => query.Where(r => r.VideoId != null),
                "comment" => query.Where(r => r.CommentId != null),
                "channel" => query.Where(r => r.ChannelId != null),
                _ => query
            };
        }

        if (!string.IsNullOrWhiteSpace(status))
        {
            var s = status.Trim().ToLowerInvariant();
            query = query.Where(r => r.Status == s);
        }

        var reports = await query
            .OrderBy(r => r.Status == "pending" ? 0 : 1)
            .ThenByDescending(r => r.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(ct);

        if (reports.Count == 0) return [];

        var userIds = reports.Select(r => r.UserId).Distinct().ToList();
        var users = await db.Users.AsNoTracking()
            .Where(u => userIds.Contains(u.UserId))
            .ToDictionaryAsync(u => u.UserId, u => u.DisplayName ?? u.Username, ct);

        var violationTypeIds = reports.Select(r => r.ViolationTypeId).Distinct().ToList();
        var violationTypes = await db.ViolationTypes.AsNoTracking()
            .Where(v => violationTypeIds.Contains(v.ViolationTypeId))
            .ToDictionaryAsync(v => v.ViolationTypeId, ct);

        var reportIds = reports.Select(r => r.ReportId).ToList();
        var moderationCases = await db.ModerationCases.AsNoTracking()
            .Where(m => m.ReportId.HasValue && reportIds.Contains(m.ReportId.Value))
            .ToDictionaryAsync(m => m.ReportId!.Value, ct);

        var reviewerIds = moderationCases.Values.Where(m => m.ReviewerId.HasValue).Select(m => m.ReviewerId!.Value).Distinct().ToList();
        var reviewers = await db.Users.AsNoTracking()
            .Where(u => reviewerIds.Contains(u.UserId))
            .ToDictionaryAsync(u => u.UserId, u => u.DisplayName ?? u.Username, ct);

        var videoIds = reports.Where(r => r.VideoId.HasValue).Select(r => r.VideoId!.Value).Distinct().ToList();
        var videos = await db.Videos.AsNoTracking()
            .Where(v => videoIds.Contains(v.VideoId))
            .ToDictionaryAsync(v => v.VideoId, v => v.Title, ct);

        var commentIds = reports.Where(r => r.CommentId.HasValue).Select(r => r.CommentId!.Value).Distinct().ToList();
        var comments = await db.Comments.AsNoTracking()
            .Where(c => commentIds.Contains(c.CommentId))
            .ToDictionaryAsync(c => c.CommentId, c => c.Content.Length > 50 ? c.Content[..50] + "..." : c.Content, ct);

        var channelIds = reports.Where(r => r.ChannelId.HasValue).Select(r => r.ChannelId!.Value).Distinct().ToList();
        var channels = await db.Channels.AsNoTracking()
            .Where(c => channelIds.Contains(c.ChannelId))
            .ToDictionaryAsync(c => c.ChannelId, c => c.Name, ct);

        return reports.Select(r =>
        {
            var tType = r.VideoId != null ? "video" : (r.CommentId != null ? "comment" : "channel");
            var tId = r.VideoId ?? (r.CommentId ?? (r.ChannelId ?? Guid.Empty));
            var tTitle = r.VideoId != null
                ? videos.GetValueOrDefault(r.VideoId.Value, "Video")
                : (r.CommentId != null ? comments.GetValueOrDefault(r.CommentId.Value, "Bình luận") : channels.GetValueOrDefault(r.ChannelId ?? Guid.Empty, "Kênh"));

            violationTypes.TryGetValue(r.ViolationTypeId, out var vt);
            moderationCases.TryGetValue(r.ReportId, out var mc);
            string? reviewerName = null;
            if (mc?.ReviewerId != null) reviewers.TryGetValue(mc.ReviewerId.Value, out reviewerName);

            return new ReportDto(
                r.ReportId,
                r.UserId,
                users.GetValueOrDefault(r.UserId, "Người dùng"),
                tType,
                tId,
                tTitle,
                r.ViolationTypeId,
                vt?.Code,
                vt?.Name,
                r.Description,
                r.Status,
                mc?.ReviewerId,
                reviewerName,
                r.CreatedAt,
                r.UpdatedAt
            );
        }).ToList();
    }

    public async Task<bool> ClaimReportAsync(Guid actorId, Guid reportId, CancellationToken ct = default)
    {
        var report = await db.Reports.FirstOrDefaultAsync(r => r.ReportId == reportId, ct)
            ?? throw new AuthException(404, "REPORT_NOT_FOUND", "Không tìm thấy báo cáo.");

        var moderationCase = await db.ModerationCases.FirstOrDefaultAsync(m => m.ReportId == reportId, ct);
        var now = DateTimeOffset.UtcNow;

        report.Status = "reviewing";
        report.UpdatedAt = now;

        if (moderationCase != null)
        {
            moderationCase.ReviewerId = actorId;
            moderationCase.Status = "reviewing";
            moderationCase.ClaimedAt = now;
            moderationCase.UpdatedAt = now;
        }

        await db.SaveChangesAsync(ct);
        await rbac.LogAuditAsync(new AuditLogEntry(actorId, "report.claim", "report", reportId, "Nhận xử lý báo cáo"), ct);
        return true;
    }

    public async Task<bool> ReleaseReportAsync(Guid actorId, Guid reportId, CancellationToken ct = default)
    {
        var report = await db.Reports.FirstOrDefaultAsync(r => r.ReportId == reportId, ct)
            ?? throw new AuthException(404, "REPORT_NOT_FOUND", "Không tìm thấy báo cáo.");

        var moderationCase = await db.ModerationCases.FirstOrDefaultAsync(m => m.ReportId == reportId, ct);
        var now = DateTimeOffset.UtcNow;

        report.Status = "pending";
        report.UpdatedAt = now;

        if (moderationCase != null)
        {
            moderationCase.ReviewerId = null;
            moderationCase.ClaimedAt = null;
            moderationCase.Status = "pending";
            moderationCase.UpdatedAt = now;
        }

        await db.SaveChangesAsync(ct);
        await rbac.LogAuditAsync(new AuditLogEntry(actorId, "report.release", "report", reportId, "Hủy nhận xử lý báo cáo"), ct);
        return true;
    }

    public async Task<ReportResolutionResponse> ResolveReportAsync(Guid actorId, Guid reportId, ResolveReportRequest request, CancellationToken ct = default)
    {
        var decision = request.Decision?.Trim().ToLowerInvariant();
        if (decision is not ("dismiss" or "warn" or "strike" or "hide" or "remove" or "lock_channel" or "escalate"))
            throw new AuthException(400, "INVALID_DECISION", "Quyết định xử lý chỉ chấp nhận dismiss, warn, strike, hide, remove, lock_channel, escalate.");

        if (string.IsNullOrWhiteSpace(request.Reason))
            throw new AuthException(400, "REASON_REQUIRED", "Bắt buộc nhập lý do giải quyết báo cáo.");

        var report = await db.Reports.FirstOrDefaultAsync(r => r.ReportId == reportId, ct)
            ?? throw new AuthException(404, "REPORT_NOT_FOUND", "Không tìm thấy báo cáo.");

        var moderationCase = await db.ModerationCases.FirstOrDefaultAsync(m => m.ReportId == reportId, ct);
        var now = DateTimeOffset.UtcNow;

        string finalStatus = "resolved";
        string message = "Đã giải quyết báo cáo thành công.";

        Guid? targetOwnerUserId = null;
        Guid? affectedChannelId = null;

        if (report.VideoId.HasValue)
        {
            var video = await db.Videos.FirstOrDefaultAsync(v => v.VideoId == report.VideoId.Value, ct);
            if (video != null)
            {
                var channel = await db.Channels.FirstOrDefaultAsync(c => c.ChannelId == video.ChannelId, ct);
                targetOwnerUserId = channel?.OwnerUserId;
                affectedChannelId = video.ChannelId;

                if (decision is "hide" or "remove")
                {
                    video.Status = "blocked";
                    video.ModerationStatus = "rejected";
                    video.UpdatedAt = now;
                    message = $"Đã gỡ bỏ video '{video.Title}'.";
                }
            }
        }
        else if (report.CommentId.HasValue)
        {
            var comment = await db.Comments.FirstOrDefaultAsync(c => c.CommentId == report.CommentId.Value, ct);
            if (comment != null)
            {
                targetOwnerUserId = comment.UserId;
                if (decision is "hide" or "remove")
                {
                    comment.Status = "hidden";
                    comment.UpdatedAt = now;
                    message = "Đã ẩn bình luận vi phạm.";
                }
            }
        }
        else if (report.ChannelId.HasValue)
        {
            var channel = await db.Channels.FirstOrDefaultAsync(c => c.ChannelId == report.ChannelId.Value, ct);
            if (channel != null)
            {
                targetOwnerUserId = channel.OwnerUserId;
                affectedChannelId = channel.ChannelId;

                if (decision is "hide" or "remove" or "lock_channel")
                {
                    channel.Status = "suspended";
                    channel.UpdatedAt = now;
                    message = $"Đã khóa kênh '{channel.Name}'.";
                }
            }
        }

        if (decision == "strike" && affectedChannelId.HasValue)
        {
            await strikeService.CreateManualStrikeAsync(actorId, new CreateStrikeRequest(
                affectedChannelId.Value,
                request.PolicyCode,
                StrikeSeverities.High,
                request.Reason,
                request.InternalNote
            ), ct);
            message = "Đã áp dụng Gậy phạt cho kênh vi phạm.";
        }
        else if (decision == "lock_channel" && affectedChannelId.HasValue)
        {
            await strikeService.SetChannelLockAsync(actorId, affectedChannelId.Value, true, request.Reason, ct);
            message = "Đã khóa kênh vi phạm.";
        }
        else if (decision == "warn" && targetOwnerUserId.HasValue)
        {
            await notifications.PublishAsync(
                targetOwnerUserId.Value,
                "moderation_warning",
                "Cảnh cáo vi phạm chính sách",
                $"Nội dung của bạn bị báo cáo vi phạm chính sách {request.PolicyCode ?? ""}. Lý do: {request.Reason}. Vui lòng tuân thủ Tiêu chuẩn Cộng đồng.",
                "/studio",
                "report",
                report.ReportId,
                ct
            );
            message = "Đã gửi cảnh cáo đến người dùng.";
        }
        else if (decision == "dismiss")
        {
            finalStatus = "rejected";
            message = "Đã bác bỏ báo cáo (không phát hiện vi phạm).";
        }
        else if (decision == "escalate")
        {
            finalStatus = "escalated";
            message = "Đã chuyển báo cáo lên cấp cao hơn.";
        }

        report.Status = finalStatus;
        report.UpdatedAt = now;

        if (moderationCase != null)
        {
            moderationCase.ReviewerId = actorId;
            moderationCase.Status = finalStatus;
            moderationCase.Decision = decision;
            moderationCase.PolicyCode = request.PolicyCode;
            moderationCase.Note = request.Reason;
            moderationCase.InternalNote = request.InternalNote;
            moderationCase.ResolvedAt = now;
            moderationCase.UpdatedAt = now;
        }

        await db.SaveChangesAsync(ct);

        await rbac.LogAuditAsync(new AuditLogEntry(
            actorId,
            $"report.{decision}",
            "report",
            report.ReportId,
            $"{message} - Lý do: {request.Reason}"
        ), ct);

        // Notify the reporter
        await notifications.PublishAsync(
            report.UserId,
            "report_resolved",
            "Báo cáo của bạn đã được xử lý",
            decision == "dismiss"
                ? "Cảm ơn bạn đã gửi báo cáo. Chúng tôi đã xem xét và xác định nội dung không vi phạm điều khoản."
                : "Cảm ơn bạn đã gửi báo cáo. Chúng tôi đã tiến hành các biện pháp xử lý phù hợp theo Tiêu chuẩn Cộng đồng.",
            "/",
            "report",
            report.ReportId,
            ct
        );

        return new ReportResolutionResponse(report.ReportId, finalStatus, decision, message);
    }
}
