using HuTube.Application.Plans;
using HuTube.Application.Rbac;
using HuTube.Application.Serialization;
using HuTube.Domain.Channels;
using HuTube.Domain.Plans;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Plans;

public sealed class AdminSubscriptionService(HuTubeDbContext db, TimeProvider clock, RbacService audit)
{
    private DateTimeOffset Now => clock.GetUtcNow();

    public async Task<AdminSubscriptionPageResponse> GetSubscriptionsAsync(
        string? search, string? status, Guid? planId, string? cycle, bool? autoRenew,
        DateTimeOffset? fromDate, DateTimeOffset? toDate, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var now = Now;
        var histories = FilterQuery(search, status, planId, cycle, autoRenew, fromDate, toDate, now);

        var total = await histories.CountAsync(ct);
        var rows = await CreateSubscriptionRowsQuery(histories)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(ct);

        var paymentsByHistory = await GetLatestPaymentsAsync(rows, ct);
        var overQuotaUsers = await GetOverQuotaUserIdsAsync(rows, ct);
        var items = rows.Select(row => ToResponse(row, paymentsByHistory.GetValueOrDefault(row.PlanHistoryId), overQuotaUsers.Contains(row.UserId))).ToList();
        return new AdminSubscriptionPageResponse(items, page, pageSize, total, page * pageSize < total, await GetStatsAsync(now, ct));
    }

    public async Task<IReadOnlyList<AdminSubscriptionItemResponse>> GetSubscriptionsExportAsync(
        string? search, string? status, Guid? planId, string? cycle, bool? autoRenew,
        DateTimeOffset? fromDate, DateTimeOffset? toDate, CancellationToken ct)
    {
        var histories = FilterQuery(search, status, planId, cycle, autoRenew, fromDate, toDate, Now);
        var rows = await CreateSubscriptionRowsQuery(histories).ToListAsync(ct);
        var payments = await GetLatestPaymentsAsync(rows, ct);
        var overQuotaUsers = await GetOverQuotaUserIdsAsync(rows, ct);
        return rows.Select(row => ToResponse(row, payments.GetValueOrDefault(row.PlanHistoryId), overQuotaUsers.Contains(row.UserId))).ToList();
    }

    public async Task<AdminSubscriptionDetailResponse> GetSubscriptionAsync(Guid historyId, CancellationToken ct)
    {
        var row = await CreateSubscriptionRowsQuery(CreateHistoryQuery().Where(item => item.PlanHistoryId == historyId))
            .SingleOrDefaultAsync(ct)
            ?? throw new PlanException(404, "SUBSCRIPTION_NOT_FOUND", "Không tìm thấy thuê bao.");

        var paymentsQuery = db.Payments.AsNoTracking().Where(payment => payment.PlanHistoryId == historyId);
        if (Guid.TryParse(row.PaymentReference, out var paymentId))
            paymentsQuery = paymentsQuery.Union(db.Payments.AsNoTracking().Where(payment => payment.PaymentId == paymentId));

        var payments = await (from payment in paymentsQuery
                              join plan in db.Plans.AsNoTracking() on payment.PlanId equals plan.PlanId
                              orderby payment.CreatedAt descending
                              select new AdminSubscriptionPaymentResponse(
                                  payment.PaymentId, payment.PlanId, plan.Name, payment.TransactionCode,
                                  payment.Amount, payment.Currency, payment.Status, payment.CreatedAt, payment.PaidAt))
            .Take(50).ToListAsync(ct);
        var latest = payments.FirstOrDefault();
        var overQuotaUsers = await GetOverQuotaUserIdsAsync([row], ct);
        return new AdminSubscriptionDetailResponse(ToResponse(row, latest == null ? null : new LatestPayment(latest.PaidAt, latest.Amount, latest.Status), overQuotaUsers.Contains(row.UserId)), payments);
    }

