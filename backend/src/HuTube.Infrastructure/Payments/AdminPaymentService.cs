using HuTube.Application.Payments;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Payments;

public sealed class AdminPaymentService(HuTubeDbContext db, TimeProvider clock)
{
    public async Task<AdminPaymentPageResponse> GetPageAsync(
        string? search, string? status, string? method, string? type,
        DateTimeOffset? fromDate, DateTimeOffset? toDate, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var now = clock.GetUtcNow();
        var rangeQuery = ApplyDateRange(db.Payments.AsNoTracking(), fromDate, toDate);
        var query = BuildPaymentsQuery(search, status, method, type, fromDate, toDate);

        var total = await query.LongCountAsync(ct);
        var pagePayments = query.OrderByDescending(payment => payment.CreatedAt).ThenByDescending(payment => payment.PaymentId)
            .Skip((page - 1) * pageSize).Take(pageSize);
        var items = await BuildItemsQuery(pagePayments).ToListAsync(ct);

        var monthStart = new DateTimeOffset(now.Year, now.Month, 1, 0, 0, 0, TimeSpan.Zero);
        var stats = new AdminPaymentStatsResponse(
            await rangeQuery.Where(payment => payment.Status == "paid").SumAsync(payment => (decimal?)payment.Amount, ct) ?? 0,
            await db.Payments.AsNoTracking().Where(payment => payment.Status == "paid" && payment.PaidAt >= monthStart && payment.PaidAt < monthStart.AddMonths(1))
                .SumAsync(payment => (decimal?)payment.Amount, ct) ?? 0,
            await rangeQuery.LongCountAsync(payment => payment.Status == "paid", ct),
            await rangeQuery.LongCountAsync(payment => payment.Status == "refunded", ct),
            await rangeQuery.LongCountAsync(payment => payment.Status == "pending" || payment.Status == "processing", ct),
            await rangeQuery.LongCountAsync(payment => payment.Status == "failed" || payment.Status == "cancelled", ct));

        var chartEnd = toDate?.Date ?? now.Date;
        var chartStart = fromDate?.Date ?? chartEnd.AddDays(-89);
        if (chartEnd - chartStart > TimeSpan.FromDays(89)) chartStart = chartEnd.AddDays(-89);
        var chartRangeQuery = ApplyDateRange(db.Payments.AsNoTracking(), chartStart, chartEnd);
        var dailyRows = await chartRangeQuery
            .GroupBy(payment => new { payment.CreatedAt.Year, payment.CreatedAt.Month, payment.CreatedAt.Day })
            .Select(group => new
            {
                group.Key.Year,
                group.Key.Month,
                group.Key.Day,
                Revenue = group.Where(payment => payment.Status == "paid").Sum(payment => (decimal?)payment.Amount) ?? 0,
                Transactions = group.LongCount()
            })
            .OrderBy(row => row.Year).ThenBy(row => row.Month).ThenBy(row => row.Day)
            .ToListAsync(ct);
        var daily = dailyRows.Select(row => new AdminPaymentDailyResponse(new DateOnly(row.Year, row.Month, row.Day), row.Revenue, row.Transactions)).ToList();

        var methodRows = await rangeQuery.GroupBy(payment => payment.PaymentMethod)
            .Select(group => new
            {
                Method = group.Key,
                Transactions = group.LongCount(),
                Revenue = group.Where(payment => payment.Status == "paid").Sum(payment => (decimal?)payment.Amount) ?? 0
            })
            .OrderByDescending(row => row.Transactions).ThenBy(row => row.Method)
            .ToListAsync(ct);
        var rangeTotal = methodRows.Sum(row => row.Transactions);
        var methods = methodRows.Select(row => new AdminPaymentMethodResponse(
            row.Method, row.Transactions, row.Revenue, rangeTotal == 0 ? 0 : Math.Round(row.Transactions * 100d / rangeTotal, 1))).ToList();
        var availableMethods = await db.Payments.AsNoTracking().Select(payment => payment.PaymentMethod).Distinct().OrderBy(value => value).ToListAsync(ct);

        return new AdminPaymentPageResponse(items, page, pageSize, total, (long)page * pageSize < total,
            stats, daily, methods, availableMethods);
    }

    public async Task<IReadOnlyList<AdminPaymentItemResponse>> ExportAsync(
        string? search, string? status, string? method, string? type,
        DateTimeOffset? fromDate, DateTimeOffset? toDate, CancellationToken ct)
    {
        var payments = BuildPaymentsQuery(search, status, method, type, fromDate, toDate)
            .OrderByDescending(payment => payment.CreatedAt).ThenByDescending(payment => payment.PaymentId);
        return await BuildItemsQuery(payments).ToListAsync(ct);
    }

