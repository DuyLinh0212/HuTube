using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Application.Notifications;
using HuTube.Application.Rbac;
using HuTube.Application.Plans;
using HuTube.Application.Serialization;
using HuTube.Domain.Channels;
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
    RbacService audit,
    INotificationService? notifications = null) : IPlanService
{
    private DateTimeOffset Now => clock.GetUtcNow();

    public async Task<IReadOnlyList<PlanResponse>> GetPlansAsync(CancellationToken ct = default)
    {
        var plans = await db.Plans.AsNoTracking()
            .Where(x => x.Status == "active")
            .OrderBy(x => x.DisplayOrder)
            .ThenBy(x => x.Price)
            .ToListAsync(ct);

        return plans.Select(ToResponse).ToList();
    }

    public async Task<IReadOnlyList<PlanResponse>> GetAdminPlansAsync(CancellationToken ct = default) =>
        (await db.Plans.AsNoTracking().OrderBy(x => x.DisplayOrder).ThenBy(x => x.Price).ThenBy(x => x.Code).ToListAsync(ct))
        .Select(ToResponse).ToList();

    public async Task<PlanResponse> CreatePlanAsync(Guid actorUserId, CreatePlanRequest request, CancellationToken ct = default)
    {
        ValidatePlan(request.Code, request.Name, request.Price, request.DurationDays, request.StorageLimit,
            request.MaxUploadSize, request.MaxVideoDuration, request.MaxVideoQuality, request.MaxDownloadQuality,
            request.MaxMembers, "active");
        var features = NormalizeFeatures(request.Features);
        var code = request.Code.Trim().ToLowerInvariant();
        if (await db.Plans.AnyAsync(x => x.Code == code, ct))
            throw new PlanException(409, "PLAN_CODE_EXISTS", "Mã gói đã tồn tại.");
        var now = Now;
        var plan = new Plan { PlanId = Guid.NewGuid(), Code = code, Name = request.Name.Trim(), Description = Clean(request.Description),
            Price = request.Price, DurationDays = request.DurationDays, StorageLimit = request.StorageLimit,
            MaxUploadSize = request.MaxUploadSize, MaxVideoDuration = request.MaxVideoDuration,
            MaxVideoQuality = request.MaxVideoQuality.Trim().ToLowerInvariant(), MaxDownloadQuality = NormalizeQuality(request.MaxDownloadQuality, request.MaxVideoQuality), MaxMembers = request.MaxMembers,
            Features = features, DisplayOrder = Math.Max(0, request.DisplayOrder), Status = "active", CreatedAt = now, UpdatedAt = now };
        db.Plans.Add(plan);
        await db.SaveChangesAsync(ct);
        await audit.LogAuditAsync(new AuditLogEntry(actorUserId, "plan.created", "plan", plan.PlanId, "Admin tạo gói dịch vụ",
            NewValues: PersistenceJson.Serialize(ToResponse(plan))), ct);
        return ToResponse(plan);
    }

    public async Task<PlanResponse> UpdatePlanAsync(Guid actorUserId, Guid planId, UpdatePlanRequest request, CancellationToken ct = default)
    {
        var plan = await db.Plans.SingleOrDefaultAsync(x => x.PlanId == planId, ct)
            ?? throw new PlanException(404, "PLAN_NOT_FOUND", "Gói dịch vụ không tồn tại.");
        ValidatePlan(plan.Code, request.Name, request.Price, request.DurationDays, request.StorageLimit,
            request.MaxUploadSize, request.MaxVideoDuration, request.MaxVideoQuality, request.MaxDownloadQuality,
            request.MaxMembers, request.Status);
        var features = NormalizeFeatures(request.Features ?? plan.Features);
        var old = ToResponse(plan);
        plan.Name = request.Name.Trim(); plan.Description = Clean(request.Description); plan.Price = request.Price;
        plan.DurationDays = request.DurationDays; plan.StorageLimit = request.StorageLimit; plan.MaxUploadSize = request.MaxUploadSize;
        plan.MaxVideoDuration = request.MaxVideoDuration; plan.MaxVideoQuality = request.MaxVideoQuality.Trim().ToLowerInvariant();
        plan.MaxDownloadQuality = NormalizeQuality(
            request.MaxDownloadQuality ?? plan.MaxDownloadQuality,
            request.MaxVideoQuality);
        plan.MaxMembers = request.MaxMembers; plan.Status = request.Status.Trim().ToLowerInvariant();
        plan.Features = features; plan.DisplayOrder = Math.Max(0, request.DisplayOrder); plan.UpdatedAt = Now;
        await db.SaveChangesAsync(ct);
        await audit.LogAuditAsync(new AuditLogEntry(actorUserId, "plan.updated", "plan", plan.PlanId, "Admin cập nhật gói dịch vụ",
            OldValues: PersistenceJson.Serialize(old), NewValues: PersistenceJson.Serialize(ToResponse(plan))), ct);
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

        return ToResponse(plan);
    }

    public async Task<PlanShareResponse> GetPlanShareAsync(Guid planId, CancellationToken ct = default)
    {
        var plan = await db.Plans.AsNoTracking().SingleOrDefaultAsync(x => x.PlanId == planId && x.Status == "active", ct)
            ?? throw new PlanException(404, "PLAN_NOT_FOUND", "Gói dịch vụ không tồn tại.");

        var shareUrl = $"{authOptions.WebBaseUrl.TrimEnd('/')}/plans/{plan.PlanId}";
        return new PlanShareResponse(plan.PlanId, plan.Code, plan.Name, plan.Description, shareUrl, plan.Status,
            PlanEntitlementRules.ReadFlags(plan.Features));
    }

    public async Task<PlanDetailResponse?> GetMyPlanAsync(Guid userId, CancellationToken ct = default)
    {
        var user = await db.Users.AsNoTracking().SingleAsync(x => x.UserId == userId, ct);
        // 1. Kiểm tra xem người dùng có phải là chủ sở hữu của một gói đang active không
        var ownedHistory = await (from h in db.PlanHistories.AsNoTracking()
                                  join p in db.Plans.AsNoTracking() on h.PlanId equals p.PlanId
                                  where h.UserId == userId && h.Status == "active"
                                        && (!h.OwnerUserId.HasValue || h.OwnerUserId == userId)
                                        && (!h.EndedAt.HasValue || h.EndedAt > Now)
                                  orderby h.StartedAt descending
                                  select new { History = h, Plan = p }).FirstOrDefaultAsync(ct);

        Plan? plan = null;
        PlanHistory? activeHistory = null;
        var isSharedMember = false;

        if (ownedHistory != null)
        {
            plan = ownedHistory.Plan;
            activeHistory = ownedHistory.History;
            isSharedMember = false;
        }
        else
        {
            // 2. Nếu không sở hữu gói active, kiểm tra xem có tham gia gói chia sẻ của người khác không
            var sharedPlan = await GetActiveSharedPlanAsync(userId, ct);
            if (sharedPlan != null)
            {
                plan = sharedPlan.Value.Plan;
                activeHistory = sharedPlan.Value.History;
                isSharedMember = true;
            }
            else if (user.PlanId.HasValue)
            {
                plan = await db.Plans.AsNoTracking().FirstOrDefaultAsync(x => x.PlanId == user.PlanId.Value && x.Status == "active", ct);
            }
        }

        if (plan == null) return null;

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

        List<PlanMemberResponse> members;
        if (activeHistory == null || isSharedMember)
        {
            members = [];
        }
        else
        {
            var rawMembers = await db.PlanMembers.AsNoTracking()
                .Where(x => x.PlanHistoryId == activeHistory.PlanHistoryId && x.Status != "revoked")
                .OrderBy(x => x.InvitedAt)
                .ToListAsync(ct);

            var memberUserIds = rawMembers.Where(m => m.MemberUserId.HasValue).Select(m => m.MemberUserId!.Value).Distinct().ToList();
            var memberQuotas = await (from ch in db.Channels.AsNoTracking()
                                      join q in db.ChannelQuotas.AsNoTracking() on ch.ChannelId equals q.ChannelId
                                      where memberUserIds.Contains(ch.OwnerUserId) && ch.Status == "active"
                                      select new { ch.OwnerUserId, q.StorageUsed }).ToDictionaryAsync(x => x.OwnerUserId, x => x.StorageUsed, ct);

            members = rawMembers.Select(x => new PlanMemberResponse(
                x.PlanMemberId,
                plan.PlanId,
                x.OwnerUserId,
                x.MemberEmail,
                x.MemberUserId,
                x.Status,
                x.InvitedAt,
                x.AcceptedAt,
                x.RevokedAt,
                x.AllocatedStorage,
                x.MemberUserId.HasValue && memberQuotas.TryGetValue(x.MemberUserId.Value, out var used) ? used : 0L
            )).ToList();
        }

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
                                         where h.UserId == userId && h.Status == "active" && p.Price > 0
                                               && (!h.EndedAt.HasValue || h.EndedAt > Now)
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
            activePaidPlanIds,
            PlanEntitlementRules.ReadFlags(plan.Features),
            plan.DurationDays,
            plan.MaxVideoDuration,
            plan.Description,
            plan.Status,
            plan.MaxDownloadQuality,
            activeHistory?.OwnerAllocatedStorage);
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

            // 3. Khi chuyển đổi ngang giữa các gói cùng giá, yêu cầu gói đích đã mua và còn hạn.
            // Nếu là nâng cấp lên gói giá cao hơn (plan.Price > activeSub.Plan.Price), luôn cho phép đăng ký mới.
            if (activeSub.Plan.Price > 0 && plan.Price <= activeSub.Plan.Price)
            {
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

        await SyncChannelQuotaAsync(userId, plan.StorageLimit, now, ct);

        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);
        return ToResponse(plan);
    }

    public async Task<long?> GetEffectiveStorageLimitAsync(Guid userId, CancellationToken ct = default)
    {
        var user = await db.Users.AsNoTracking().SingleAsync(x => x.UserId == userId, ct);
        if (user.PlanId.HasValue)
        {
            var plan = await GetEffectivePlanAsync(userId, user.PlanId.Value, ct);
            if (plan != null)
            {
                var history = await db.PlanHistories.AsNoTracking().FirstOrDefaultAsync(x => x.UserId == userId && x.Status == "active", ct);
                return history?.OwnerAllocatedStorage ?? plan.StorageLimit;
            }
        }

        var shared = await GetActiveSharedPlanAsync(userId, ct);
        return shared?.Member.AllocatedStorage ?? shared?.Plan.StorageLimit;
    }

    public async Task<PlanMemberResponse> InviteMemberAsync(Guid ownerUserId, string email, long? allocatedStorage, CancellationToken ct = default)
    {
        var normalizedEmail = email.Trim().ToLowerInvariant();
        if (!IsValidEmail(normalizedEmail)) throw new PlanException(400, "INVALID_EMAIL", "Email không hợp lệ.");

        var user = await db.Users.AsNoTracking().SingleAsync(x => x.UserId == ownerUserId, ct);
        if (!user.PlanId.HasValue) throw new PlanException(400, "NO_ACTIVE_PLAN", "Bạn chưa có gói dịch vụ.");

        var plan = await GetEffectivePlanAsync(ownerUserId, user.PlanId.Value, ct)
            ?? throw new PlanException(400, "PLAN_EXPIRED", "Gói dịch vụ đã hết hạn.");
        if (plan.MaxMembers <= 1) throw new PlanException(400, "PLAN_SHARE_NOT_ALLOWED", "Gói hiện tại không cho phép chia sẻ.");

        var activeHistory = await db.PlanHistories.AsNoTracking()
            .Where(x => x.UserId == ownerUserId && (!x.OwnerUserId.HasValue || x.OwnerUserId == ownerUserId) && x.PlanId == plan.PlanId
                && x.Status == "active" && (!x.EndedAt.HasValue || x.EndedAt > Now))
            .OrderByDescending(x => x.StartedAt)
            .FirstOrDefaultAsync(ct);

        if (activeHistory == null)
            throw new PlanException(403, "PLAN_OWNER_REQUIRED", "Chỉ chủ gói mới có thể mời thành viên.");

        var currentMembers = await db.PlanMembers.AsNoTracking().CountAsync(x => x.PlanHistoryId == activeHistory.PlanHistoryId && x.Status != "revoked", ct);
        if (currentMembers + 1 >= plan.MaxMembers) throw new PlanException(409, "PLAN_MEMBER_LIMIT_EXCEEDED", "Số lượng thành viên đã đạt giới hạn gói.");
        if (await db.PlanMembers.AsNoTracking().AnyAsync(x => x.PlanHistoryId == activeHistory.PlanHistoryId
                && x.MemberEmail == normalizedEmail && (x.Status == "pending" || x.Status == "accepted"), ct))
            throw new PlanException(409, "PLAN_MEMBER_ALREADY_EXISTS", "Email này đã có quyền hoặc đang chờ tham gia gói.");

        if (allocatedStorage.HasValue && allocatedStorage.Value < 0)
        {
            throw new PlanException(400, "INVALID_STORAGE_LIMIT", "Dung lượng phân bổ không được nhỏ hơn 0.");
        }

        if (allocatedStorage.HasValue)
        {
            var currentMembersAllocated = await db.PlanMembers.AsNoTracking()
                .Where(x => x.PlanHistoryId == activeHistory.PlanHistoryId && x.Status != "revoked")
                .SumAsync(x => x.AllocatedStorage ?? 0, ct);
            var totalAllocated = (activeHistory.OwnerAllocatedStorage ?? 0) + currentMembersAllocated + allocatedStorage.Value;

            if (totalAllocated > plan.StorageLimit)
            {
                throw new PlanException(400, "PLAN_STORAGE_LIMIT_EXCEEDED", "Tổng dung lượng phân bổ vượt quá dung lượng gói.");
            }
        }

        var targetUserId = await db.Users.AsNoTracking()
            .Where(x => x.Email == normalizedEmail)
            .Select(x => (Guid?)x.UserId)
            .SingleOrDefaultAsync(ct);

        var member = new PlanMember
        {
            PlanMemberId = Guid.NewGuid(),
            PlanHistoryId = activeHistory.PlanHistoryId,
            OwnerUserId = ownerUserId,
            MemberEmail = normalizedEmail,
            Status = "pending",
            InvitedAt = Now,
            AllocatedStorage = allocatedStorage
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

        await audit.LogAuditAsync(new AuditLogEntry(ownerUserId, "plan.member_invited", "plan_member", member.PlanMemberId,
            "Mời thành viên dùng chung gói", NewValues: PersistenceJson.Serialize(new { member.MemberEmail, plan.PlanId })), ct);
        if (notifications != null && targetUserId.HasValue)
        {
            try
            {
                await notifications.PublishInAppAsync(targetUserId.Value, "plan_invitation",
                    "Lời mời dùng chung gói HuTube", "Bạn có lời mời dùng chung gói. Hãy kiểm tra email để xác nhận.",
                    "/my-plan", "plan_member", member.PlanMemberId, ct);
            }
            catch
            {
                // Persisted invitation and email remain the source of truth when realtime delivery is unavailable.
            }
        }

        return new PlanMemberResponse(member.PlanMemberId, plan.PlanId, ownerUserId, member.MemberEmail, member.MemberUserId, member.Status, member.InvitedAt, member.AcceptedAt, member.RevokedAt, member.AllocatedStorage);
    }

    public async Task<PlanMemberResponse> AcceptInvitationAsync(Guid userId, Guid memberId, string token, CancellationToken ct = default)
    {
        var member = await db.PlanMembers.SingleOrDefaultAsync(x => x.PlanMemberId == memberId, ct)
            ?? throw new PlanException(404, "INVITATION_NOT_FOUND", "Lời mời không tồn tại.");

        var invitationToken = await db.PlanInvitationTokens.SingleOrDefaultAsync(x => x.PlanMemberId == memberId && x.Token == token, ct)
            ?? throw new PlanException(400, "INVALID_TOKEN", "Token không hợp lệ.");

        if (invitationToken.ExpiresAt <= Now) throw new PlanException(410, "INVITATION_EXPIRED", "Lời mời đã hết hạn.");
        if (member.Status != "pending") throw new PlanException(409, "INVITATION_ALREADY_PROCESSED", "Lời mời đã được xử lý.");

        var user = await db.Users.SingleAsync(x => x.UserId == userId, ct);
        if (!string.Equals(user.Email, member.MemberEmail, StringComparison.OrdinalIgnoreCase))
            throw new PlanException(403, "EMAIL_MISMATCH", "Email xác nhận không khớp với lời mời.");

        var activeHistory = await db.PlanHistories.AsNoTracking()
            .SingleOrDefaultAsync(x => x.PlanHistoryId == member.PlanHistoryId
                && x.Status == "active" && (!x.EndedAt.HasValue || x.EndedAt > Now), ct)
            ?? throw new PlanException(410, "PLAN_EXPIRED", "Gói của chủ sở hữu đã hết hạn.");
        var sharedPlan = await db.Plans.AsNoTracking()
            .SingleOrDefaultAsync(x => x.PlanId == activeHistory.PlanId && x.Status == "active", ct)
            ?? throw new PlanException(410, "PLAN_EXPIRED", "Gói của chủ sở hữu không còn hoạt động.");

        member.MemberUserId = userId;
        member.Status = "accepted";
        member.AcceptedAt = Now;
        invitationToken.UsedAt = Now;
        if (!user.PlanId.HasValue)
        {
            user.PlanId = activeHistory.PlanId;
            var effectiveQuota = member.AllocatedStorage ?? sharedPlan.StorageLimit;
            await SyncChannelQuotaAsync(userId, effectiveQuota, Now, ct);
        }

        await db.SaveChangesAsync(ct);

        var planId = await db.PlanHistories.AsNoTracking()
            .Where(y => y.PlanHistoryId == member.PlanHistoryId)
            .Select(y => y.PlanId)
            .SingleAsync(ct);

        var plan = await db.Plans.AsNoTracking().SingleOrDefaultAsync(x => x.PlanId == planId, ct);
        return new PlanMemberResponse(member.PlanMemberId, plan?.PlanId ?? Guid.Empty, member.OwnerUserId, member.MemberEmail, member.MemberUserId, member.Status, member.InvitedAt, member.AcceptedAt, member.RevokedAt, member.AllocatedStorage);
    }

    public async Task RemoveMemberAsync(Guid ownerUserId, Guid memberId, CancellationToken ct = default)
    {
        var member = await db.PlanMembers.SingleOrDefaultAsync(x => x.PlanMemberId == memberId && x.OwnerUserId == ownerUserId, ct)
            ?? throw new PlanException(404, "PLAN_MEMBER_NOT_FOUND", "Thành viên không tồn tại hoặc không thuộc quyền quản lý của bạn.");

        member.Status = "revoked";
        member.RevokedAt = Now;
        var historyPlanId = await db.PlanHistories.AsNoTracking()
            .Where(x => x.PlanHistoryId == member.PlanHistoryId)
            .Select(x => x.PlanId)
            .SingleOrDefaultAsync(ct);
        if (member.MemberUserId.HasValue)
        {
            var memberUser = await db.Users.SingleOrDefaultAsync(x => x.UserId == member.MemberUserId.Value, ct);
            if (memberUser?.PlanId == historyPlanId
                && !await db.PlanHistories.AnyAsync(x => x.UserId == memberUser.UserId && x.Status == "active" && (!x.EndedAt.HasValue || x.EndedAt > Now), ct))
            {
                memberUser.PlanId = null;
                await SyncChannelQuotaAsync(memberUser.UserId, ChannelQuotaRules.DefaultStorageLimit, Now, ct);
            }
        }
        await db.SaveChangesAsync(ct);
        await audit.LogAuditAsync(new AuditLogEntry(ownerUserId, "plan.member_revoked", "plan_member", member.PlanMemberId,
            "Thu hồi quyền dùng chung gói"), ct);
    }

    private async Task<Plan?> GetEffectivePlanAsync(Guid userId, Guid planId, CancellationToken ct)
    {
        var plan = await db.Plans.AsNoTracking().SingleOrDefaultAsync(x => x.PlanId == planId && x.Status == "active", ct);
        if (plan == null) return null;
        var now = Now;
        var hasSubscription = await db.PlanHistories.AsNoTracking().AnyAsync(x =>
            x.UserId == userId && x.PlanId == planId && x.Status == "active" && (!x.EndedAt.HasValue || x.EndedAt > now), ct)
            || await (from member in db.PlanMembers.AsNoTracking()
                      join history in db.PlanHistories.AsNoTracking() on member.PlanHistoryId equals history.PlanHistoryId
                      where member.MemberUserId == userId && member.Status == "accepted" && history.PlanId == planId
                            && history.Status == "active" && (!history.EndedAt.HasValue || history.EndedAt > now)
                      select member.PlanMemberId).AnyAsync(ct);
        return hasSubscription ? plan : null;
    }

    private async Task<(Plan Plan, PlanHistory History, PlanMember Member)?> GetActiveSharedPlanAsync(Guid userId, CancellationToken ct)
    {
        var result = await (from member in db.PlanMembers.AsNoTracking()
                             join history in db.PlanHistories.AsNoTracking() on member.PlanHistoryId equals history.PlanHistoryId
                             join plan in db.Plans.AsNoTracking() on history.PlanId equals plan.PlanId
                             where member.MemberUserId == userId && member.Status == "accepted"
                                   && history.Status == "active" && (!history.EndedAt.HasValue || history.EndedAt > Now)
                                   && plan.Status == "active"
                             orderby history.EndedAt descending
                             select new { Plan = plan, History = history, Member = member }).FirstOrDefaultAsync(ct);
        return result == null ? null : (result.Plan, result.History, result.Member);
    }

    private static PlanResponse ToResponse(Plan x) => new(x.PlanId, x.Code, x.Name, x.Description, x.Price, x.DurationDays,
        x.StorageLimit, x.MaxUploadSize, x.MaxVideoDuration, x.MaxVideoQuality, x.MaxMembers, x.Status,
        PlanEntitlementRules.ReadFlags(x.Features), x.DisplayOrder, x.MaxDownloadQuality);

    private static void ValidatePlan(string code, string name, decimal price, int durationDays, long storageLimit,
        long maxUploadSize, int maxVideoDuration, string quality, string? downloadQuality, int maxMembers, string status)
    {
        if (string.IsNullOrWhiteSpace(code) || code.Length > 50 || !code.All(c => char.IsLetterOrDigit(c) || c is '_' or '-'))
            throw new PlanException(400, "INVALID_PLAN_CODE", "Mã gói chỉ gồm chữ, số, gạch dưới hoặc gạch ngang.");
        if (string.IsNullOrWhiteSpace(name) || name.Length > 120) throw new PlanException(400, "INVALID_PLAN_NAME", "Tên gói không hợp lệ.");
        if (price < 0 || durationDays <= 0 || storageLimit <= 0 || maxUploadSize <= 0 || maxVideoDuration <= 0 || maxMembers <= 0)
            throw new PlanException(400, "INVALID_PLAN_LIMIT", "Giá và các giới hạn gói phải hợp lệ.");
        if (VideoRules.QualityHeight(quality) == 0) throw new PlanException(400, "INVALID_PLAN_QUALITY", "Chất lượng gói không hợp lệ.");
        if (VideoRules.QualityHeight(NormalizeQuality(downloadQuality, quality)) == 0) throw new PlanException(400, "INVALID_PLAN_DOWNLOAD_QUALITY", "Chất lượng tải xuống của gói không hợp lệ.");
        if (status is not ("active" or "inactive" or "archived")) throw new PlanException(400, "INVALID_PLAN_STATUS", "Trạng thái gói không hợp lệ.");
    }

    private static string NormalizeQuality(string? value, string fallback) =>
        string.IsNullOrWhiteSpace(value) ? fallback.Trim().ToLowerInvariant() : value.Trim().ToLowerInvariant();

    private static string NormalizeFeatures(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return "{}";
        try
        {
            using var document = JsonDocument.Parse(value);
            if (document.RootElement.ValueKind != JsonValueKind.Object)
                throw new PlanException(400, "INVALID_PLAN_FEATURES", "Quyền lợi gói phải là một JSON object.");
            return value.Trim();
        }
        catch (JsonException)
        {
            throw new PlanException(400, "INVALID_PLAN_FEATURES", "Quyền lợi gói không phải JSON hợp lệ.");
        }
    }

    private async Task<long> GetUsedStorageAsync(Guid userId, CancellationToken ct)
    {
        var channelId = await db.Channels.AsNoTracking()
            .Where(x => x.OwnerUserId == userId && x.Status == "active")
            .Select(x => (Guid?)x.ChannelId)
            .SingleOrDefaultAsync(ct);

        if (!channelId.HasValue) return 0L;

        return await db.ChannelQuotas.AsNoTracking()
            .Where(x => x.ChannelId == channelId.Value)
            .Select(x => x.StorageUsed)
            .SingleOrDefaultAsync(ct);
    }

    private async Task SyncChannelQuotaAsync(Guid userId, long storageLimit, DateTimeOffset now, CancellationToken ct)
    {
        var channelId = await db.Channels.AsNoTracking()
            .Where(x => x.OwnerUserId == userId && x.Status == "active")
            .Select(x => x.ChannelId)
            .SingleOrDefaultAsync(ct);
        if (channelId == Guid.Empty) return;
        var quota = await db.ChannelQuotas.SingleOrDefaultAsync(x => x.ChannelId == channelId, ct);
        if (quota == null)
        {
            db.ChannelQuotas.Add(new ChannelQuota { ChannelId = channelId, StorageLimit = storageLimit, UpdatedAt = now });
            return;
        }
        quota.StorageLimit = storageLimit;
        quota.UpdatedAt = now;
    }

    public async Task<PlanMemberResponse> UpdateMemberStorageAsync(Guid ownerUserId, Guid memberId, long? allocatedStorage, CancellationToken ct = default)
    {
        var member = await db.PlanMembers.FirstOrDefaultAsync(x => x.PlanMemberId == memberId && x.OwnerUserId == ownerUserId && x.Status != "revoked", ct);
        if (member == null) throw new PlanException(404, "MEMBER_NOT_FOUND", "Không tìm thấy thành viên.");

        var history = await db.PlanHistories.AsNoTracking().FirstOrDefaultAsync(x => x.PlanHistoryId == member.PlanHistoryId, ct);
        if (history == null || history.Status != "active" || (history.EndedAt.HasValue && history.EndedAt <= Now))
            throw new PlanException(400, "PLAN_EXPIRED", "Gói dịch vụ đã hết hạn hoặc không hoạt động.");

        var plan = await db.Plans.AsNoTracking().FirstOrDefaultAsync(x => x.PlanId == history.PlanId, ct);
        if (plan == null) throw new PlanException(404, "PLAN_NOT_FOUND", "Không tìm thấy gói.");

        if (allocatedStorage.HasValue && allocatedStorage.Value < 0)
            throw new PlanException(400, "INVALID_STORAGE_LIMIT", "Dung lượng phân bổ không được nhỏ hơn 0.");

        if (allocatedStorage.HasValue)
        {
            var usedStorage = member.MemberUserId.HasValue
                ? await GetUsedStorageAsync(member.MemberUserId.Value, ct)
                : 0L;
            if (allocatedStorage.Value < usedStorage)
                throw new PlanException(400, "STORAGE_LIMIT_TOO_LOW", "Dung lượng phân bổ không được nhỏ hơn dung lượng thành viên đã sử dụng.");

            var currentMembersAllocated = await db.PlanMembers.AsNoTracking()
                .Where(x => x.PlanHistoryId == history.PlanHistoryId && x.Status != "revoked" && x.PlanMemberId != memberId)
                .SumAsync(x => x.AllocatedStorage ?? 0, ct);

            var totalAllocated = (history.OwnerAllocatedStorage ?? 0) + currentMembersAllocated + allocatedStorage.Value;
            if (totalAllocated > plan.StorageLimit)
                throw new PlanException(400, "PLAN_STORAGE_LIMIT_EXCEEDED", "Tổng dung lượng phân bổ vượt quá dung lượng gói.");
        }

        member.AllocatedStorage = allocatedStorage;
        await db.SaveChangesAsync(ct);
        await audit.LogAuditAsync(new AuditLogEntry(ownerUserId, "plan.member_storage_updated", "plan_member", member.PlanMemberId,
            "Cập nhật dung lượng thành viên", NewValues: PersistenceJson.Serialize(new { allocatedStorage })), ct);

        // Sync channel quota directly if member is accepted
        if (member.Status == "accepted" && member.MemberUserId.HasValue)
        {
            var effectiveQuota = allocatedStorage ?? plan.StorageLimit;
            await SyncChannelQuotaAsync(member.MemberUserId.Value, effectiveQuota, Now, ct);
            await db.SaveChangesAsync(ct);
        }

        return new PlanMemberResponse(member.PlanMemberId, plan.PlanId, ownerUserId, member.MemberEmail, member.MemberUserId, member.Status, member.InvitedAt, member.AcceptedAt, member.RevokedAt, member.AllocatedStorage);
    }

    public async Task UpdateOwnerStorageAsync(Guid ownerUserId, long? allocatedStorage, CancellationToken ct = default)
    {
        var history = await db.PlanHistories.FirstOrDefaultAsync(x => x.UserId == ownerUserId && x.Status == "active" && (!x.EndedAt.HasValue || x.EndedAt > Now), ct);
        if (history == null) throw new PlanException(400, "NO_ACTIVE_PLAN", "Bạn không có gói đang hoạt động.");

        var plan = await db.Plans.AsNoTracking().FirstOrDefaultAsync(x => x.PlanId == history.PlanId, ct);
        if (plan == null) throw new PlanException(404, "PLAN_NOT_FOUND", "Không tìm thấy gói.");

        if (allocatedStorage.HasValue && allocatedStorage.Value < 0)
            throw new PlanException(400, "INVALID_STORAGE_LIMIT", "Dung lượng phân bổ không được nhỏ hơn 0.");

        if (allocatedStorage.HasValue)
        {
            var usedStorage = await GetUsedStorageAsync(ownerUserId, ct);
            if (allocatedStorage.Value < usedStorage)
                throw new PlanException(400, "STORAGE_LIMIT_TOO_LOW", "Dung lượng phân bổ không được nhỏ hơn dung lượng đã sử dụng.");

            var currentMembersAllocated = await db.PlanMembers.AsNoTracking()
                .Where(x => x.PlanHistoryId == history.PlanHistoryId && x.Status != "revoked")
                .SumAsync(x => x.AllocatedStorage ?? 0, ct);

            var totalAllocated = allocatedStorage.Value + currentMembersAllocated;
            if (totalAllocated > plan.StorageLimit)
                throw new PlanException(400, "PLAN_STORAGE_LIMIT_EXCEEDED", "Tổng dung lượng phân bổ vượt quá dung lượng gói.");
        }

        history.OwnerAllocatedStorage = allocatedStorage;
        await db.SaveChangesAsync(ct);
        await audit.LogAuditAsync(new AuditLogEntry(ownerUserId, "plan.owner_storage_updated", "plan_history", history.PlanHistoryId,
            "Cập nhật dung lượng chủ gói", NewValues: PersistenceJson.Serialize(new { allocatedStorage })), ct);

        // Sync channel quota for owner
        var effectiveQuota = allocatedStorage ?? plan.StorageLimit;
        await SyncChannelQuotaAsync(ownerUserId, effectiveQuota, Now, ct);
        await db.SaveChangesAsync(ct);
    }

    private static bool IsValidEmail(string value) =>
        value.Length is > 3 and <= 254 && !value.Any(char.IsWhiteSpace)
        && value.Count(character => character == '@') == 1
        && value.IndexOf('@') > 0
        && value.LastIndexOf('.') > value.IndexOf('@') + 1
        && !value.EndsWith(".", StringComparison.Ordinal);

    private static string? Clean(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
