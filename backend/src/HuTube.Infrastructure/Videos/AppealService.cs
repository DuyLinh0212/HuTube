using HuTube.Application.Auth;
using HuTube.Application.Notifications;
using HuTube.Application.Rbac;
using HuTube.Application.Videos;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Videos;

public sealed class AppealService(
    HuTubeDbContext db,
    RbacService rbac,
    INotificationService notifications)
{
    public async Task<AppealDto> CreateAppealAsync(Guid userId, CreateAppealRequest request, CancellationToken ct = default)
    {
        var targetType = request.TargetType?.Trim().ToLowerInvariant();
        if (targetType is not (AppealTargetTypes.Video or AppealTargetTypes.Channel or AppealTargetTypes.Comment or AppealTargetTypes.Strike))
            throw new AuthException(400, "INVALID_TARGET_TYPE", "Đối tượng khiếu nại chỉ chấp nhận video, channel, comment, hoặc strike.");

        if (string.IsNullOrWhiteSpace(request.Reason))
            throw new AuthException(400, "REASON_REQUIRED", "Vui lòng nhập chi tiết lý do khiếu nại.");

        string targetTitle = "Đối tượng kiểm duyệt";
        Guid? linkedModerationCaseId = request.ModerationCaseId;
        Guid? linkedStrikeId = request.StrikeId;

        switch (targetType)
        {
            case AppealTargetTypes.Video:
                var video = await db.Videos.AsNoTracking().FirstOrDefaultAsync(v => v.VideoId == request.TargetId, ct)
                    ?? throw new AuthException(404, "VIDEO_NOT_FOUND", "Không tìm thấy video cần khiếu nại.");

                var channel = await db.Channels.AsNoTracking().FirstOrDefaultAsync(c => c.ChannelId == video.ChannelId, ct);
                if (channel == null || channel.OwnerUserId != userId)
                    throw new AuthException(403, "NOT_VIDEO_OWNER", "Bạn chỉ có thể khiếu nại video thuộc quyền sở hữu của mình.");

                targetTitle = video.Title;

                if (linkedModerationCaseId == null)
                {
                    var mc = await db.ModerationCases.AsNoTracking()
                        .Where(m => m.VideoId == video.VideoId)
                        .OrderByDescending(m => m.SubmittedAt)
                        .FirstOrDefaultAsync(ct);
                    linkedModerationCaseId = mc?.ModerationCaseId;
                }
                break;

            case AppealTargetTypes.Channel:
                var ch = await db.Channels.AsNoTracking().FirstOrDefaultAsync(c => c.ChannelId == request.TargetId, ct)
                    ?? throw new AuthException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh cần khiếu nại.");

                if (ch.OwnerUserId != userId)
                    throw new AuthException(403, "NOT_CHANNEL_OWNER", "Bạn chỉ có thể khiếu nại kênh do mình sở hữu.");

                targetTitle = ch.Name;
                break;

            case AppealTargetTypes.Comment:
                var cm = await db.Comments.AsNoTracking().FirstOrDefaultAsync(c => c.CommentId == request.TargetId, ct)
                    ?? throw new AuthException(404, "COMMENT_NOT_FOUND", "Không tìm thấy bình luận cần khiếu nại.");

                if (cm.UserId != userId)
                    throw new AuthException(403, "NOT_COMMENT_AUTHOR", "Bạn chỉ có thể khiếu nại bình luận của mình.");

                targetTitle = cm.Content.Length > 50 ? cm.Content[..50] + "..." : cm.Content;
                break;

            case AppealTargetTypes.Strike:
                var st = await db.ChannelStrikes.AsNoTracking().FirstOrDefaultAsync(s => s.StrikeId == request.TargetId, ct)
                    ?? throw new AuthException(404, "STRIKE_NOT_FOUND", "Không tìm thấy bản ghi gậy phạt cần khiếu nại.");

                if (st.UserId != userId)
                    throw new AuthException(403, "NOT_STRIKE_TARGET", "Bạn chỉ có thể khiếu nại gậy phạt áp dụng cho tài khoản/kênh của mình.");

                targetTitle = $"Gậy phạt số {st.StrikeNumber} ({st.Severity})";
                linkedStrikeId = st.StrikeId;
                break;
        }

        // Check if there is already a pending or reviewing appeal for this target by this user
        var hasActiveAppeal = await db.Appeals.AsNoTracking().AnyAsync(a =>
            a.UserId == userId &&
            a.TargetId == request.TargetId &&
            (a.Status == AppealStatuses.Pending || a.Status == AppealStatuses.Reviewing), ct);

        if (hasActiveAppeal)
            throw new AuthException(409, "APPEAL_ALREADY_PENDING", "Bạn đã có một đơn khiếu nại đang chờ xử lý cho đối tượng này.");

        var existingAttempts = await db.Appeals.AsNoTracking()
            .CountAsync(a => a.UserId == userId && a.TargetId == request.TargetId, ct);

        var now = DateTimeOffset.UtcNow;
        var appeal = new Appeal
        {
            UserId = userId,
            TargetType = targetType,
            TargetId = request.TargetId,
            AppealNumber = existingAttempts + 1,
            Reason = request.Reason.Trim(),
            Status = AppealStatuses.Pending,
            EvidenceUrl = request.EvidenceUrl?.Trim(),
            EvidenceNote = request.EvidenceNote?.Trim(),
            ModerationCaseId = linkedModerationCaseId,
            StrikeId = linkedStrikeId,
            CreatedAt = now,
            UpdatedAt = now
        };

        db.Appeals.Add(appeal);
        await db.SaveChangesAsync(ct);

        await rbac.LogAuditAsync(new AuditLogEntry(
            userId,
            "appeal.create",
            "appeal",
            appeal.AppealId,
            $"Gửi đơn khiếu nại lần {appeal.AppealNumber} cho đối tượng '{targetTitle}' ({targetType})"
        ), ct);

        var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.UserId == userId, ct);

        return new AppealDto(
            appeal.AppealId,
            appeal.UserId,
            user?.DisplayName ?? user?.Username,
            appeal.TargetType,
            appeal.TargetId,
            targetTitle,
            appeal.AppealNumber,
            null,
            null,
            appeal.Reason,
            appeal.Status,
            appeal.ReviewNote,
            appeal.EvidenceUrl,
            appeal.EvidenceNote,
            appeal.ModerationCaseId,
            appeal.StrikeId,
            appeal.CreatedAt,
            appeal.ResolvedAt
        );
    }

    public async Task<List<AppealDto>> GetMyAppealsAsync(Guid userId, CancellationToken ct = default)
    {
        var appeals = await db.Appeals.AsNoTracking()
            .Where(a => a.UserId == userId)
            .OrderByDescending(a => a.CreatedAt)
            .ToListAsync(ct);

        if (appeals.Count == 0) return [];

        var reviewerIds = appeals.Where(a => a.ReviewerId.HasValue).Select(a => a.ReviewerId!.Value).Distinct().ToList();
        var reviewers = await db.Users.AsNoTracking()
            .Where(u => reviewerIds.Contains(u.UserId))
            .ToDictionaryAsync(u => u.UserId, u => u.DisplayName ?? u.Username, ct);

        var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.UserId == userId, ct);
        var userName = user?.DisplayName ?? user?.Username;

        return appeals.Select(a =>
        {
            string? reviewerName = null;
            if (a.ReviewerId.HasValue) reviewers.TryGetValue(a.ReviewerId.Value, out reviewerName);

            return new AppealDto(
                a.AppealId,
                a.UserId,
                userName,
                a.TargetType,
                a.TargetId,
                $"{a.TargetType.ToUpperInvariant()} ({a.TargetId})",
                a.AppealNumber,
                a.ReviewerId,
                reviewerName,
                a.Reason,
                a.Status,
                a.ReviewNote,
                a.EvidenceUrl,
                a.EvidenceNote,
                a.ModerationCaseId,
                a.StrikeId,
                a.CreatedAt,
                a.ResolvedAt
            );
        }).ToList();
    }

    public async Task<List<AppealDto>> GetAdminAppealsAsync(
        string? targetType = null,
        string? status = null,
        int page = 1,
        int pageSize = 50,
        CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);

        var query = db.Appeals.AsNoTracking();

        if (!string.IsNullOrWhiteSpace(targetType))
        {
            var t = targetType.Trim().ToLowerInvariant();
            query = query.Where(a => a.TargetType == t);
        }

        if (!string.IsNullOrWhiteSpace(status))
        {
            var s = status.Trim().ToLowerInvariant();
            query = query.Where(a => a.Status == s);
        }

        var appeals = await query
            .OrderBy(a => a.Status == AppealStatuses.Pending ? 0 : (a.Status == AppealStatuses.Reviewing ? 1 : 2))
            .ThenByDescending(a => a.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(ct);

        if (appeals.Count == 0) return [];

        var userIds = appeals.Select(a => a.UserId).Distinct().ToList();
        var users = await db.Users.AsNoTracking()
            .Where(u => userIds.Contains(u.UserId))
            .ToDictionaryAsync(u => u.UserId, u => u.DisplayName ?? u.Username, ct);

        var reviewerIds = appeals.Where(a => a.ReviewerId.HasValue).Select(a => a.ReviewerId!.Value).Distinct().ToList();
        var reviewers = await db.Users.AsNoTracking()
            .Where(u => reviewerIds.Contains(u.UserId))
            .ToDictionaryAsync(u => u.UserId, u => u.DisplayName ?? u.Username, ct);

        return appeals.Select(a =>
        {
            string? reviewerName = null;
            if (a.ReviewerId.HasValue) reviewers.TryGetValue(a.ReviewerId.Value, out reviewerName);

            return new AppealDto(
                a.AppealId,
                a.UserId,
                users.GetValueOrDefault(a.UserId, "Người dùng"),
                a.TargetType,
                a.TargetId,
                $"{a.TargetType.ToUpperInvariant()} ({a.TargetId})",
                a.AppealNumber,
                a.ReviewerId,
                reviewerName,
                a.Reason,
                a.Status,
                a.ReviewNote,
                a.EvidenceUrl,
                a.EvidenceNote,
                a.ModerationCaseId,
                a.StrikeId,
                a.CreatedAt,
                a.ResolvedAt
            );
        }).ToList();
    }

    public async Task<bool> ClaimAppealAsync(Guid actorId, Guid appealId, CancellationToken ct = default)
    {
        var appeal = await db.Appeals.FirstOrDefaultAsync(a => a.AppealId == appealId, ct)
            ?? throw new AuthException(404, "APPEAL_NOT_FOUND", "Không tìm thấy đơn khiếu nại.");

        await EnsureSeparationOfDutiesAsync(actorId, appeal, ct);

        appeal.ReviewerId = actorId;
        appeal.Status = AppealStatuses.Reviewing;
        appeal.UpdatedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync(ct);
        await rbac.LogAuditAsync(new AuditLogEntry(actorId, "appeal.claim", "appeal", appealId, "Nhận thụ lý đơn khiếu nại"), ct);
        return true;
    }

    public async Task<bool> ReleaseAppealAsync(Guid actorId, Guid appealId, CancellationToken ct = default)
    {
        var appeal = await db.Appeals.FirstOrDefaultAsync(a => a.AppealId == appealId, ct)
            ?? throw new AuthException(404, "APPEAL_NOT_FOUND", "Không tìm thấy đơn khiếu nại.");

        if (appeal.ReviewerId == actorId && appeal.Status == AppealStatuses.Reviewing)
        {
            appeal.ReviewerId = null;
            appeal.Status = AppealStatuses.Pending;
            appeal.UpdatedAt = DateTimeOffset.UtcNow;

            await db.SaveChangesAsync(ct);
            await rbac.LogAuditAsync(new AuditLogEntry(actorId, "appeal.release", "appeal", appealId, "Trả đơn khiếu nại về hàng đợi"), ct);
            return true;
        }

        return false;
    }

    public async Task<AppealResolutionResponse> ResolveAppealAsync(Guid actorId, Guid appealId, ResolveAppealRequest request, CancellationToken ct = default)
    {
        var decision = request.Decision?.Trim().ToLowerInvariant();
        if (decision is not ("approve" or "reject" or "escalate"))
            throw new AuthException(400, "INVALID_DECISION", "Quyết định xử lý chỉ chấp nhận approve, reject, hoặc escalate.");

        var appeal = await db.Appeals.FirstOrDefaultAsync(a => a.AppealId == appealId, ct)
            ?? throw new AuthException(404, "APPEAL_NOT_FOUND", "Không tìm thấy đơn khiếu nại.");

        // Rule: Separation of duties check
        await EnsureSeparationOfDutiesAsync(actorId, appeal, ct);

        var now = DateTimeOffset.UtcNow;
        appeal.ReviewerId = actorId;
        appeal.ReviewNote = request.ReviewNote?.Trim();
        appeal.UpdatedAt = now;

        string targetTitle = appeal.TargetType switch
        {
            AppealTargetTypes.Video => (await db.Videos.AsNoTracking().Where(v => v.VideoId == appeal.TargetId).Select(v => v.Title).FirstOrDefaultAsync(ct)) ?? "Video",
            AppealTargetTypes.Channel => (await db.Channels.AsNoTracking().Where(c => c.ChannelId == appeal.TargetId).Select(c => c.Name).FirstOrDefaultAsync(ct)) ?? "Kênh",
            AppealTargetTypes.Comment => "Bình luận",
            _ => "Nội dung"
        };

        string message;
        if (decision == "approve")
        {
            appeal.Status = AppealStatuses.Approved;
            appeal.ResolvedAt = now;
            message = "Đã chấp thuận đơn khiếu nại và phục hồi quyền lợi nội dung/kênh.";

            // Auto restoration logic based on TargetType
            if (appeal.TargetType == AppealTargetTypes.Video)
            {
                var video = await db.Videos.FirstOrDefaultAsync(v => v.VideoId == appeal.TargetId, ct);
                if (video != null)
                {
                    video.ModerationStatus = "approved";
                    video.Status = "published";
                    video.UpdatedAt = now;

                    // If moderation case exists, update it
                    if (appeal.ModerationCaseId.HasValue)
                    {
                        var mc = await db.ModerationCases.FirstOrDefaultAsync(m => m.ModerationCaseId == appeal.ModerationCaseId.Value, ct);
                        if (mc != null)
                        {
                            mc.Status = "approved";
                            mc.Decision = "appeal_approved";
                            mc.UpdatedAt = now;
                        }
                    }

                    // Check if channel was suspended due to 5 rejections, and if current distinct rejections is now < 5, unlock channel
                    var remainingRejects = await db.Videos.AsNoTracking()
                        .Where(v => v.ChannelId == video.ChannelId && v.VideoId != video.VideoId && v.ModerationStatus == "rejected")
                        .Select(v => v.VideoId)
                        .Distinct()
                        .CountAsync(ct);

                    var ch = await db.Channels.FirstOrDefaultAsync(c => c.ChannelId == video.ChannelId, ct);
                    if (ch != null && ch.Status == "suspended" && remainingRejects < 5)
                    {
                        ch.Status = "active";
                        ch.UpdatedAt = now;

                        // Also revoke auto strike if any
                        var autoStrike = await db.ChannelStrikes.FirstOrDefaultAsync(s =>
                            s.ChannelId == ch.ChannelId && s.PolicyCode == "SPAM.REPEATED_VIOLATIONS" && s.Status == StrikeStatuses.Active, ct);
                        if (autoStrike != null)
                        {
                            autoStrike.Status = StrikeStatuses.Revoked;
                            autoStrike.RevokedAt = now;
                            autoStrike.RevokedByUserId = actorId;
                            autoStrike.RevocationReason = "Thu hồi do khiếu nại video được chấp thuận.";
                        }
                    }
                }
            }
            else if (appeal.TargetType == AppealTargetTypes.Channel)
            {
                var ch = await db.Channels.FirstOrDefaultAsync(c => c.ChannelId == appeal.TargetId, ct);
                if (ch != null)
                {
                    ch.Status = "active";
                    ch.UpdatedAt = now;
                }
            }
            else if (appeal.TargetType == AppealTargetTypes.Comment)
            {
                var cm = await db.Comments.FirstOrDefaultAsync(c => c.CommentId == appeal.TargetId, ct);
                if (cm != null)
                {
                    cm.Status = "visible";
                    cm.UpdatedAt = now;
                }
            }
            else if (appeal.TargetType == AppealTargetTypes.Strike || appeal.StrikeId.HasValue)
            {
                var strikeId = appeal.StrikeId ?? appeal.TargetId;
                var st = await db.ChannelStrikes.FirstOrDefaultAsync(s => s.StrikeId == strikeId, ct);
                if (st != null && st.Status != StrikeStatuses.Revoked)
                {
                    st.Status = StrikeStatuses.Revoked;
                    st.RevokedAt = now;
                    st.RevokedByUserId = actorId;
                    st.RevocationReason = "Khiếu nại được chấp thuận: " + (request.ReviewNote ?? "Xem xét lại hợp lệ");

                    // Check if channel was suspended due to strikes and can now be unlocked
                    var ch = await db.Channels.FirstOrDefaultAsync(c => c.ChannelId == st.ChannelId, ct);
                    if (ch != null && ch.Status == "suspended")
                    {
                        var remainingActive = await db.ChannelStrikes
                            .CountAsync(s => s.ChannelId == ch.ChannelId && s.StrikeId != st.StrikeId && s.Status == StrikeStatuses.Active && s.ExpiresAt > now, ct);
                        if (remainingActive < 3)
                        {
                            ch.Status = "active";
                            ch.UpdatedAt = now;
                        }
                    }
                }
            }

            await notifications.PublishAsync(
                appeal.UserId,
                "appeal_approved",
                "Khiếu nại của bạn đã được chấp thuận",
                $"Đơn khiếu nại #{appeal.AppealNumber} của bạn đối với {appeal.TargetType} \"{targetTitle}\" đã được xem xét và chấp thuận. Ghi chú: {request.ReviewNote ?? "Xem xét lại hợp lệ, các hạn chế liên quan đã được gỡ bỏ."}",
                "/studio",
                "appeal",
                appeal.AppealId,
                ct
            );
        }
        else if (decision == "reject")
        {
            appeal.Status = AppealStatuses.Rejected;
            appeal.ResolvedAt = now;
            message = "Đã bác bỏ đơn khiếu nại.";

            await notifications.PublishAsync(
                appeal.UserId,
                "appeal_rejected",
                "Khiếu nại của bạn đã bị từ chối",
                $"Đơn khiếu nại #{appeal.AppealNumber} của bạn đối với {appeal.TargetType} \"{targetTitle}\" đã bị từ chối sau khi xem xét kỹ lưỡng. Lý do: {request.ReviewNote ?? "Nội dung vẫn vi phạm điều khoản chính sách cộng đồng."}",
                "/studio",
                "appeal",
                appeal.AppealId,
                ct
            );
        }
        else // escalate
        {
            appeal.Status = "escalated";
            message = "Đã chuyển đơn khiếu nại lên cấp cao hơn.";
        }

        await db.SaveChangesAsync(ct);

        await rbac.LogAuditAsync(new AuditLogEntry(
            actorId,
            $"appeal.{decision}",
            "appeal",
            appeal.AppealId,
            $"{message} - Ghi chú: {request.ReviewNote ?? "Không có"}"
        ), ct);

        return new AppealResolutionResponse(appeal.AppealId, appeal.Status, decision, message);
    }

    private async Task EnsureSeparationOfDutiesAsync(Guid actorId, Appeal appeal, CancellationToken ct)
    {
        // 1. If linked to ModerationCase, reviewer who decided that case cannot resolve appeal
        if (appeal.ModerationCaseId.HasValue)
        {
            var mc = await db.ModerationCases.AsNoTracking()
                .FirstOrDefaultAsync(m => m.ModerationCaseId == appeal.ModerationCaseId.Value, ct);
            if (mc?.ReviewerId.HasValue == true && mc.ReviewerId.Value == actorId)
            {
                throw new AuthException(403, "CANNOT_RESOLVE_OWN_CASE", "Bạn không thể tự duyệt đơn khiếu nại đối với quyết định kiểm duyệt do chính bạn ban hành.");
            }
        }

        // 2. If target is video, check any moderation cases for this video
        if (appeal.TargetType == AppealTargetTypes.Video)
        {
            var originalReviewer = await db.ModerationCases.AsNoTracking()
                .Where(m => m.VideoId == appeal.TargetId && m.ReviewerId.HasValue)
                .OrderByDescending(m => m.SubmittedAt)
                .Select(m => m.ReviewerId)
                .FirstOrDefaultAsync(ct);

            if (originalReviewer.HasValue && originalReviewer.Value == actorId)
            {
                throw new AuthException(403, "CANNOT_RESOLVE_OWN_CASE", "Bạn không thể tự duyệt đơn khiếu nại đối với video do chính bạn kiểm duyệt.");
            }
        }

        // 3. If target is strike, check who revoked or created it
        if (appeal.TargetType == AppealTargetTypes.Strike || appeal.StrikeId.HasValue)
        {
            var strikeId = appeal.StrikeId ?? appeal.TargetId;
            var st = await db.ChannelStrikes.AsNoTracking().FirstOrDefaultAsync(s => s.StrikeId == strikeId, ct);
            if (st?.RevokedByUserId.HasValue == true && st.RevokedByUserId.Value == actorId)
            {
                throw new AuthException(403, "CANNOT_RESOLVE_OWN_CASE", "Bạn không thể tự duyệt đơn khiếu nại cho bản ghi này.");
            }
        }
    }
}
