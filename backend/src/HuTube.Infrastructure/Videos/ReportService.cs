using HuTube.Application.Auth;
using HuTube.Application.Notifications;
using HuTube.Application.Rbac;
using HuTube.Application.Serialization;
using HuTube.Application.Videos;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using System.Text.Json;

namespace HuTube.Infrastructure.Videos;

public sealed class ReportService(
    HuTubeDbContext db,
    RbacService rbac,
    INotificationService notifications,
    StrikeService strikeService,
    IAuthEmailSender emailSender,
    ILogger<ReportService> logger)
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

        var idempotencyKey = string.IsNullOrWhiteSpace(request.IdempotencyKey) ? null : request.IdempotencyKey.Trim();
        if (idempotencyKey != null && idempotencyKey.Length > 128)
            throw new AuthException(400, "INVALID_IDEMPOTENCY_KEY", "Idempotency key tối đa 128 ký tự.");
        var existingSubmission = idempotencyKey == null ? null : await db.Reports.AsNoTracking()
            .FirstOrDefaultAsync(r => r.UserId == userId && r.IdempotencyKey == idempotencyKey, ct);
        if (existingSubmission != null)
        {
            var requestedTargetId = videoId ?? commentId ?? channelId ?? Guid.Empty;
            var existingTargetId = existingSubmission.VideoId ?? existingSubmission.CommentId ?? existingSubmission.ChannelId ?? Guid.Empty;
            if (requestedTargetId != existingTargetId || existingSubmission.ViolationTypeId != violationType.ViolationTypeId
                || !string.Equals(existingSubmission.Description, request.Description.Trim(), StringComparison.Ordinal))
                throw new AuthException(409, "IDEMPOTENCY_KEY_REUSED", "Idempotency key đã được dùng cho một báo cáo khác.");
            return new ReportDto(
                existingSubmission.ReportId,
                existingSubmission.UserId,
                null,
                targetType,
                request.TargetId,
                targetTitle,
                existingSubmission.ViolationTypeId,
                violationType.Code,
                violationType.Name,
                existingSubmission.Description,
                existingSubmission.Status,
                null,
                null,
                existingSubmission.CreatedAt,
                existingSubmission.UpdatedAt,
                Disposition: existingSubmission.Disposition,
                AbuseFlag: existingSubmission.AbuseFlag
            );
        }

        var now = DateTimeOffset.UtcNow;
        var report = new Report
        {
            UserId = userId,
            ViolationTypeId = violationType.ViolationTypeId,
            VideoId = videoId,
            CommentId = commentId,
            ChannelId = channelId,
            IdempotencyKey = idempotencyKey,
            Description = request.Description.Trim(),
            Status = "pending",
            CreatedAt = now,
            UpdatedAt = now
        };

        db.Reports.Add(report);
        await db.SaveChangesAsync(ct);

        var targetId = videoId ?? commentId ?? channelId!.Value;
        await db.Database.ExecuteSqlInterpolatedAsync($"""
            INSERT INTO public.moderation_cases
              (moderation_case_id, case_type, status, submitted_at, updated_at, target_type, target_id)
            VALUES ({Guid.NewGuid()}, 'report_case', 'pending', {now}, {now}, {targetType}, {targetId})
            ON CONFLICT (case_type, target_type, target_id) WHERE case_type = 'report_case'
            DO UPDATE SET
              status = CASE WHEN public.moderation_cases.status IN ('resolved','escalated') THEN 'pending' ELSE public.moderation_cases.status END,
              reviewer_id = CASE WHEN public.moderation_cases.status IN ('resolved','escalated') THEN NULL ELSE public.moderation_cases.reviewer_id END,
              claimed_at = CASE WHEN public.moderation_cases.status IN ('resolved','escalated') THEN NULL ELSE public.moderation_cases.claimed_at END,
              resolved_at = CASE WHEN public.moderation_cases.status IN ('resolved','escalated') THEN NULL ELSE public.moderation_cases.resolved_at END,
              decision = CASE WHEN public.moderation_cases.status IN ('resolved','escalated') THEN NULL ELSE public.moderation_cases.decision END,
              updated_at = EXCLUDED.updated_at
            """, ct);
        var moderationCase = await db.ModerationCases.FirstAsync(m => m.CaseType == "report_case"
            && m.TargetType == targetType && m.TargetId == targetId, ct);
        report.ModerationCaseId = moderationCase.ModerationCaseId;
        moderationCase.UpdatedAt = now;
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
            .ToDictionaryAsync(v => v.VideoId, v => new { v.VideoId, v.Title, v.ThumbnailUrl, v.ChannelId }, ct);

        var commentIds = reports.Where(r => r.CommentId.HasValue).Select(r => r.CommentId!.Value).Distinct().ToList();
        var comments = await db.Comments.AsNoTracking()
            .Where(c => commentIds.Contains(c.CommentId))
            .ToDictionaryAsync(c => c.CommentId, c => new { c.CommentId, c.Content, c.VideoId }, ct);

        var extraVideoIds = comments.Values.Select(c => c.VideoId).Distinct().Except(videoIds).ToList();
        if (extraVideoIds.Count > 0)
        {
            var extraVideos = await db.Videos.AsNoTracking()
                .Where(v => extraVideoIds.Contains(v.VideoId))
                .ToDictionaryAsync(v => v.VideoId, v => new { v.VideoId, v.Title, v.ThumbnailUrl, v.ChannelId }, ct);
            foreach (var kv in extraVideos) videos[kv.Key] = kv.Value;
        }

        var channelIdsFromReports = reports.Where(r => r.ChannelId.HasValue).Select(r => r.ChannelId!.Value);
        var channelIdsFromVideos = videos.Values.Select(v => v.ChannelId);
        var allChannelIds = channelIdsFromReports.Concat(channelIdsFromVideos).Distinct().ToList();

        var channels = await db.Channels.AsNoTracking()
            .Where(c => allChannelIds.Contains(c.ChannelId))
            .ToDictionaryAsync(c => c.ChannelId, c => new { c.ChannelId, c.Name, c.Handle, c.AvatarUrl }, ct);

        return reports.Select(r =>
        {
            var tType = r.VideoId != null ? "video" : (r.CommentId != null ? "comment" : "channel");
            var tId = r.VideoId ?? (r.CommentId ?? (r.ChannelId ?? Guid.Empty));
            string? tTitle = null;
            string? targetUrl = null;
            string? targetThumbnailUrl = null;
            string? targetChannelName = null;
            string? targetChannelHandle = null;
            string? contextText = null;

            if (r.VideoId != null && videos.TryGetValue(r.VideoId.Value, out var vid))
            {
                tTitle = vid.Title;
                targetUrl = $"/watch/{vid.VideoId}";
                targetThumbnailUrl = vid.ThumbnailUrl;
                if (channels.TryGetValue(vid.ChannelId, out var ch))
                {
                    targetChannelName = ch.Name;
                    targetChannelHandle = ch.Handle;
                }
            }
            else if (r.CommentId != null && comments.TryGetValue(r.CommentId.Value, out var cm))
            {
                contextText = cm.Content;
                tTitle = cm.Content.Length > 50 ? cm.Content[..50] + "..." : cm.Content;
                targetUrl = $"/watch/{cm.VideoId}";
                if (videos.TryGetValue(cm.VideoId, out var cv))
                {
                    targetThumbnailUrl = cv.ThumbnailUrl;
                    if (channels.TryGetValue(cv.ChannelId, out var ch))
                    {
                        targetChannelName = ch.Name;
                        targetChannelHandle = ch.Handle;
                    }
                }
            }
            else if (r.ChannelId != null && channels.TryGetValue(r.ChannelId.Value, out var ch))
            {
                tTitle = ch.Name;
                targetUrl = $"/channel/{ch.Handle}";
                targetThumbnailUrl = ch.AvatarUrl;
                targetChannelName = ch.Name;
                targetChannelHandle = ch.Handle;
            }

            tTitle ??= (r.VideoId != null ? "Video" : (r.CommentId != null ? "Bình luận" : "Kênh"));

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
                r.UpdatedAt,
                targetUrl,
                targetThumbnailUrl,
                targetChannelName,
                targetChannelHandle,
                contextText
            );
        }).ToList();
    }

    public async Task<PageResult<ReportCaseSummary>> GetReportCasesAsync(
        string? targetType = null, string? status = null, int page = 1, int pageSize = 50, CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var query = db.ModerationCases.AsNoTracking().Where(c => c.CaseType == "report_case");
        if (!string.IsNullOrWhiteSpace(targetType)) query = query.Where(c => c.TargetType == targetType.Trim().ToLowerInvariant());
        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(c => c.Status == status.Trim().ToLowerInvariant());
        var total = await query.CountAsync(ct);
        var cases = await query.OrderBy(c => c.Status == "pending" ? 0 : c.Status == "reviewing" ? 1 : 2)
            .ThenByDescending(c => c.SubmittedAt).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        var summaries = await BuildReportCaseSummariesAsync(cases, ct);
        return new(summaries, page, pageSize, total);
    }

    public async Task<ReportCaseDetail> GetReportCaseAsync(Guid caseId, CancellationToken ct = default)
    {
        var moderationCase = await db.ModerationCases.AsNoTracking()
            .FirstOrDefaultAsync(c => c.ModerationCaseId == caseId && c.CaseType == "report_case", ct)
            ?? throw new AuthException(404, "REPORT_CASE_NOT_FOUND", "Không tìm thấy hồ sơ báo cáo.");
        var summary = (await BuildReportCaseSummariesAsync([moderationCase], ct)).Single();
        var reports = await db.Reports.AsNoTracking().Where(r => r.ModerationCaseId == caseId)
            .OrderByDescending(r => r.CreatedAt).ToListAsync(ct);
        var reporterIds = reports.Select(r => r.UserId).Distinct().ToList();
        var users = await db.Users.AsNoTracking().Where(u => reporterIds.Contains(u.UserId))
            .ToDictionaryAsync(u => u.UserId, u => u.DisplayName ?? u.Username, ct);
        var violationIds = reports.Select(r => r.ViolationTypeId).Distinct().ToList();
        var violations = await db.ViolationTypes.AsNoTracking().Where(v => violationIds.Contains(v.ViolationTypeId))
            .ToDictionaryAsync(v => v.ViolationTypeId, ct);
        var details = reports.Select(r =>
        {
            violations.TryGetValue(r.ViolationTypeId, out var violation);
            return new ReportCaseReportDetail(r.ReportId, r.UserId, users.GetValueOrDefault(r.UserId), r.ViolationTypeId,
                violation?.Code, violation?.Name, r.Description, r.Status, r.Disposition, r.DispositionReason,
                r.DispositionByUserId, r.DispositionAt, r.AbuseFlag, r.CreatedAt, r.UpdatedAt);
        }).ToList();
        return new(summary, details);
    }

    private async Task<List<ReportCaseSummary>> BuildReportCaseSummariesAsync(IReadOnlyList<ModerationCase> cases, CancellationToken ct)
    {
        if (cases.Count == 0) return [];
        var caseIds = cases.Select(c => c.ModerationCaseId).ToList();
        var reports = await db.Reports.AsNoTracking().Where(r => r.ModerationCaseId.HasValue && caseIds.Contains(r.ModerationCaseId.Value))
            .Join(db.ViolationTypes.AsNoTracking(), r => r.ViolationTypeId, v => v.ViolationTypeId,
                (r, v) => new
                {
                    r.ModerationCaseId,
                    r.ReportId,
                    r.UserId,
                    r.Disposition,
                    r.DispositionByUserId,
                    Code = v.Code,
                    Name = v.Name
                })
            .ToListAsync(ct);

        // The first grouped-report migration kept the old report_review cases. Some
        // closed grouped cases therefore have no reviewer_id even though the legacy
        // case still records who resolved the report. Read that value as a fallback
        // until the backfill migration has been applied (and for databases upgraded
        // from an older schema).
        var reportIds = reports.Select(r => r.ReportId).Distinct().ToList();
        var legacyCases = reportIds.Count == 0
            ? []
            : await db.ModerationCases.AsNoTracking()
                .Where(m => m.ReportId.HasValue && reportIds.Contains(m.ReportId.Value) && m.ReviewerId.HasValue)
                .ToListAsync(ct);
        var legacyReviewerByReport = legacyCases
            .GroupBy(m => m.ReportId!.Value)
            .ToDictionary(
                group => group.Key,
                group => group.OrderByDescending(m => m.ResolvedAt ?? m.UpdatedAt)
                    .ThenByDescending(m => m.ClaimedAt ?? m.SubmittedAt)
                    .Select(m => m.ReviewerId)
                    .FirstOrDefault());
        var fallbackReviewerIds = legacyReviewerByReport.Values
            .Where(id => id.HasValue)
            .Select(id => id!.Value)
            .Concat(reports.Where(r => r.DispositionByUserId.HasValue).Select(r => r.DispositionByUserId!.Value))
            .Distinct();
        var userIds = cases.Where(c => c.ReviewerId.HasValue).Select(c => c.ReviewerId!.Value)
            .Concat(fallbackReviewerIds)
            .Concat(reports.Select(r => r.UserId)).Distinct().ToList();
        var users = await db.Users.AsNoTracking().Where(u => userIds.Contains(u.UserId))
            .ToDictionaryAsync(u => u.UserId, u => u.DisplayName ?? u.Username, ct);

        var videoTargetIds = cases.Where(c => c.TargetType == "video" && c.TargetId.HasValue).Select(c => c.TargetId!.Value).Distinct().ToList();
        var commentTargetIds = cases.Where(c => c.TargetType == "comment" && c.TargetId.HasValue).Select(c => c.TargetId!.Value).Distinct().ToList();
        var channelTargetIds = cases.Where(c => c.TargetType == "channel" && c.TargetId.HasValue).Select(c => c.TargetId!.Value).Distinct().ToList();
        var comments = await db.Comments.AsNoTracking().Where(c => commentTargetIds.Contains(c.CommentId))
            .ToDictionaryAsync(c => c.CommentId, c => new { c.Content, c.VideoId }, ct);
        var allVideoIds = videoTargetIds.Concat(comments.Values.Select(c => c.VideoId)).Distinct().ToList();
        var videos = await db.Videos.AsNoTracking().Where(v => allVideoIds.Contains(v.VideoId))
            .ToDictionaryAsync(v => v.VideoId, v => new { v.Title, v.ThumbnailUrl, v.ChannelId }, ct);
        var channelIds = channelTargetIds.Concat(videos.Values.Select(v => v.ChannelId)).Distinct().ToList();
        var channels = await db.Channels.AsNoTracking().Where(c => channelIds.Contains(c.ChannelId))
            .ToDictionaryAsync(c => c.ChannelId, c => new { c.Name, c.Handle, c.AvatarUrl }, ct);

        var result = new List<ReportCaseSummary>(cases.Count);
        foreach (var c in cases)
        {
            var caseReports = reports.Where(r => r.ModerationCaseId == c.ModerationCaseId).ToList();
            string? title = null;
            string? url = null;
            string? thumbnail = null;
            string? channelName = null;
            string? channelHandle = null;
            var targetId = c.TargetId ?? Guid.Empty;
            if (c.TargetType == "video" && videos.TryGetValue(targetId, out var video))
            {
                title = video.Title; url = $"/watch/{targetId}"; thumbnail = video.ThumbnailUrl;
                if (channels.TryGetValue(video.ChannelId, out var videoChannel)) { channelName = videoChannel.Name; channelHandle = videoChannel.Handle; }
            }
            else if (c.TargetType == "comment" && comments.TryGetValue(targetId, out var comment))
            {
                title = comment.Content.Length > 50 ? comment.Content[..50] + "..." : comment.Content;
                url = $"/watch/{comment.VideoId}";
                if (videos.TryGetValue(comment.VideoId, out var commentVideo))
                {
                    thumbnail = commentVideo.ThumbnailUrl;
                    if (channels.TryGetValue(commentVideo.ChannelId, out var commentChannel)) { channelName = commentChannel.Name; channelHandle = commentChannel.Handle; }
                }
            }
            else if (c.TargetType == "channel" && channels.TryGetValue(targetId, out var channel))
            {
                title = channel.Name; url = $"/channel/{channel.Handle}"; thumbnail = channel.AvatarUrl;
                channelName = channel.Name; channelHandle = channel.Handle;
            }
            var counts = caseReports.GroupBy(r => (r.Code, r.Name))
                .Select(g => new ReportViolationCount(g.Key.Code, g.Key.Name, g.Count()))
                .OrderByDescending(x => x.Count).ToList();
            Guid? reviewerId = c.ReviewerId;
            if (reviewerId is null && (c.Status is "resolved" or "escalated"))
            {
                reviewerId = caseReports
                    .Select(r => legacyReviewerByReport.GetValueOrDefault(r.ReportId) ?? r.DispositionByUserId)
                    .FirstOrDefault(id => id.HasValue);
            }
            users.TryGetValue(reviewerId ?? Guid.Empty, out var reviewerName);
            result.Add(new ReportCaseSummary(c.ModerationCaseId, c.TargetType ?? "unknown", targetId, title, url, thumbnail,
                channelName, channelHandle, c.Status, caseReports.Count, caseReports.Select(r => r.UserId).Distinct().Count(),
                caseReports.Count(r => r.Disposition == null), counts, reviewerId, reviewerName, c.SubmittedAt, c.UpdatedAt));
        }
        return result;
    }

    public async Task<bool> ClaimReportCaseAsync(Guid actorId, Guid caseId, CancellationToken ct = default)
    {
        var reportCase = await RequireReportCaseAsync(caseId, ct);
        if (reportCase.Status == "reviewing" && reportCase.ReviewerId == actorId) return true;
        if (reportCase.Status != "pending") throw new AuthException(409, "REPORT_CASE_ALREADY_CLAIMED", "Hồ sơ không còn ở trạng thái chờ nhận.");
        reportCase.ReviewerId = actorId; reportCase.Status = "reviewing";
        reportCase.ClaimedAt = DateTimeOffset.UtcNow; reportCase.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
        await rbac.LogAuditAsync(new AuditLogEntry(actorId, "report.case.claim", "moderation_case", caseId, "Nhận xử lý hồ sơ báo cáo"), ct);
        return true;
    }

    public async Task<bool> ReleaseReportCaseAsync(Guid actorId, Guid caseId, CancellationToken ct = default)
    {
        var reportCase = await RequireReportCaseAsync(caseId, ct);
        if (reportCase.Status != "reviewing" || reportCase.ReviewerId != actorId)
            throw new AuthException(409, "REPORT_CASE_NOT_OWNED", "Chỉ người đang nhận hồ sơ mới có thể trả lại hồ sơ.");
        reportCase.ReviewerId = null; reportCase.Status = "pending"; reportCase.ClaimedAt = null; reportCase.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
        await rbac.LogAuditAsync(new AuditLogEntry(actorId, "report.case.release", "moderation_case", caseId, "Trả hồ sơ về hàng đợi"), ct);
        return true;
    }

    public async Task UpdateReportDispositionsAsync(Guid actorId, Guid caseId, UpdateReportDispositionsRequest request, CancellationToken ct = default)
    {
        var disposition = request.Disposition?.Trim().ToLowerInvariant();
        var reportIds = request.ReportIds?.Distinct().ToList() ?? [];
        var reason = request.Reason?.Trim();
        if (disposition is not ("accepted" or "rejected")) throw new AuthException(400, "INVALID_DISPOSITION", "Kết quả báo cáo phải là accepted hoặc rejected.");
        if (reportIds.Count == 0) throw new AuthException(400, "REPORTS_REQUIRED", "Chọn ít nhất một báo cáo.");
        if (string.IsNullOrWhiteSpace(reason)) throw new AuthException(400, "REASON_REQUIRED", "Nhập lý do phân loại báo cáo.");
        var reportCase = await RequireReportCaseAsync(caseId, ct);
        EnsureReportCaseReviewer(reportCase, actorId);
        var reports = await db.Reports.Where(r => r.ModerationCaseId == caseId && reportIds.Contains(r.ReportId)).ToListAsync(ct);
        if (reports.Count != reportIds.Count) throw new AuthException(400, "REPORT_NOT_IN_CASE", "Một hoặc nhiều báo cáo không thuộc hồ sơ này.");
        var now = DateTimeOffset.UtcNow;
        foreach (var report in reports)
        {
            report.Disposition = disposition; report.DispositionReason = reason; report.DispositionByUserId = actorId;
            report.DispositionAt = now; report.Status = disposition == "accepted" ? "resolved" : "rejected"; report.UpdatedAt = now;
        }
        reportCase.UpdatedAt = now;
        await db.SaveChangesAsync(ct);
        foreach (var report in reports)
            await rbac.LogAuditAsync(new AuditLogEntry(actorId, $"report.disposition.{disposition}", "report", report.ReportId,
                $"Phân loại báo cáo thuộc hồ sơ {caseId}: {reason}"), ct);
    }

    public async Task<ReportResolutionResponse> ResolveReportCaseAsync(Guid actorId, Guid caseId, ResolveReportCaseRequest request, CancellationToken ct = default)
    {
        var decision = request.Decision?.Trim().ToLowerInvariant();
        if (decision is not ("dismiss" or "warn" or "age_restrict" or "recommendation_restricted" or "hide" or "remove" or "upload_restriction" or "strike" or "lock_channel" or "escalate"))
            throw new AuthException(400, "INVALID_DECISION", "Quyết định không hợp lệ.");
        if (string.IsNullOrWhiteSpace(request.Reason)) throw new AuthException(400, "REASON_REQUIRED", "Bắt buộc nhập lý do giải quyết hồ sơ.");

        await using var transaction = await db.Database.BeginTransactionAsync(System.Data.IsolationLevel.Serializable, ct);
        var reportCase = await RequireReportCaseAsync(caseId, ct);
        EnsureReportCaseReviewer(reportCase, actorId);
        var reports = await db.Reports.Where(r => r.ModerationCaseId == caseId).ToListAsync(ct);
        if (reports.Count == 0) throw new AuthException(409, "EMPTY_REPORT_CASE", "Hồ sơ không có báo cáo để xử lý.");
        if (reports.Any(r => r.Disposition is not ("accepted" or "rejected")))
            throw new AuthException(409, "REPORTS_UNCLASSIFIED", "Hãy phân loại từng báo cáo trước khi đóng hồ sơ.");
        if (reportCase.Status is "resolved" or "escalated") throw new AuthException(409, "REPORT_CASE_CLOSED", "Hồ sơ đã được đóng.");

        var now = DateTimeOffset.UtcNow;
        var targetType = reportCase.TargetType ?? "";
        var targetId = reportCase.TargetId ?? Guid.Empty;
        var targetTitle = "nội dung";
        Guid? ownerId = null;
        Guid? channelId = null;
        if (targetType == "video")
        {
            var video = await db.Videos.FirstOrDefaultAsync(v => v.VideoId == targetId, ct);
            if (video != null)
            {
                targetTitle = video.Title; channelId = video.ChannelId;
                var channel = await db.Channels.FirstOrDefaultAsync(c => c.ChannelId == video.ChannelId, ct);
                ownerId = channel?.OwnerUserId;
                ApplyVideoDecision(video, decision, now, request.Reason.Trim());
            }
        }
        else if (targetType == "comment")
        {
            var comment = await db.Comments.FirstOrDefaultAsync(c => c.CommentId == targetId, ct);
            if (comment != null) { targetTitle = comment.Content; ownerId = comment.UserId; if (decision == "hide" || decision == "remove") comment.Status = "hidden"; comment.UpdatedAt = now; }
        }
        else if (targetType == "channel")
        {
            var channel = await db.Channels.FirstOrDefaultAsync(c => c.ChannelId == targetId, ct);
            if (channel != null)
            {
                targetTitle = channel.Name; ownerId = channel.OwnerUserId; channelId = channel.ChannelId;
                if (decision is "hide" or "remove")
                {
                    channel.Status = decision == "remove" ? "banned" : "suspended";
                    channel.StatusReason = request.Reason.Trim();
                }
                channel.UpdatedAt = now;
            }
        }

        if (!IsDecisionSupportedForTarget(targetType, decision))
            throw new AuthException(400, "INVALID_DECISION_TARGET", "Biện pháp này không áp dụng cho loại đối tượng đã chọn.");
        if ((decision is "upload_restriction" or "strike" or "lock_channel") && !channelId.HasValue)
            throw new AuthException(409, "CHANNEL_REQUIRED", "Không tìm thấy kênh để áp dụng biện pháp này.");

        var reason = request.Reason.Trim();
        var policyText = string.IsNullOrWhiteSpace(request.PolicyCode) ? "Tiêu chuẩn Cộng đồng" : $"quy chuẩn '{request.PolicyCode}'";
        if (decision == "upload_restriction" && channelId.HasValue)
            await strikeService.CreateUploadRestrictionAsync(actorId, channelId.Value, Math.Clamp(request.RestrictionDays ?? 7, 1, 30), reason, ct);
        else if (decision == "strike" && channelId.HasValue)
            await strikeService.CreateManualStrikeAsync(actorId, new CreateStrikeRequest(
                channelId.Value,
                request.PolicyCode,
                StrikeSeverities.High,
                reason,
                request.InternalNote), ct);
        else if (decision == "lock_channel" && channelId.HasValue)
            await strikeService.SetChannelLockAsync(actorId, channelId.Value, true, reason, ct);
        if (decision == "warn" && ownerId.HasValue)
            await notifications.PublishAsync(ownerId.Value, "moderation_warning", "Cảnh cáo vi phạm chính sách",
                $"Nội dung '{targetTitle}' bị xác nhận vi phạm {policyText}. Lý do: {reason}.", "/studio", "moderation_case", caseId, ct);
        if ((decision is "hide" or "remove" or "recommendation_restricted") && ownerId.HasValue)
            await notifications.PublishAsync(ownerId.Value, "moderation_action_taken", "Thông báo xử lý nội dung vi phạm",
                $"Nội dung '{targetTitle}' đã được {decision switch { "remove" => "gỡ bỏ", "hide" => "ẩn", _ => "hạn chế đề xuất" }} do vi phạm {policyText}. Lý do: {reason}. Bạn có thể gửi khiếu nại trong 30 ngày tại Creator Studio.",
                "/studio", "moderation_case", caseId, ct);

        reportCase.Status = decision == "escalate" ? "escalated" : "resolved";
        reportCase.Decision = decision; reportCase.PolicyCode = request.PolicyCode?.Trim(); reportCase.Note = reason;
        reportCase.InternalNote = request.InternalNote?.Trim(); reportCase.ResolvedAt = now; reportCase.UpdatedAt = now;
        await db.SaveChangesAsync(ct);
        await rbac.LogAuditAsync(new AuditLogEntry(actorId, $"report.case.{decision}", "moderation_case", caseId,
            $"Đóng hồ sơ cho đối tượng {targetType}/{targetId}. Lý do: {reason}"), ct);
        await transaction.CommitAsync(ct);

        if (targetType == "video" && decision == "remove" && ownerId.HasValue)
        {
            var email = await db.Users.IgnoreQueryFilters().AsNoTracking().Where(u => u.UserId == ownerId.Value)
                .Select(u => u.Email).FirstOrDefaultAsync(ct);
            if (!string.IsNullOrWhiteSpace(email))
            {
                try { await emailSender.SendAsync(email, "Video đã bị gỡ khỏi HuTube",
                    $"Video “{targetTitle}” đã bị gỡ. Lý do: {reason}. Bạn có thể gửi khiếu nại trong 30 ngày tại Creator Studio.", ct); }
                catch (Exception ex) when (ex is not OperationCanceledException) { logger.LogWarning(ex, "Không gửi được email gỡ video trong hồ sơ {CaseId}", caseId); }
            }
        }

        foreach (var report in reports)
            await notifications.PublishAsync(report.UserId, "report_resolved", "Kết quả xử lý báo cáo vi phạm",
                $"Báo cáo của bạn đối với '{targetTitle}' đã được xem xét. Biện pháp áp dụng: {decision}. Lý do: {reason}.",
                "/", "report", report.ReportId, ct);
        var message = decision switch
        {
            "escalate" => "Đã chuyển hồ sơ lên cấp cao hơn.",
            "strike" => "Đã áp dụng gậy phạt cho kênh vi phạm.",
            "lock_channel" => "Đã khóa kênh vi phạm.",
            "upload_restriction" => "Đã hạn chế quyền tải lên theo thời hạn đã chọn.",
            "recommendation_restricted" => "Đã hạn chế đề xuất video.",
            "age_restrict" => "Đã gắn giới hạn độ tuổi cho video.",
            "hide" => "Đã ẩn đối tượng khỏi bề mặt công khai.",
            "remove" => "Đã gỡ đối tượng khỏi HuTube.",
            "warn" => "Đã gửi cảnh cáo đến chủ sở hữu nội dung.",
            _ => "Đã đóng hồ sơ và xác định không có vi phạm."
        };
        return new(caseId, reportCase.Status, decision, message);
    }

    private async Task<ModerationCase> RequireReportCaseAsync(Guid caseId, CancellationToken ct) =>
        await db.ModerationCases.FirstOrDefaultAsync(c => c.ModerationCaseId == caseId && c.CaseType == "report_case", ct)
        ?? throw new AuthException(404, "REPORT_CASE_NOT_FOUND", "Không tìm thấy hồ sơ báo cáo.");

    private static void EnsureReportCaseReviewer(ModerationCase reportCase, Guid actorId)
    {
        if (reportCase.Status != "reviewing" || reportCase.ReviewerId != actorId)
            throw new AuthException(409, "REPORT_CASE_NOT_CLAIMED", "Hãy nhận hồ sơ trước khi cập nhật kết quả.");
    }

    private static void ApplyVideoDecision(Video video, string decision, DateTimeOffset now, string reason)
    {
        if (decision == "age_restrict") video.AgeRestricted = true;
        else if (decision == "recommendation_restricted")
        {
            try
            {
                var metadata = JsonSerializer.Deserialize<Dictionary<string, object>>(video.Metadata) ?? [];
                metadata["recommendation_restricted"] = true;
                video.Metadata = PersistenceJson.Serialize(metadata);
            }
            catch (JsonException)
            {
                video.Metadata = "{\"recommendation_restricted\":true}";
            }
        }
        else if (decision == "hide") video.Visibility = "private";
        else if (decision == "remove") { video.Status = "blocked"; video.ModerationStatus = "rejected"; video.ModerationReason = reason; video.MediaRetentionUntil ??= now.AddDays(30); }
        video.UpdatedAt = now;
    }

    private static bool IsDecisionSupportedForTarget(string targetType, string decision) => targetType switch
    {
        "video" => decision is "dismiss" or "warn" or "age_restrict" or "recommendation_restricted" or "hide" or "remove" or "upload_restriction" or "strike" or "lock_channel" or "escalate",
        "channel" => decision is "dismiss" or "warn" or "hide" or "remove" or "upload_restriction" or "strike" or "lock_channel" or "escalate",
        "comment" => decision is "dismiss" or "warn" or "hide" or "remove" or "escalate",
        _ => false
    };

    public async Task<bool> ClaimReportAsync(Guid actorId, Guid reportId, CancellationToken ct = default)
    {
        var report = await db.Reports.FirstOrDefaultAsync(r => r.ReportId == reportId, ct)
            ?? throw new AuthException(404, "REPORT_NOT_FOUND", "Không tìm thấy báo cáo.");
        if (report.ModerationCaseId.HasValue) return await ClaimReportCaseAsync(actorId, report.ModerationCaseId.Value, ct);

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
        if (report.ModerationCaseId.HasValue) return await ReleaseReportCaseAsync(actorId, report.ModerationCaseId.Value, ct);

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
        throw new AuthException(409, "REPORT_CASE_WORKFLOW_REQUIRED", "Hãy mở hồ sơ theo đối tượng, phân loại từng báo cáo rồi mới áp dụng quyết định cho đối tượng.");
#pragma warning disable CS0162
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

        string targetTitle = "nội dung";
        string targetTypeStr = "nội dung";

        if (report.VideoId.HasValue)
        {
            var video = await db.Videos.FirstOrDefaultAsync(v => v.VideoId == report.VideoId.Value, ct);
            if (video != null)
            {
                targetTitle = video.Title;
                targetTypeStr = "video";
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
                targetTitle = comment.Content.Length > 40 ? comment.Content[..40] + "..." : comment.Content;
                targetTypeStr = "bình luận";
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
                targetTitle = channel.Name;
                targetTypeStr = "kênh";
                targetOwnerUserId = channel.OwnerUserId;
                affectedChannelId = channel.ChannelId;

                if (decision is "hide" or "remove" or "lock_channel")
                {
                    channel.Status = "suspended";
                    channel.StatusReason = request.Reason.Trim();
                    channel.UpdatedAt = now;
                    message = $"Đã khóa kênh '{channel.Name}'.";
                }
            }
        }

        var policyText = !string.IsNullOrWhiteSpace(request.PolicyCode) ? $"quy chuẩn '{request.PolicyCode}'" : "Tiêu chuẩn Cộng đồng";

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
                $"Nội dung {targetTypeStr} \"{targetTitle}\" của bạn bị báo cáo vi phạm {policyText}. Lý do: {request.Reason}. Vui lòng tuân thủ Tiêu chuẩn Cộng đồng.",
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

        // Notify content owner if removed or hidden
        if (targetOwnerUserId.HasValue && decision is "hide" or "remove" or "lock_channel")
        {
            await notifications.PublishAsync(
                targetOwnerUserId.Value,
                "moderation_action_taken",
                "Thông báo xử lý nội dung vi phạm",
                $"Nội dung {targetTypeStr} \"{targetTitle}\" của bạn đã bị gỡ bỏ hoặc khóa hoạt động do vi phạm {policyText}. Lý do: {request.Reason}. Nếu bạn cho rằng đây là một sự nhầm lẫn, bạn có thể nộp đơn khiếu nại (Appeal) trong Creator Studio.",
                "/studio",
                "report",
                report.ReportId,
                ct
            );
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

        // Notify the reporter with clear context
        string reporterMsg = decision == "dismiss"
            ? $"Cảm ơn bạn đã gửi báo cáo đối với {targetTypeStr} \"{targetTitle}\". Sau khi xem xét kỹ lưỡng, chúng tôi xác định nội dung này không vi phạm {policyText} và tuân thủ nguyên tắc cộng đồng."
            : $"Cảm ơn bạn đã gửi báo cáo đối với {targetTypeStr} \"{targetTitle}\". Chúng tôi đã thẩm định và xác nhận nội dung vi phạm {policyText}. Biện pháp xử lý đã được áp dụng ({message}). Đóng góp của bạn giúp cộng đồng HuTube an toàn hơn.";

        await notifications.PublishAsync(
            report.UserId,
            "report_resolved",
            "Kết quả xử lý báo cáo vi phạm",
            reporterMsg,
            "/",
            "report",
            report.ReportId,
            ct
        );

        return new ReportResolutionResponse(report.ReportId, finalStatus, decision, message);
#pragma warning restore CS0162
    }
}
