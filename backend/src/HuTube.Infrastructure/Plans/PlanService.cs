using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Application.Rbac;
using HuTube.Application.Plans;
using HuTube.Domain.Plans;
using HuTube.Domain.Users;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Plans;

public sealed class PlanService(
    HuTubeDbContext db,
    IAuthEmailSender emailSender,
    TimeProvider clock,
    AuthOptions authOptions,
    RbacService audit) : IPlanService
{
    private DateTimeOffset Now => clock.GetUtcNow();

    public async Task<IReadOnlyList<PlanResponse>> GetPlansAsync(CancellationToken ct = default)
    {
        var plans = await db.Plans.AsNoTracking()
            .Where(x => x.Status == "active")
            .OrderBy(x => x.Price)
            .ToListAsync(ct);

        return plans.Select(x => new PlanResponse(
            x.PlanId,
            x.Code,
            x.Name,
            x.Description,
            x.Price,
            x.DurationDays,
            x.StorageLimit,
            x.MaxUploadSize,
            x.MaxVideoDuration,
            x.MaxVideoQuality,
            x.MaxMembers,
            x.Status)).ToList();
    }

    public async Task<IReadOnlyList<PlanResponse>> GetAdminPlansAsync(CancellationToken ct = default) =>
        (await db.Plans.AsNoTracking().OrderBy(x => x.Price).ThenBy(x => x.Code).ToListAsync(ct))
        .Select(ToResponse).ToList();

    public async Task<PlanResponse> CreatePlanAsync(Guid actorUserId, CreatePlanRequest request, CancellationToken ct = default)
    {
        ValidatePlan(request.Code, request.Name, request.Price, request.DurationDays, request.StorageLimit,
            request.MaxUploadSize, request.MaxVideoDuration, request.MaxVideoQuality, request.MaxMembers, "active");
        var code = request.Code.Trim().ToLowerInvariant();
        if (await db.Plans.AnyAsync(x => x.Code == code, ct))
            throw new PlanException(409, "PLAN_CODE_EXISTS", "Mã gói đã tồn tại.");
        var now = Now;
        var plan = new Plan { PlanId = Guid.NewGuid(), Code = code, Name = request.Name.Trim(), Description = Clean(request.Description),
            Price = request.Price, DurationDays = request.DurationDays, StorageLimit = request.StorageLimit,
            MaxUploadSize = request.MaxUploadSize, MaxVideoDuration = request.MaxVideoDuration,
            MaxVideoQuality = request.MaxVideoQuality.Trim().ToLowerInvariant(), MaxMembers = request.MaxMembers,
            Features = string.IsNullOrWhiteSpace(request.Features) ? "{}" : request.Features, Status = "active", CreatedAt = now, UpdatedAt = now };
        db.Plans.Add(plan);
        await db.SaveChangesAsync(ct);
        await audit.LogAuditAsync(new AuditLogEntry(actorUserId, "plan.created", "plan", plan.PlanId, "Admin tạo gói dịch vụ",
            NewValues: JsonSerializer.Serialize(ToResponse(plan))), ct);
        return ToResponse(plan);
    }

    public async Task<PlanResponse> UpdatePlanAsync(Guid actorUserId, Guid planId, UpdatePlanRequest request, CancellationToken ct = default)
    {
        var plan = await db.Plans.SingleOrDefaultAsync(x => x.PlanId == planId, ct)
            ?? throw new PlanException(404, "PLAN_NOT_FOUND", "Gói dịch vụ không tồn tại.");
        ValidatePlan(plan.Code, request.Name, request.Price, request.DurationDays, request.StorageLimit,
            request.MaxUploadSize, request.MaxVideoDuration, request.MaxVideoQuality, request.MaxMembers, request.Status);
        var old = ToResponse(plan);
        plan.Name = request.Name.Trim(); plan.Description = Clean(request.Description); plan.Price = request.Price;
        plan.DurationDays = request.DurationDays; plan.StorageLimit = request.StorageLimit; plan.MaxUploadSize = request.MaxUploadSize;
        plan.MaxVideoDuration = request.MaxVideoDuration; plan.MaxVideoQuality = request.MaxVideoQuality.Trim().ToLowerInvariant();
        plan.MaxMembers = request.MaxMembers; plan.Status = request.Status.Trim().ToLowerInvariant();
        plan.Features = string.IsNullOrWhiteSpace(request.Features) ? "{}" : request.Features; plan.UpdatedAt = Now;
        await db.SaveChangesAsync(ct);
        await audit.LogAuditAsync(new AuditLogEntry(actorUserId, "plan.updated", "plan", plan.PlanId, "Admin cập nhật gói dịch vụ",
            OldValues: JsonSerializer.Serialize(old), NewValues: JsonSerializer.Serialize(ToResponse(plan))), ct);
        return ToResponse(plan);
    }

    public async Task ArchivePlanAsync(Guid actorUserId, Guid planId, CancellationToken ct = default)
    {
        var plan = await db.Plans.SingleOrDefaultAsync(x => x.PlanId == planId, ct)
            ?? throw new PlanException(404, "PLAN_NOT_FOUND", "Gói dịch vụ không tồn tại.");
        plan.Status = "archived"; plan.UpdatedAt = Now;
        await db.SaveChangesAsync(ct);
        await audit.LogAuditAsync(new AuditLogEntry(actorUserId, "plan.archived", "plan", plan.PlanId, "Admin lưu trữ gói dịch vụ"), ct);
    }

    public async Task<PlanResponse> GetPlanByIdAsync(Guid planId, CancellationToken ct = default)
    {
        var plan = await db.Plans.AsNoTracking().SingleOrDefaultAsync(x => x.PlanId == planId && x.Status == "active", ct)
            ?? throw new PlanException(404, "PLAN_NOT_FOUND", "Gói dịch vụ không tồn tại.");

        return new PlanResponse(
            plan.PlanId,
            plan.Code,
            plan.Name,
            plan.Description,
            plan.Price,
            plan.DurationDays,
            plan.StorageLimit,
            plan.MaxUploadSize,
            plan.MaxVideoDuration,
            plan.MaxVideoQuality,
            plan.MaxMembers,
            plan.Status);
    }

    public async Task<PlanShareResponse> GetPlanShareAsync(Guid planId, CancellationToken ct = default)
    {
        var plan = await db.Plans.AsNoTracking().SingleOrDefaultAsync(x => x.PlanId == planId && x.Status == "active", ct)
            ?? throw new PlanException(404, "PLAN_NOT_FOUND", "Gói dịch vụ không tồn tại.");

        var shareUrl = $"{authOptions.WebBaseUrl.TrimEnd('/')}/plans/{plan.PlanId}";
        return new PlanShareResponse(plan.PlanId, plan.Code, plan.Name, plan.Description, shareUrl, plan.Status);
    }

    public async Task<PlanDetailResponse> GetMyPlanAsync(Guid userId, CancellationToken ct = default)
    {
        var user = await db.Users.AsNoTracking().SingleAsync(x => x.UserId == userId, ct);
        var plan = user.PlanId.HasValue
            ? await GetEffectivePlanAsync(userId, user.PlanId.Value, ct)
            : null;

        if (plan == null)
            return new PlanDetailResponse(null, null, null, 0, 0, 0, 0, null, 1, []);

        var channelId = await db.Channels.AsNoTracking()
            .Where(x => x.OwnerUserId == userId && x.Status == "active")
            .Select(x => x.ChannelId)
            .SingleOrDefaultAsync(ct);

        var usedStorage = channelId == Guid.Empty
            ? 0L
            : await db.ChannelQuotas.AsNoTracking()
                .Where(x => x.ChannelId == channelId)
                .Select(x => x.StorageUsed)
                .SingleOrDefaultAsync(ct);

        var activeHistory = await db.PlanHistories.AsNoTracking()
            .Where(x => x.UserId == userId && x.PlanId == plan.PlanId && x.Status == "active")
            .OrderByDescending(x => x.StartedAt)
            .FirstOrDefaultAsync(ct);

        var isSharedMember = false;
        if (activeHistory == null)
        {
            // Kiểm tra xem có phải là thành viên được chia sẻ gói không
            var sharedMember = await (from m in db.PlanMembers.AsNoTracking()
                                      join h in db.PlanHistories.AsNoTracking() on m.PlanHistoryId equals h.PlanHistoryId
                                      where m.MemberUserId == userId && m.Status == "accepted" && h.PlanId == plan.PlanId
                                            && h.Status == "active" && h.EndedAt > Now
                                      select new { Member = m, History = h }).FirstOrDefaultAsync(ct);
            if (sharedMember != null)
            {
                isSharedMember = true;
                activeHistory = sharedMember.History;
            }
        }

        var members = activeHistory == null || isSharedMember
            ? new List<PlanMemberResponse>()
            : await db.PlanMembers.AsNoTracking()
                .Where(x => x.PlanHistoryId == activeHistory.PlanHistoryId && x.Status != "revoked")
                .OrderBy(x => x.InvitedAt)
                .Select(x => new PlanMemberResponse(
                    x.PlanMemberId,
                    x.PlanHistoryId,
                    x.OwnerUserId,
                    x.MemberEmail,
                    x.MemberUserId,
                    x.Status,
                    x.InvitedAt,
                    x.AcceptedAt,
                    x.RevokedAt))
                .ToListAsync(ct);

        var remainingStorage = Math.Max(0, plan.StorageLimit - usedStorage);

        var subscriptionInfo = activeHistory != null
            ? new PlanSubscriptionInfo(
                activeHistory.PlanHistoryId,
                activeHistory.StartedAt,
                activeHistory.EndedAt,
                activeHistory.AutoRenew,
                activeHistory.EndedAt.HasValue && activeHistory.EndedAt.Value <= Now)
            : null;

        var activePaidPlanIds = await (from h in db.PlanHistories.AsNoTracking()
                                        join p in db.Plans.AsNoTracking() on h.PlanId equals p.PlanId
                                        where h.UserId == userId && p.Price > 0 && (!h.EndedAt.HasValue || h.EndedAt > Now)
                                        select h.PlanId).Distinct().ToListAsync(ct);

        return new PlanDetailResponse(
            plan.PlanId,
            plan.Code,
            plan.Name,
            plan.StorageLimit,
            usedStorage,
            remainingStorage,
            plan.MaxUploadSize,
            plan.MaxVideoQuality,
            plan.MaxMembers,
            members,
            subscriptionInfo,
            isSharedMember,
            plan.Price,
            activePaidPlanIds);
    }

    public async Task<PlanResponse> SubscribeAsync(Guid userId, Guid planId, PlanSubscriptionRequest request, CancellationToken ct = default)
    {
        var user = await db.Users.SingleAsync(x => x.UserId == userId, ct);
        var plan = await db.Plans.SingleAsync(x => x.PlanId == planId && x.Status == "active", ct);
        var now = Now;

        // Kiểm tra xem người dùng có gói đang active hay không
        var activeSub = await (from h in db.PlanHistories.AsNoTracking()
                               join p in db.Plans.AsNoTracking() on h.PlanId equals p.PlanId
                               where h.UserId == userId && h.Status == "active" && (!h.EndedAt.HasValue || h.EndedAt > now)
                               orderby h.StartedAt descending
                               select new { History = h, Plan = p }).FirstOrDefaultAsync(ct);

        if (activeSub != null)
        {
            // 1. Không cho phép đăng ký lại chính gói đang sử dụng khi chưa hết hạn
            if (activeSub.History.PlanId == planId)
            {
                var expiryText = activeSub.History.EndedAt.HasValue
                    ? activeSub.History.EndedAt.Value.ToLocalTime().ToString("dd/MM/yyyy HH:mm")
                    : "vô thời hạn";
                throw new PlanException(400, "PLAN_ALREADY_ACTIVE",
                    $"Bạn đang sử dụng gói này (còn hạn đến {expiryText}). Bạn chỉ có thể đăng ký lại sau khi gói hết hạn.");
            }

            // 2. Các quy tắc đổi/hạ gói chỉ áp dụng khi gói hiện tại là gói trả phí.
            if (activeSub.Plan.Price > 0 && plan.Price < activeSub.Plan.Price)
            {
                throw new PlanException(400, "PLAN_DOWNGRADE_NOT_ALLOWED",
                    "Bạn chỉ có thể hạ xuống gói nhỏ hơn sau khi gói hiện tại hết hạn.");
            }

            if (activeSub.Plan.Price > 0)
            {
                // 3. Khi gói trả phí hiện tại còn hạn, chỉ được chuyển sang gói trả phí đã mua và còn hạn.
                var targetWasPurchased = plan.Price > 0 && await db.PlanHistories.AnyAsync(
                    x => x.UserId == userId
                         && x.PlanId == planId
                         && x.Status == "active"
                         && (!x.EndedAt.HasValue || x.EndedAt > now), ct);
                if (!targetWasPurchased)
                {
                    throw new PlanException(400, "PLAN_NOT_AVAILABLE_FOR_SWITCH",
                        "Bạn chỉ có thể đổi sang gói trả phí đã mua và còn hạn.");
                }
            }
        }

        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        await db.PlanHistories.Where(x => x.UserId == userId && x.Status == "active")
            .ExecuteUpdateAsync(update => update.SetProperty(x => x.Status, "expired").SetProperty(x => x.EndedAt, now), ct);
        user.PlanId = plan.PlanId;
        user.UpdatedAt = now;
        db.PlanHistories.Add(new PlanHistory
        {
            PlanHistoryId = Guid.NewGuid(), UserId = userId, PlanId = plan.PlanId, OwnerUserId = userId,
            Status = "active", StartedAt = now, EndedAt = now.AddDays(plan.DurationDays), AutoRenew = request.AutoRenew, CreatedAt = now
        });

        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);
        return new PlanResponse(plan.PlanId, plan.Code, plan.Name, plan.Description, plan.Price, plan.DurationDays, plan.StorageLimit, plan.MaxUploadSize, plan.MaxVideoDuration, plan.MaxVideoQuality, plan.MaxMembers, plan.Status);
    }

    public async Task<PlanMemberResponse> InviteMemberAsync(Guid ownerUserId, string email, CancellationToken ct = default)
    {
        var normalizedEmail = email.Trim();
        if (!normalizedEmail.Contains('@')) throw new PlanException(400, "INVALID_EMAIL", "Email không hợp lệ.");

        var user = await db.Users.AsNoTracking().SingleAsync(x => x.UserId == ownerUserId, ct);
        if (!user.PlanId.HasValue) throw new PlanException(400, "NO_ACTIVE_PLAN", "Bạn chưa có gói dịch vụ.");

        var plan = await GetEffectivePlanAsync(ownerUserId, user.PlanId.Value, ct)
            ?? throw new PlanException(400, "PLAN_EXPIRED", "Gói dịch vụ đã hết hạn.");
        if (plan.MaxMembers <= 1) throw new PlanException(400, "PLAN_SHARE_NOT_ALLOWED", "Gói hiện tại không cho phép chia sẻ.");

        var activeHistory = await db.PlanHistories.AsNoTracking()
            .Where(x => x.UserId == ownerUserId && x.PlanId == plan.PlanId && x.Status == "active")
            .OrderByDescending(x => x.StartedAt)
            .FirstOrDefaultAsync(ct);

        if (activeHistory == null)
        {
            activeHistory = new PlanHistory
            {
                PlanHistoryId = Guid.NewGuid(),
                UserId = ownerUserId,
                PlanId = plan.PlanId,
                OwnerUserId = ownerUserId,
                Status = "active",
                StartedAt = Now,
                EndedAt = Now.AddDays(plan.DurationDays),
                CreatedAt = Now
            };
            db.PlanHistories.Add(activeHistory);
            await db.SaveChangesAsync(ct);
        }

        var currentMembers = await db.PlanMembers.AsNoTracking().CountAsync(x => x.PlanHistoryId == activeHistory.PlanHistoryId && x.Status != "revoked", ct);
        if (currentMembers + 1 >= plan.MaxMembers) throw new PlanException(409, "PLAN_MEMBER_LIMIT_EXCEEDED", "Số lượng thành viên đã đạt giới hạn gói.");

        var member = new PlanMember
        {
            PlanMemberId = Guid.NewGuid(),
            PlanHistoryId = activeHistory.PlanHistoryId,
            OwnerUserId = ownerUserId,
            MemberEmail = normalizedEmail,
            Status = "pending",
            InvitedAt = Now
        };
        db.PlanMembers.Add(member);
        await db.SaveChangesAsync(ct);

        var token = Convert.ToBase64String(Guid.NewGuid().ToByteArray()).Replace("=", "").Replace("+", "-").Replace("/", "_");
        db.PlanInvitationTokens.Add(new PlanInvitationToken
        {
            PlanInvitationTokenId = Guid.NewGuid(),
            PlanMemberId = member.PlanMemberId,
            Token = token,
            ExpiresAt = Now.AddDays(7),
            CreatedAt = Now
        });
        await db.SaveChangesAsync(ct);

        var acceptUrl = $"{authOptions.WebBaseUrl.TrimEnd('/')}/plans/accept-invite?memberId={member.PlanMemberId}&token={Uri.EscapeDataString(token)}";
        try
        {
            await emailSender.SendAsync(normalizedEmail, "Lời mời dùng chung gói HuTube", $"Bạn được mời tham gia gói của {user.DisplayName}.\n\nXác nhận: {acceptUrl}", ct);
        }
        catch
        {
            // The database invitation remains the source of truth when delivery is unavailable.
        }

        return new PlanMemberResponse(member.PlanMemberId, plan.PlanId, ownerUserId, member.MemberEmail, member.MemberUserId, member.Status, member.InvitedAt, member.AcceptedAt, member.RevokedAt);
    }

    public async Task<PlanMemberResponse> AcceptInvitationAsync(Guid userId, Guid memberId, string token, CancellationToken ct = default)
    {
        var member = await db.PlanMembers.SingleOrDefaultAsync(x => x.PlanMemberId == memberId, ct)
            ?? throw new PlanException(404, "INVITATION_NOT_FOUND", "Lời mời không tồn tại.");

        var invitationToken = await db.PlanInvitationTokens.SingleOrDefaultAsync(x => x.PlanMemberId == memberId && x.Token == token, ct)
            ?? throw new PlanException(400, "INVALID_TOKEN", "Token không hợp lệ.");

        if (invitationToken.ExpiresAt < Now) throw new PlanException(400, "INVITATION_EXPIRED", "Lời mời đã hết hạn.");
        if (member.Status != "pending") throw new PlanException(409, "INVITATION_ALREADY_PROCESSED", "Lời mời đã được xử lý.");

        var user = await db.Users.SingleAsync(x => x.UserId == userId, ct);
        if (!string.Equals(user.Email, member.MemberEmail, StringComparison.OrdinalIgnoreCase))
            throw new PlanException(403, "EMAIL_MISMATCH", "Email xác nhận không khớp với lời mời.");

        member.MemberUserId = userId;
        member.Status = "accepted";
        member.AcceptedAt = Now;
        invitationToken.UsedAt = Now;
        if (!user.PlanId.HasValue)
        {
            var activePlanId = await db.PlanHistories.AsNoTracking()
                .Where(x => x.PlanHistoryId == member.PlanHistoryId)
                .Select(x => x.PlanId)
                .SingleOrDefaultAsync(ct);

            user.PlanId = activePlanId == Guid.Empty ? null : activePlanId;
        }

        await db.SaveChangesAsync(ct);

        var planId = await db.PlanHistories.AsNoTracking()
            .Where(y => y.PlanHistoryId == member.PlanHistoryId)
            .Select(y => y.PlanId)
            .SingleAsync(ct);

        var plan = await db.Plans.AsNoTracking().SingleOrDefaultAsync(x => x.PlanId == planId, ct);
        return new PlanMemberResponse(member.PlanMemberId, plan?.PlanId ?? Guid.Empty, member.OwnerUserId, member.MemberEmail, member.MemberUserId, member.Status, member.InvitedAt, member.AcceptedAt, member.RevokedAt);
    }

    public async Task RemoveMemberAsync(Guid ownerUserId, Guid memberId, CancellationToken ct = default)
    {
        var member = await db.PlanMembers.SingleOrDefaultAsync(x => x.PlanMemberId == memberId && x.OwnerUserId == ownerUserId, ct)
            ?? throw new PlanException(404, "PLAN_MEMBER_NOT_FOUND", "Thành viên không tồn tại hoặc không thuộc quyền quản lý của bạn.");

        member.Status = "revoked";
        member.RevokedAt = Now;
        await db.SaveChangesAsync(ct);
    }

    private async Task<Plan?> GetEffectivePlanAsync(Guid userId, Guid planId, CancellationToken ct)
    {
        var plan = await db.Plans.AsNoTracking().SingleOrDefaultAsync(x => x.PlanId == planId && x.Status == "active", ct);
        if (plan == null) return null;
        var now = Now;
        var hasSubscription = await db.PlanHistories.AsNoTracking().AnyAsync(x =>
            x.UserId == userId && x.PlanId == planId && x.Status == "active" && x.EndedAt > now, ct)
            || await (from member in db.PlanMembers.AsNoTracking()
                      join history in db.PlanHistories.AsNoTracking() on member.PlanHistoryId equals history.PlanHistoryId
                      where member.MemberUserId == userId && member.Status == "accepted" && history.PlanId == planId
                            && history.Status == "active" && history.EndedAt > now
                      select member.PlanMemberId).AnyAsync(ct);
        return hasSubscription ? plan : null;
    }

    private static PlanResponse ToResponse(Plan x) => new(x.PlanId, x.Code, x.Name, x.Description, x.Price, x.DurationDays,
        x.StorageLimit, x.MaxUploadSize, x.MaxVideoDuration, x.MaxVideoQuality, x.MaxMembers, x.Status);

    private static void ValidatePlan(string code, string name, decimal price, int durationDays, long storageLimit,
        long maxUploadSize, int maxVideoDuration, string quality, int maxMembers, string status)
    {
        if (string.IsNullOrWhiteSpace(code) || code.Length > 50 || !code.All(c => char.IsLetterOrDigit(c) || c is '_' or '-'))
            throw new PlanException(400, "INVALID_PLAN_CODE", "Mã gói chỉ gồm chữ, số, gạch dưới hoặc gạch ngang.");
        if (string.IsNullOrWhiteSpace(name) || name.Length > 120) throw new PlanException(400, "INVALID_PLAN_NAME", "Tên gói không hợp lệ.");
        if (price < 0 || durationDays <= 0 || storageLimit <= 0 || maxUploadSize <= 0 || maxVideoDuration <= 0 || maxMembers <= 0)
            throw new PlanException(400, "INVALID_PLAN_LIMIT", "Giá và các giới hạn gói phải hợp lệ.");
        if (VideoRules.QualityHeight(quality) == 0) throw new PlanException(400, "INVALID_PLAN_QUALITY", "Chất lượng gói không hợp lệ.");
        if (status is not ("active" or "inactive" or "archived")) throw new PlanException(400, "INVALID_PLAN_STATUS", "Trạng thái gói không hợp lệ.");
    }

    private static string? Clean(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
