using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Application.Notifications;
using HuTube.Application.Rbac;
using HuTube.Application.Videos;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Videos;

public sealed class ModerationService(
    HuTubeDbContext db,
    RbacService rbac,
    INotificationService notifications)
{
    public async Task<List<ModerationQueueItemResponse>> GetQueueAsync(string? status = null, string? riskLevel = null, int page = 1, int pageSize = 20, CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);

        var query = db.ModerationCases.AsNoTracking().Where(c => c.CaseType == "upload_review");

        if (!string.IsNullOrWhiteSpace(status))
        {
            var normalizedStatus = status.Trim().ToLowerInvariant();
            query = query.Where(c => c.Status == normalizedStatus);
        }
        else
        {
            query = query.Where(c => c.Status == "pending" || c.Status == "reviewing" || c.Status == "escalated");
        }

        if (!string.IsNullOrWhiteSpace(riskLevel))
        {
            var normalizedRisk = riskLevel.Trim().ToLowerInvariant();
            query = normalizedRisk == "high" ? query.Where(c => c.RiskLevel == "high") : query.Where(c => c.RiskLevel != "high");
        }

        var sorted = query.OrderBy(c => c.RiskLevel == "high" ? 0 : 1)
                          .ThenBy(c => c.SubmittedAt);

        var cases = await sorted.Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        if (cases.Count == 0) return [];

        var videoIds = cases.Where(c => c.VideoId.HasValue).Select(c => c.VideoId!.Value).Distinct().ToList();
        var videos = await db.Videos.AsNoTracking().Where(v => videoIds.Contains(v.VideoId)).ToDictionaryAsync(v => v.VideoId, ct);

        var channelIds = videos.Values.Select(v => v.ChannelId).Distinct().ToList();
        var channels = await db.Channels.AsNoTracking().Where(c => channelIds.Contains(c.ChannelId)).ToDictionaryAsync(c => c.ChannelId, ct);

        var reviewerIds = cases.Where(c => c.ReviewerId.HasValue).Select(c => c.ReviewerId!.Value).Distinct().ToList();
        var reviewers = await db.Users.AsNoTracking().Where(u => reviewerIds.Contains(u.UserId)).ToDictionaryAsync(u => u.UserId, ct);

        var result = new List<ModerationQueueItemResponse>();
        foreach (var c in cases)
        {
            if (!c.VideoId.HasValue || !videos.TryGetValue(c.VideoId.Value, out var video)) continue;
            channels.TryGetValue(video.ChannelId, out var channel);
            reviewers.TryGetValue(c.ReviewerId ?? Guid.Empty, out var reviewer);

            result.Add(new ModerationQueueItemResponse(
                c.ModerationCaseId,
                video.VideoId,
                video.Title,
                video.Description,
                video.VideoUrl,
                video.ThumbnailUrl,
                video.Duration,
                video.ChannelId,
                channel?.Name ?? "Kênh không xác định",
                channel?.Handle,
                channel?.AvatarUrl,
                c.CaseType,
                c.Status,
                c.RiskLevel == "high" ? "high" : "low",
                c.ReviewerId,
                reviewer?.DisplayName,
                c.SubmittedAt,
                c.ClaimedAt,
                c.Note
            ));
        }

        return result;
    }

    public async Task<ModerationQueueItemResponse> ClaimCaseAsync(Guid actorId, Guid caseId, CancellationToken ct = default)
    {
        var moderationCase = await db.ModerationCases.FirstOrDefaultAsync(c => c.ModerationCaseId == caseId, ct)
            ?? throw new AuthException(404, "CASE_NOT_FOUND", "Không tìm thấy hồ sơ kiểm duyệt.");

        if (moderationCase.ReviewerId.HasValue && moderationCase.ReviewerId.Value != actorId && moderationCase.Status == "reviewing")
        {
            throw new AuthException(409, "CASE_ALREADY_CLAIMED", "Hồ sơ này đang được một kiểm duyệt viên khác xử lý.");
        }

        var now = DateTimeOffset.UtcNow;
        moderationCase.ReviewerId = actorId;
        moderationCase.Status = "reviewing";
        moderationCase.ClaimedAt = now;
        moderationCase.UpdatedAt = now;

        await db.SaveChangesAsync(ct);
        await rbac.LogAuditAsync(new AuditLogEntry(actorId, "moderation.claim", "moderation_case", caseId, "Nhận duyệt video"), ct);

        var queueItems = await GetQueueAsync(null, null, 1, 100, ct);
        return queueItems.FirstOrDefault(x => x.ModerationCaseId == caseId)
            ?? throw new AuthException(404, "CASE_NOT_FOUND", "Hồ sơ không khả dụng.");
    }

    public async Task<bool> ReleaseCaseAsync(Guid actorId, Guid caseId, CancellationToken ct = default)
    {
        var moderationCase = await db.ModerationCases.FirstOrDefaultAsync(c => c.ModerationCaseId == caseId, ct)
            ?? throw new AuthException(404, "CASE_NOT_FOUND", "Không tìm thấy hồ sơ kiểm duyệt.");

        if (moderationCase.ReviewerId == actorId && moderationCase.Status == "reviewing")
        {
            moderationCase.ReviewerId = null;
            moderationCase.ClaimedAt = null;
            moderationCase.Status = "pending";
            moderationCase.UpdatedAt = DateTimeOffset.UtcNow;

            await db.SaveChangesAsync(ct);
            await rbac.LogAuditAsync(new AuditLogEntry(actorId, "moderation.release", "moderation_case", caseId, "Bỏ nhận duyệt video"), ct);
            return true;
        }

        return false;
    }

    public async Task<ModerationDecisionResponse> ResolveCaseAsync(Guid actorId, Guid caseId, ResolveModerationRequest request, CancellationToken ct = default)
    {
        var decision = request.Decision.Trim().ToLowerInvariant();
        if (decision is not ("approve" or "age_restricted" or "recommendation_restricted" or "reject" or "escalate"))
            throw new AuthException(400, "INVALID_DECISION", "Quyết định không hợp lệ. Chỉ chấp nhận approve, age_restricted, recommendation_restricted, reject, escalate.");

        var moderationCase = await db.ModerationCases.FirstOrDefaultAsync(c => c.ModerationCaseId == caseId, ct)
            ?? throw new AuthException(404, "CASE_NOT_FOUND", "Không tìm thấy hồ sơ kiểm duyệt.");

        if (!moderationCase.VideoId.HasValue)
            throw new AuthException(400, "INVALID_CASE_TARGET", "Hồ sơ kiểm duyệt không gắn với video nào.");

        var video = await db.Videos.FirstOrDefaultAsync(v => v.VideoId == moderationCase.VideoId.Value, ct)
            ?? throw new AuthException(404, "VIDEO_NOT_FOUND", "Không tìm thấy video cần duyệt.");

        var channel = await db.Channels.AsNoTracking().FirstOrDefaultAsync(c => c.ChannelId == video.ChannelId, ct);
        var now = DateTimeOffset.UtcNow;
        var message = "";

        moderationCase.ReviewerId = actorId;
        moderationCase.Decision = decision;
        moderationCase.PolicyCode = string.IsNullOrWhiteSpace(request.PolicyCode)
            ? null
            : request.PolicyCode.Trim();
        moderationCase.InternalNote = request.InternalNote?.Trim();
        moderationCase.UpdatedAt = now;

        switch (decision)
        {
            case "approve":
                video.ModerationStatus = "approved";
                video.Status = "published";
                video.PublishedAt ??= now;
                video.UpdatedAt = now;

                moderationCase.Status = "approved";
                moderationCase.ResolvedAt = now;
                message = "Đã phê duyệt video an toàn và xuất bản thành công.";

                if (channel != null)
                {
                    await notifications.PublishAsync(channel.OwnerUserId, "video_approved", "Video đã được phê duyệt",
                        $"Video '{video.Title}' đã được phê duyệt và xuất bản công khai.", $"/watch/{video.VideoId}", "video", video.VideoId, ct);
                }
                break;

            case "age_restricted":
                video.ModerationStatus = "approved";
                video.AgeRestricted = true;
                video.Status = "published";
                video.PublishedAt ??= now;
                video.UpdatedAt = now;

                moderationCase.Status = "approved";
                moderationCase.ResolvedAt = now;
                message = "Đã phê duyệt video với giới hạn độ tuổi (18+).";

                if (channel != null)
                {
                    await notifications.PublishAsync(channel.OwnerUserId, "video_age_restricted", "Video gắn giới hạn độ tuổi",
                        $"Video '{video.Title}' được duyệt nhưng bị gắn nhãn 18+ do chứa nội dung phù hợp người trưởng thành.", $"/watch/{video.VideoId}", "video", video.VideoId, ct);
                }
                break;

            case "recommendation_restricted":
                video.ModerationStatus = "approved";
                video.Status = "published";
                video.PublishedAt ??= now;
                video.UpdatedAt = now;

                try
                {
                    var meta = JsonSerializer.Deserialize<Dictionary<string, object>>(video.Metadata) ?? [];
                    meta["recommendation_restricted"] = true;
                    video.Metadata = JsonSerializer.Serialize(meta);
                }
                catch
                {
                    video.Metadata = "{\"recommendation_restricted\":true}";
                }

                moderationCase.Status = "approved";
                moderationCase.ResolvedAt = now;
                message = "Đã phê duyệt video với hạn chế đề xuất.";

                if (channel != null)
                {
                    await notifications.PublishAsync(channel.OwnerUserId, "video_restricted", "Video hạn chế phân phối",
                        $"Video '{video.Title}' đã xuất bản nhưng bị hạn chế gợi ý tại Trang chủ/Khám phá do nội dung nhạy cảm.", $"/watch/{video.VideoId}", "video", video.VideoId, ct);
                }
                break;

            case "reject":
                if (string.IsNullOrWhiteSpace(request.PolicyCode) || string.IsNullOrWhiteSpace(request.Reason))
                    throw new AuthException(400, "REJECTION_DETAILS_REQUIRED", "Bắt buộc chọn mã chính sách và điền lý do từ chối.");

                video.ModerationStatus = "rejected";
                // The videos.status constraint uses "blocked" for content
                // that cannot be published; "rejected" belongs to the
                // moderation status field.
                video.Status = "blocked";
                video.UpdatedAt = now;

                moderationCase.Status = "rejected";
                moderationCase.Note = request.Reason.Trim();
                moderationCase.ResolvedAt = now;
                message = $"Đã từ chối xuất bản video do vi phạm chính sách {request.PolicyCode}.";

                if (channel != null)
                {
                    await notifications.PublishAsync(channel.OwnerUserId, "video_rejected", "Video bị từ chối xuất bản",
                        $"Video '{video.Title}' bị từ chối xuất bản do vi phạm điều khoản {request.PolicyCode}. Lý do: {request.Reason}", $"/studio", "video", video.VideoId, ct);
                }
                break;

            case "escalate":
                moderationCase.Status = "escalated";
                message = "Đã chuyển hồ sơ lên cấp quản trị cao hơn.";
                break;
        }

        await db.SaveChangesAsync(ct);
        await rbac.LogAuditAsync(new AuditLogEntry(
            actorId,
            $"moderation.{decision}",
            "video",
            video.VideoId,
            $"{message} - Lý do: {request.Reason ?? "Không có"} - Policy: {request.PolicyCode ?? "N/A"}"
        ), ct);

        return new ModerationDecisionResponse(
            moderationCase.ModerationCaseId,
            video.VideoId,
            moderationCase.Status,
            decision,
            moderationCase.PolicyCode,
            message
        );
    }
}