    public async Task<AdminSubscriptionItemResponse> SetAutoRenewAsync(Guid actorId, Guid historyId, AdminSubscriptionAutoRenewRequest request, CancellationToken ct)
    {
        var history = await db.PlanHistories.SingleOrDefaultAsync(item => item.PlanHistoryId == historyId, ct)
            ?? throw new PlanException(404, "SUBSCRIPTION_NOT_FOUND", "Không tìm thấy thuê bao.");
        var now = Now;
        if (history.Status != "active" || (history.EndedAt.HasValue && history.EndedAt <= now))
            throw new PlanException(400, "SUBSCRIPTION_NOT_ACTIVE", "Chỉ có thể thay đổi gia hạn tự động của thuê bao đang hoạt động.");

        var previous = history.AutoRenew;
        history.AutoRenew = request.AutoRenew;
        await db.SaveChangesAsync(ct);
        await audit.LogAuditAsync(new AuditLogEntry(actorId, "admin.subscription.auto_renew_changed", "plan_history", historyId,
            request.AutoRenew ? "Bật gia hạn tự động" : "Tắt gia hạn tự động",
            OldValues: PersistenceJson.Serialize(new { autoRenew = previous }),
            NewValues: PersistenceJson.Serialize(new { autoRenew = request.AutoRenew })), ct);
        return await GetSubscriptionItemAsync(historyId, ct);
    }

    public async Task<AdminSubscriptionItemResponse> ExtendAsync(Guid actorId, Guid historyId, CancellationToken ct)
    {
        var history = await db.PlanHistories.SingleOrDefaultAsync(item => item.PlanHistoryId == historyId, ct)
            ?? throw new PlanException(404, "SUBSCRIPTION_NOT_FOUND", "Không tìm thấy thuê bao.");
        var plan = await db.Plans.SingleOrDefaultAsync(item => item.PlanId == history.PlanId, ct)
            ?? throw new PlanException(404, "PLAN_NOT_FOUND", "Không tìm thấy gói dịch vụ.");
        var now = Now;
        if (history.EndedAt == null)
            throw new PlanException(400, "SUBSCRIPTION_NO_EXPIRY", "Thuê bao không có ngày hết hạn để gia hạn.");

        if (history.Status == "active" && history.EndedAt > now)
        {
            var oldEnd = history.EndedAt;
            history.EndedAt = oldEnd.Value.AddDays(plan.DurationDays);
            await db.SaveChangesAsync(ct);
            await audit.LogAuditAsync(new AuditLogEntry(actorId, "admin.subscription.extended", "plan_history", historyId,
                "Admin gia hạn thủ công thuê bao", OldValues: PersistenceJson.Serialize(new { endedAt = oldEnd }),
                NewValues: PersistenceJson.Serialize(new { endedAt = history.EndedAt, addedDays = plan.DurationDays })), ct);
            return await GetSubscriptionItemAsync(historyId, ct);
        }

        if (await db.PlanHistories.AnyAsync(item => item.UserId == history.UserId && item.Status == "active"
            && (!item.EndedAt.HasValue || item.EndedAt > now), ct))
            throw new PlanException(409, "ACTIVE_SUBSCRIPTION_EXISTS", "Người dùng đã có một thuê bao đang hoạt động.");

        history.Status = "expired";
        var renewed = new PlanHistory
        {
            PlanHistoryId = Guid.NewGuid(), UserId = history.UserId, OwnerUserId = history.UserId, PlanId = plan.PlanId,
            Status = "active", StartedAt = now, EndedAt = now.AddDays(plan.DurationDays), AutoRenew = false, CreatedAt = now
        };
        db.PlanHistories.Add(renewed);
        var user = await db.Users.SingleAsync(item => item.UserId == history.UserId, ct);
        user.PlanId = plan.PlanId;
        user.UpdatedAt = now;
        await db.SaveChangesAsync(ct);
        await audit.LogAuditAsync(new AuditLogEntry(actorId, "admin.subscription.extended", "plan_history", renewed.PlanHistoryId,
            "Admin gia hạn thủ công thuê bao đã hết hạn", NewValues: PersistenceJson.Serialize(new { previousHistoryId = historyId, planId = plan.PlanId, renewed.EndedAt })), ct);
        return await GetSubscriptionItemAsync(renewed.PlanHistoryId, ct);
    }

