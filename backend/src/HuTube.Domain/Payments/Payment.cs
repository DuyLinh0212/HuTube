namespace HuTube.Domain.Payments;

public sealed class Payment
{
    public Guid PaymentId { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public Guid PlanId { get; set; }
    public Guid? PlanHistoryId { get; set; }
    public decimal Amount { get; set; }
    public string Currency { get; set; } = "VND";
    public string PaymentMethod { get; set; } = "sepay";

    /// <summary>
    /// Mã nội dung chuyển khoản, dạng "HUTUBE-XXXXXXXX". Người dùng điền nội dung này khi chuyển khoản.
    /// </summary>
    public string TransactionCode { get; set; } = "";

    /// <summary>
    /// ID giao dịch phía SePay (dùng để chống xử lý trùng lặp khi SePay retry).
    /// </summary>
    public long? SepayTransactionId { get; set; }

    public DateTimeOffset? PaidAt { get; set; }

    /// <summary>
    /// Trạng thái: pending | paid | failed | cancelled
    /// </summary>
    public string Status { get; set; } = "pending";

    /// <summary>
    /// Idempotency key do client gửi lên khi tạo payment.
    /// </summary>
    public string? IdempotencyKey { get; set; }

    /// <summary>
    /// Toàn bộ payload webhook từ SePay (lưu để audit).
    /// </summary>
    public string GatewayPayload { get; set; } = "{}";

    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}