    public async Task<AdminPaymentDetailResponse?> GetDetailAsync(Guid paymentId, CancellationToken ct)
    {
        var transaction = await BuildItemsQuery(db.Payments.AsNoTracking().Where(payment => payment.PaymentId == paymentId))
            .SingleOrDefaultAsync(ct);
        if (transaction is null) return null;

        var events = new List<AdminPaymentEventResponse>
        {
            new("created", "Tạo giao dịch", $"Mã thanh toán {transaction.TransactionCode} được tạo.", transaction.CreatedAt)
        };
        if (transaction.Status == "paid")
        {
            events.Add(new("paid", "Thanh toán thành công",
                transaction.SepayTransactionId.HasValue
                    ? $"SePay ghi nhận giao dịch {transaction.SepayTransactionId.Value}."
                    : $"Đã nhận {transaction.Amount:N0} {transaction.Currency} qua {transaction.PaymentMethod}.",
                transaction.PaidAt ?? transaction.UpdatedAt));
        }
        else if (transaction.Status is "processing" or "failed" or "cancelled" or "refunded")
        {
            var title = transaction.Status switch
            {
                "processing" => "Đang xử lý thanh toán",
                "failed" => "Thanh toán thất bại",
                "cancelled" => "Giao dịch đã hủy",
                _ => "Đã hoàn tiền"
            };
            var description = transaction.Status switch
            {
                "processing" => "Cổng thanh toán đang xử lý giao dịch.",
                "failed" => "Cổng thanh toán không xác nhận giao dịch.",
                "cancelled" => "Giao dịch đã được hủy.",
                _ => "Giao dịch đã được ghi nhận hoàn tiền."
            };
            events.Add(new(transaction.Status, title, description, transaction.UpdatedAt));
        }

        return new AdminPaymentDetailResponse(transaction, events.OrderBy(item => item.OccurredAt).ToList());
    }

    private IQueryable<AdminPaymentItemResponse> BuildItemsQuery(IQueryable<HuTube.Domain.Payments.Payment> payments) =>
        from payment in payments
        join user in db.Users.IgnoreQueryFilters().AsNoTracking() on payment.UserId equals user.UserId
        join plan in db.Plans.AsNoTracking() on payment.PlanId equals plan.PlanId
        orderby payment.CreatedAt descending, payment.PaymentId descending
        select new AdminPaymentItemResponse(
            payment.PaymentId, payment.TransactionCode, user.UserId, user.DisplayName, user.Email, user.AvatarUrl,
            plan.PlanId, plan.Name, "subscription", payment.PaymentMethod, payment.Amount, payment.Currency,
            payment.Status, payment.CreatedAt, payment.PaidAt, payment.UpdatedAt, payment.ExpiresAt,
            payment.SepayTransactionId, payment.PlanHistoryId);

    private static IQueryable<HuTube.Domain.Payments.Payment> ApplyDateRange(
        IQueryable<HuTube.Domain.Payments.Payment> query, DateTimeOffset? fromDate, DateTimeOffset? toDate)
    {
        if (fromDate.HasValue)
        {
            var start = new DateTimeOffset(fromDate.Value.Date, fromDate.Value.Offset).ToUniversalTime();
            query = query.Where(payment => payment.CreatedAt >= start);
        }
        if (toDate.HasValue)
        {
            var exclusiveEnd = new DateTimeOffset(toDate.Value.Date.AddDays(1), toDate.Value.Offset).ToUniversalTime();
            query = query.Where(payment => payment.CreatedAt < exclusiveEnd);
        }
        return query;
    }

    private IQueryable<HuTube.Domain.Payments.Payment> BuildPaymentsQuery(
        string? search, string? status, string? method, string? type,
        DateTimeOffset? fromDate, DateTimeOffset? toDate)
    {
        var query = db.Payments.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(search))
        {
            var term = search.Trim();
            query = query.Where(payment => payment.TransactionCode.Contains(term)
                || db.Users.IgnoreQueryFilters().Any(user => user.UserId == payment.UserId
                    && (user.DisplayName.Contains(term) || user.Email.Contains(term)))
                || db.Plans.Any(plan => plan.PlanId == payment.PlanId && plan.Name.Contains(term)));
        }
        if (!string.IsNullOrWhiteSpace(status) && status != "all") query = query.Where(payment => payment.Status == status);
        if (!string.IsNullOrWhiteSpace(method) && method != "all") query = query.Where(payment => payment.PaymentMethod == method);
        if (!string.IsNullOrWhiteSpace(type) && type != "all" && type != "subscription") query = query.Where(_ => false);
        return ApplyDateRange(query, fromDate, toDate);
    }
}