    public async Task<AdminSubscriptionItemResponse> SwitchPlanAsync(Guid actorId, Guid historyId, AdminSubscriptionSwitchPlanRequest request, CancellationToken ct)
    {
        var now = Now;
        var history = await db.PlanHistories.SingleOrDefaultAsync(item => item.PlanHistoryId == historyId, ct)
            ?? throw new PlanException(404, "SUBSCRIPTION_NOT_FOUND", "Không tìm thấy thuê bao.");
        if (history.Status != "active" || (history.EndedAt.HasValue && history.EndedAt <= now))
            throw new PlanException(400, "SUBSCRIPTION_NOT_ACTIVE", "Chỉ có thể chuyển gói của thuê bao đang hoạt động.");
        if (history.PlanId == request.PlanId)
            throw new PlanException(400, "SAME_PLAN", "Thuê bao hiện đang sử dụng gói này.");
        var currentActiveHistoryIds = await db.PlanHistories.AsNoTracking()
            .Where(item => item.UserId == history.UserId && item.Status == "active")
            .Select(item => item.PlanHistoryId).ToArrayAsync(ct);
        if (await db.PlanMembers.AnyAsync(member => currentActiveHistoryIds.Contains(member.PlanHistoryId) && member.Status != "revoked", ct))
            throw new PlanException(409, "SHARED_PLAN_CANNOT_SWITCH", "Hãy xử lý thành viên dùng chung trước khi chuyển gói.");

        var plan = await db.Plans.SingleOrDefaultAsync(item => item.PlanId == request.PlanId && item.Status == "active", ct)
            ?? throw new PlanException(404, "PLAN_NOT_FOUND", "Không tìm thấy gói đang hoạt động.");
        var channel = await db.Channels.AsNoTracking().Where(item => item.OwnerUserId == history.UserId && item.Status == "active")
            .Select(item => new { item.ChannelId, item.Status }).SingleOrDefaultAsync(ct);
        var quota = channel == null ? null : await db.ChannelQuotas.SingleOrDefaultAsync(item => item.ChannelId == channel.ChannelId, ct);
        if (quota != null && quota.StorageUsed > plan.StorageLimit)
            throw new PlanException(400, "PLAN_STORAGE_LIMIT_TOO_LOW", "Dung lượng đã dùng vượt giới hạn của gói đích.");

        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        var activeHistories = await db.PlanHistories.Where(item => item.UserId == history.UserId && item.Status == "active").ToListAsync(ct);
        foreach (var activeHistory in activeHistories)
        {
            activeHistory.Status = "expired";
            activeHistory.EndedAt = now;
        }
        var switched = new PlanHistory
        {
            PlanHistoryId = Guid.NewGuid(), UserId = history.UserId, OwnerUserId = history.UserId, PlanId = plan.PlanId,
            Status = "active", StartedAt = now, EndedAt = now.AddDays(plan.DurationDays), AutoRenew = false, CreatedAt = now
        };
        db.PlanHistories.Add(switched);
        var user = await db.Users.SingleAsync(item => item.UserId == history.UserId, ct);
        user.PlanId = plan.PlanId;
        user.UpdatedAt = now;
        if (channel != null)
        {
            if (quota == null)
                db.ChannelQuotas.Add(new ChannelQuota { ChannelId = channel.ChannelId, StorageLimit = plan.StorageLimit, UpdatedAt = now });
            else
            {
                quota.StorageLimit = plan.StorageLimit;
                quota.UpdatedAt = now;
            }
        }
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);
        await audit.LogAuditAsync(new AuditLogEntry(actorId, "admin.subscription.plan_changed", "plan_history", switched.PlanHistoryId,
            "Admin chuyển gói thuê bao ngay lập tức", OldValues: PersistenceJson.Serialize(new { historyId, planId = history.PlanId }),
            NewValues: PersistenceJson.Serialize(new { historyId = switched.PlanHistoryId, planId = plan.PlanId, plan.Code, plan.Name })), ct);
        return await GetSubscriptionItemAsync(switched.PlanHistoryId, ct);
    }

    private async Task<AdminSubscriptionItemResponse> GetSubscriptionItemAsync(Guid historyId, CancellationToken ct)
    {
        var detail = await GetSubscriptionAsync(historyId, ct);
        return detail.Subscription;
    }

    private IQueryable<PlanHistory> CreateHistoryQuery() => db.PlanHistories.AsNoTracking()
        .Where(history => !history.OwnerUserId.HasValue || history.OwnerUserId == history.UserId)
        // Preserve the inner-join behavior of the previous list query, including global filters.
        .Where(history => db.Users.Any(user => user.UserId == history.UserId))
        .Where(history => db.Plans.Any(plan => plan.PlanId == history.PlanId));

    private IQueryable<SubscriptionRow> CreateSubscriptionRowsQuery(IQueryable<PlanHistory> histories)
    {
        var joined =
            from history in histories
            join user in db.Users.AsNoTracking() on history.UserId equals user.UserId
            join plan in db.Plans.AsNoTracking() on history.PlanId equals plan.PlanId
            select new { History = history, User = user, Plan = plan };

        return joined
            .OrderByDescending(row => row.History.StartedAt)
            .ThenBy(row => row.User.DisplayName)
            .Select(row => new SubscriptionRow(
                row.History.PlanHistoryId, row.User.UserId, row.User.DisplayName, row.User.Email, row.User.AvatarUrl,
                row.Plan.PlanId, row.Plan.Code, row.Plan.Name, row.Plan.Price, row.Plan.DurationDays,
                row.History.Status, row.History.StartedAt, row.History.EndedAt, row.History.AutoRenew,
                row.History.PaymentReference));
    }

    private IQueryable<PlanHistory> FilterQuery(
        string? search, string? status, Guid? planId, string? cycle, bool? autoRenew,
        DateTimeOffset? fromDate, DateTimeOffset? toDate, DateTimeOffset now)
    {
        var query = CreateHistoryQuery();
        var fromUtc = fromDate?.ToUniversalTime();
        var toExclusiveUtc = toDate?.ToUniversalTime().AddDays(1);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var term = search.Trim();
            if (term.StartsWith("SUB-", StringComparison.OrdinalIgnoreCase)) term = term[4..];
            query = query.Where(history => EF.Functions.ILike(history.PlanHistoryId.ToString(), $"%{term}%")
                || db.Users.Any(user => user.UserId == history.UserId
                    && (EF.Functions.ILike(user.DisplayName, $"%{term}%")
                        || EF.Functions.ILike(user.Email, $"%{term}%")
                        || EF.Functions.ILike(user.Username, $"%{term}%"))));
        }

        if (planId.HasValue) query = query.Where(history => history.PlanId == planId.Value);
        if (autoRenew.HasValue) query = query.Where(history => history.AutoRenew == autoRenew.Value);
        if (fromUtc.HasValue) query = query.Where(history => history.StartedAt >= fromUtc.Value);
        if (toExclusiveUtc.HasValue) query = query.Where(history => history.StartedAt < toExclusiveUtc.Value);

        var normalizedCycle = cycle?.Trim().ToLowerInvariant();
        if (normalizedCycle == "monthly") query = query.Where(history => db.Plans.Any(plan => plan.PlanId == history.PlanId && plan.DurationDays <= 35));
        else if (normalizedCycle == "yearly") query = query.Where(history => db.Plans.Any(plan => plan.PlanId == history.PlanId && plan.DurationDays >= 360));
        else if (normalizedCycle == "custom") query = query.Where(history => db.Plans.Any(plan => plan.PlanId == history.PlanId && plan.DurationDays > 35 && plan.DurationDays < 360));

        var normalizedStatus = status?.Trim().ToLowerInvariant();
        if (normalizedStatus == "active") query = query.Where(history => history.Status == "active" && (!history.EndedAt.HasValue || history.EndedAt > now.AddDays(7)));
        else if (normalizedStatus == "expiring") query = query.Where(history => history.Status == "active" && history.EndedAt.HasValue && history.EndedAt > now && history.EndedAt <= now.AddDays(7));
        else if (normalizedStatus == "expired") query = query.Where(history => history.Status != "active" || (history.EndedAt.HasValue && history.EndedAt <= now));
        else if (!string.IsNullOrWhiteSpace(normalizedStatus) && normalizedStatus != "all") query = query.Where(history => history.Status == normalizedStatus);
        return query;
    }

    private async Task<Dictionary<Guid, LatestPayment>> GetLatestPaymentsAsync(IReadOnlyCollection<SubscriptionRow> rows, CancellationToken ct)
    {
        if (rows.Count == 0) return [];
        var historyIds = rows.Select(row => row.PlanHistoryId).ToArray();
        var paymentIds = rows.Select(row => Guid.TryParse(row.PaymentReference, out var id) ? (Guid?)id : null)
            .Where(id => id.HasValue).Select(id => id!.Value).ToArray();
        var payments = await db.Payments.AsNoTracking()
            .Where(payment => (payment.PlanHistoryId.HasValue && historyIds.Contains(payment.PlanHistoryId.Value))
                || paymentIds.Contains(payment.PaymentId))
            .OrderByDescending(payment => payment.PaidAt ?? payment.CreatedAt)
            .Select(payment => new { payment.PaymentId, payment.PlanHistoryId, payment.Amount, payment.Status, payment.PaidAt, payment.CreatedAt })
            .ToListAsync(ct);

        var paymentIdByHistory = rows.Where(row => Guid.TryParse(row.PaymentReference, out _))
            .ToDictionary(row => row.PlanHistoryId, row => Guid.Parse(row.PaymentReference!));
        return rows.Select(row =>
            {
                var latest = payments.FirstOrDefault(payment => payment.PlanHistoryId == row.PlanHistoryId
                    || (paymentIdByHistory.TryGetValue(row.PlanHistoryId, out var paymentId) && payment.PaymentId == paymentId));
                return latest == null ? (row.PlanHistoryId, (LatestPayment?)null)
                    : (row.PlanHistoryId, new LatestPayment(latest.PaidAt ?? latest.CreatedAt, latest.Amount, latest.Status));
            })
            .Where(entry => entry.Item2 != null)
            .ToDictionary(entry => entry.PlanHistoryId, entry => entry.Item2!);
    }

    private async Task<AdminSubscriptionStatsResponse> GetStatsAsync(DateTimeOffset now, CancellationToken ct)
    {
        var histories = CreateHistoryQuery();
        var active = histories.Where(history => history.Status == "active" && (!history.EndedAt.HasValue || history.EndedAt > now));
        var activeRows = await active.Select(history => new { history.EndedAt, history.AutoRenew }).ToListAsync(ct);
        var monthStart = new DateTimeOffset(now.Year, now.Month, 1, 0, 0, 0, TimeSpan.Zero);
        var paidThisMonth = db.Payments.AsNoTracking().Where(payment => payment.Status == "paid" && payment.PaidAt >= monthStart && payment.PaidAt < monthStart.AddMonths(1));
        return new AdminSubscriptionStatsResponse(
            await histories.CountAsync(ct),
            activeRows.Count(row => !row.EndedAt.HasValue || row.EndedAt > now.AddDays(7)),
            activeRows.Count(row => row.EndedAt.HasValue && row.EndedAt <= now.AddDays(7)),
            await histories.CountAsync(history => history.Status != "active" || (history.EndedAt.HasValue && history.EndedAt <= now), ct),
            activeRows.Count(row => row.AutoRenew),
            await db.Payments.AsNoTracking().CountAsync(payment => payment.Status == "pending", ct),
            await paidThisMonth.SumAsync(payment => (decimal?)payment.Amount, ct) ?? 0,
            await paidThisMonth.CountAsync(ct),
            await db.Payments.AsNoTracking().CountAsync(payment => payment.Status == "failed", ct),
            await histories.CountAsync(history => history.CreatedAt >= monthStart && history.CreatedAt < monthStart.AddMonths(1), ct));
    }

    private async Task<HashSet<Guid>> GetOverQuotaUserIdsAsync(IReadOnlyCollection<SubscriptionRow> rows, CancellationToken ct)
    {
        var userIds = rows.Select(row => row.UserId).Distinct().ToArray();
        if (userIds.Length == 0) return [];

        return (await (from channel in db.Channels.AsNoTracking()
                       join quota in db.ChannelQuotas.AsNoTracking() on channel.ChannelId equals quota.ChannelId
                       where userIds.Contains(channel.OwnerUserId) && channel.Status == "active"
                           && quota.StorageUsed > quota.StorageLimit
                       select channel.OwnerUserId).Distinct().ToListAsync(ct)).ToHashSet();
    }

    private AdminSubscriptionItemResponse ToResponse(SubscriptionRow row, LatestPayment? payment, bool isStorageOverLimit)
    {
        var status = row.Status;
        if (status == "active" && row.ExpiresAt.HasValue)
        {
            var now = Now;
            status = row.ExpiresAt <= now ? "expired" : row.ExpiresAt <= now.AddDays(7) ? "expiring" : "active";
        }
        else if (status == "active") status = "active";
        var cycle = row.DurationDays >= 360 ? "yearly" : row.DurationDays <= 35 ? "monthly" : "custom";
        return new AdminSubscriptionItemResponse(row.PlanHistoryId, row.UserId, row.UserName, row.Email, row.AvatarUrl,
            row.PlanId, row.PlanCode, row.PlanName, row.Price, row.DurationDays, cycle, status, row.StartedAt, row.ExpiresAt,
            row.AutoRenew, payment?.At, payment?.Amount, payment?.Status, isStorageOverLimit);
    }

    private sealed record SubscriptionRow(Guid PlanHistoryId, Guid UserId, string UserName, string Email, string? AvatarUrl,
        Guid PlanId, string PlanCode, string PlanName, decimal Price, int DurationDays, string Status, DateTimeOffset StartedAt,
        DateTimeOffset? ExpiresAt, bool AutoRenew, string? PaymentReference);
    private sealed record LatestPayment(DateTimeOffset? At, decimal Amount, string Status);
}
