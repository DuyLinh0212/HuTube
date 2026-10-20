using HuTube.Application.Auth;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Videos;

public static class ClaimLeasePolicy
{
    public static readonly TimeSpan Duration = TimeSpan.FromMinutes(15);

    public static bool IsActive(IClaimLease item, DateTimeOffset now) =>
        item.Status == "reviewing" && item.ClaimId.HasValue && item.ReviewerId.HasValue && item.ClaimExpiresAt > now;

    public static void Assign(IClaimLease item, Guid actorId, DateTimeOffset now)
    {
        var resolved = item is ModerationCase { ResolvedAt: not null } or Appeal { ResolvedAt: not null };
        var handoff = item.Status == "escalated" && (item is Appeal || item is ModerationCase { CaseType: "upload_review" });
        if (resolved || item.Status is not ("pending" or "reviewing") && !handoff)
            throw new AuthException(409, "CASE_ALREADY_PROCESSED", "Hồ sơ đã được xử lý.");
        if (IsActive(item, now))
        {
            if (item.ReviewerId == actorId) return; // An idempotent claim never renews the deadline.
            throw new AuthException(409, "CASE_ALREADY_CLAIMED", "Hồ sơ đang được kiểm duyệt viên khác xử lý.");
        }
        // PostgreSQL timestamps preserve microseconds. Return exactly the same
        // deadline on first acquisition and idempotent reads from the database.
        now = new DateTimeOffset(now.UtcTicks - now.UtcTicks % 10, TimeSpan.Zero);
        item.ReviewerId = actorId;
        item.Status = "reviewing";
        item.ClaimId = Guid.NewGuid();
        item.ClaimedAt = now;
        item.ClaimExpiresAt = now + Duration;
    }

    public static void Ensure(IClaimLease item, Guid actorId, Guid? claimId, DateTimeOffset now)
    {
        if (!item.ClaimId.HasValue || !item.ClaimExpiresAt.HasValue || item.Status != "reviewing")
            throw new AuthException(409, "CLAIM_REQUIRED", "Hãy nhận lại hồ sơ trước khi xử lý.");
        if (item.ClaimExpiresAt <= now)
            throw new AuthException(409, "CLAIM_EXPIRED", "Quyền xử lý đã hết hạn 15 phút. Hãy nhận lại hồ sơ.");
        if ((claimId.HasValue && claimId != item.ClaimId) || item.ReviewerId != actorId)
            throw new AuthException(409, "CLAIM_STALE", "Quyền xử lý đã thay đổi. Hãy tải lại và nhận hồ sơ.");
    }

    public static void Release(IClaimLease item)
    {
        item.ReviewerId = null; item.Status = "pending";
        item.ClaimedAt = null; item.ClaimId = null; item.ClaimExpiresAt = null;
    }

    public static async Task LockAsync(HuTubeDbContext db, IClaimLease item, CancellationToken ct)
    {
        if (!db.Database.IsRelational()) return;
        if (item is ModerationCase moderationCase)
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT moderation_case_id FROM moderation_cases WHERE moderation_case_id={moderationCase.ModerationCaseId} FOR UPDATE", ct);
        else if (item is Appeal appeal)
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT appeal_id FROM appeals WHERE appeal_id={appeal.AppealId} FOR UPDATE", ct);
        await db.Entry(item).ReloadAsync(ct);
    }
}
