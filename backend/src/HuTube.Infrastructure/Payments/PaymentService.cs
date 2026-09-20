using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using HuTube.Application.Payments;
using HuTube.Application.Plans;
using HuTube.Domain.Payments;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Payments;

public sealed class PaymentService(
    HuTubeDbContext db,
    IPlanService planService,
    SepayOptions options,
    TimeProvider clock) : IPaymentService
{
    private DateTimeOffset Now => clock.GetUtcNow();

    // ─── InitiateAsync ────────────────────────────────────────────────────────

    public async Task<CreatePaymentResponse> InitiateAsync(Guid userId, CreatePaymentRequest request, CancellationToken ct = default)
    {
        // Validate gói tồn tại và có giá > 0
        var plan = await db.Plans.AsNoTracking()
            .SingleOrDefaultAsync(x => x.PlanId == request.PlanId && x.Status == "active", ct)
            ?? throw new PaymentException(404, "PLAN_NOT_FOUND", "Gói dịch vụ không tồn tại.");

        if (plan.Price <= 0)
            throw new PaymentException(400, "FREE_PLAN_NO_PAYMENT", "Gói miễn phí không cần thanh toán. Vui lòng dùng endpoint đăng ký trực tiếp.");

        var now = Now;

        // Idempotency: nếu cùng key + user + plan → trả về payment cũ (nếu còn pending và chưa hết hạn)
        if (!string.IsNullOrWhiteSpace(request.IdempotencyKey))
        {
            var existing = await db.Payments
                .AsNoTracking()
                .FirstOrDefaultAsync(x =>
                    x.IdempotencyKey == request.IdempotencyKey
                    && x.UserId == userId
                    && x.PlanId == request.PlanId
                    && x.Status == "pending"
                    && x.ExpiresAt > now, ct);

            if (existing != null)
                return BuildResponse(existing, plan.Name);
        }

        // Sinh mã chuyển khoản duy nhất
        var transactionCode = await GenerateUniqueTransactionCodeAsync(ct);

        var payment = new Payment
        {
            PaymentId = Guid.NewGuid(),
            UserId = userId,
            PlanId = plan.PlanId,
            Amount = plan.Price,
            Currency = "VND",
            PaymentMethod = "sepay",
            TransactionCode = transactionCode,
            Status = "pending",
            IdempotencyKey = request.IdempotencyKey,
            ExpiresAt = now.AddMinutes(options.PaymentExpiryMinutes),
            CreatedAt = now,
            UpdatedAt = now,
        };

        db.Payments.Add(payment);
        await db.SaveChangesAsync(ct);

        return BuildResponse(payment, plan.Name);
    }

    // ─── HandleSepayWebhookAsync ──────────────────────────────────────────────

    public async Task<bool> HandleSepayWebhookAsync(SepayWebhookPayload payload, CancellationToken ct = default)
    {
        // Chỉ xử lý tiền vào
        if (!string.Equals(payload.TransferType, "in", StringComparison.OrdinalIgnoreCase))
            return true;

        // Deduplication: nếu đã xử lý giao dịch này rồi (theo SepayTransactionId) thì bỏ qua
        var alreadyProcessed = await db.Payments
            .AnyAsync(x => x.SepayTransactionId == payload.Id && x.Status == "paid", ct);
        if (alreadyProcessed)
            return true;

        // Tìm payment khớp với mã chuyển khoản trong nội dung
        var payment = await FindMatchingPaymentAsync(payload, ct);
        if (payment == null)
            return true; // Giao dịch không liên quan đến HuTube → trả true để SePay không retry

        var now = Now;

        // Validate số tiền
        if ((decimal)payload.TransferAmount < payment.Amount)
            return true; // Số tiền không đủ — không xử lý nhưng vẫn trả true

        // Validate payment còn pending
        if (payment.Status != "pending")
            return true;

        // Validate chưa hết hạn
        if (payment.ExpiresAt < now)
        {
            payment.Status = "cancelled";
            payment.UpdatedAt = now;
            await db.SaveChangesAsync(ct);
            return true;
        }

        // Kích hoạt gói
        var planHistoryId = await planService.ActivatePaidPlanAsync(
            payment.UserId, payment.PlanId, payment.PaymentId, autoRenew: false, ct);

        // Cập nhật payment
        payment.Status = "paid";
        payment.PaidAt = now;
        payment.UpdatedAt = now;
        payment.SepayTransactionId = payload.Id;
        payment.PlanHistoryId = planHistoryId;
        payment.GatewayPayload = JsonSerializer.Serialize(payload);

        await db.SaveChangesAsync(ct);
        return true;
    }

    // ─── GetUserPaymentsAsync ─────────────────────────────────────────────────

    public async Task<IReadOnlyList<PaymentSummaryResponse>> GetUserPaymentsAsync(Guid userId, CancellationToken ct = default)
    {
        var results = await (
            from p in db.Payments.AsNoTracking()
            join pl in db.Plans.AsNoTracking() on p.PlanId equals pl.PlanId
            where p.UserId == userId
            orderby p.CreatedAt descending
            select new PaymentSummaryResponse(
                p.PaymentId,
                p.PlanId,
                pl.Name,
                p.TransactionCode,
                p.Amount,
                p.Currency,
                p.Status,
                p.PaidAt,
                p.CreatedAt,
                p.ExpiresAt)
        ).ToListAsync(ct);

        return results;
    }

    // ─── GetPaymentAsync ──────────────────────────────────────────────────────

    public async Task<PaymentSummaryResponse?> GetPaymentAsync(Guid userId, Guid paymentId, CancellationToken ct = default)
    {
        return await (
            from p in db.Payments.AsNoTracking()
            join pl in db.Plans.AsNoTracking() on p.PlanId equals pl.PlanId
            where p.UserId == userId && p.PaymentId == paymentId
            select new PaymentSummaryResponse(
                p.PaymentId,
                p.PlanId,
                pl.Name,
                p.TransactionCode,
                p.Amount,
                p.Currency,
                p.Status,
                p.PaidAt,
                p.CreatedAt,
                p.ExpiresAt)
        ).FirstOrDefaultAsync(ct);
    }

    // ─── Private Helpers ──────────────────────────────────────────────────────

    private async Task<Payment?> FindMatchingPaymentAsync(SepayWebhookPayload payload, CancellationToken ct)
    {
        // SePay có thể trích xuất mã tự động vào field "code", hoặc mã nằm trong "content"
        var candidates = new List<string?> { payload.Code };

        // Tìm trong nội dung chuyển khoản (content chứa mã dạng "HUTUBE-XXXXXXXX")
        var content = payload.Content?.ToUpperInvariant() ?? "";
        var prefix = (options.TransactionCodePrefix + "-").ToUpperInvariant();
        var idx = content.IndexOf(prefix, StringComparison.Ordinal);
        if (idx >= 0)
        {
            var rest = content[(idx + prefix.Length)..];
            var end = rest.IndexOfAny([' ', '\t', '\n', '\r']);
            var code = end >= 0 ? rest[..end] : rest;
            if (code.Length >= 6) // mã tối thiểu 6 ký tự
                candidates.Add(options.TransactionCodePrefix + "-" + code);
        }

        foreach (var candidate in candidates.Where(c => !string.IsNullOrWhiteSpace(c)))
        {
            var payment = await db.Payments
                .FirstOrDefaultAsync(x => x.TransactionCode == candidate, ct);
            if (payment != null) return payment;
        }

        return null;
    }

    private async Task<string> GenerateUniqueTransactionCodeAsync(CancellationToken ct)
    {
        for (var attempt = 0; attempt < 5; attempt++)
        {
            var suffix = GenerateRandomCode(8);
            var code = $"{options.TransactionCodePrefix}-{suffix}";
            var exists = await db.Payments.AnyAsync(x => x.TransactionCode == code, ct);
            if (!exists) return code;
        }
        throw new PaymentException(500, "CODE_GENERATION_FAILED", "Không thể tạo mã thanh toán. Vui lòng thử lại.");
    }

    private static string GenerateRandomCode(int length)
    {
        const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // bỏ 0/O, 1/I để dễ đọc
        var bytes = new byte[length];
        RandomNumberGenerator.Fill(bytes);
        return new string(bytes.Select(b => chars[b % chars.Length]).ToArray());
    }

    private CreatePaymentResponse BuildResponse(Payment payment, string planName)
    {
        var qrUrl = string.IsNullOrWhiteSpace(options.AccountNumber)
            ? "" // Chưa cấu hình → trả về rỗng; frontend hiển thị thông báo
            : $"https://vietqr.app/img?acc={options.AccountNumber}&bank={Uri.EscapeDataString(options.BankCode)}" +
              $"&amount={payment.Amount:0}&des={Uri.EscapeDataString(payment.TransactionCode)}";

        return new CreatePaymentResponse(
            payment.PaymentId,
            payment.PlanId,
            planName,
            payment.TransactionCode,
            qrUrl,
            payment.Amount,
            payment.Currency,
            payment.ExpiresAt);
    }
}
