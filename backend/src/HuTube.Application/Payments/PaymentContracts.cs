namespace HuTube.Application.Payments;

// ─── Requests ────────────────────────────────────────────────────────────────

/// <summary>Tạo đơn hàng thanh toán để mua gói dịch vụ.</summary>
public sealed record CreatePaymentRequest(
    Guid PlanId,
    bool AutoRenew = false,
    string? IdempotencyKey = null);

// ─── Responses ───────────────────────────────────────────────────────────────

/// <summary>Thông tin đơn hàng vừa tạo, trả về cho client hiển thị QR và hướng dẫn chuyển khoản.</summary>
public sealed record CreatePaymentResponse(
    Guid PaymentId,
    Guid PlanId,
    string PlanName,
    /// <summary>Nội dung cần ghi khi chuyển khoản, ví dụ "HUTUBE-A1B2C3D4".</summary>
    string TransactionCode,
    /// <summary>URL hình QR VietQR dùng để quét thanh toán.</summary>
    string QrCodeUrl,
    decimal Amount,
    string Currency,
    DateTimeOffset ExpiresAt);

/// <summary>Tóm tắt một giao dịch thanh toán.</summary>
public sealed record PaymentSummaryResponse(
    Guid PaymentId,
    Guid PlanId,
    string PlanName,
    string TransactionCode,
    decimal Amount,
    string Currency,
    string Status,
    DateTimeOffset? PaidAt,
    DateTimeOffset CreatedAt,
    DateTimeOffset ExpiresAt);

// ─── SePay Webhook Payload ────────────────────────────────────────────────────

/// <summary>
/// Payload JSON mà SePay gửi tới webhook endpoint sau khi phát hiện giao dịch ngân hàng.
/// </summary>
public sealed record SepayWebhookPayload(
    long Id,
    string Gateway,
    string TransactionDate,
    string AccountNumber,
    string? SubAccount,
    string? Code,
    string Content,
    string TransferType,
    long TransferAmount,
    long Accumulated,
    string? ReferenceCode);

// ─── Exceptions ──────────────────────────────────────────────────────────────

public sealed class PaymentException(int status, string code, string message) : Exception(message)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
}

// ─── Interface ───────────────────────────────────────────────────────────────

public interface IPaymentService
{
    /// <summary>Tạo đơn hàng thanh toán, trả về QR code và mã chuyển khoản.</summary>
    Task<CreatePaymentResponse> InitiateAsync(Guid userId, CreatePaymentRequest request, CancellationToken ct = default);

    /// <summary>Xử lý webhook từ SePay. Trả về true nếu đã xử lý thành công (kể cả trùng lặp).</summary>
    Task<bool> HandleSepayWebhookAsync(SepayWebhookPayload payload, CancellationToken ct = default);

    /// <summary>Lấy danh sách giao dịch của user hiện tại.</summary>
    Task<IReadOnlyList<PaymentSummaryResponse>> GetUserPaymentsAsync(Guid userId, CancellationToken ct = default);

    /// <summary>Lấy trạng thái một giao dịch cụ thể (để frontend polling).</summary>
    Task<PaymentSummaryResponse?> GetPaymentAsync(Guid userId, Guid paymentId, CancellationToken ct = default);
}
