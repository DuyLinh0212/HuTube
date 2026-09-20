using System.Security.Claims;
using System.Text;
using System.Text.Json;
using HuTube.Application.Payments;
using HuTube.Infrastructure.Payments;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

[ApiController]
[Route("api/v1/payments")]
public sealed class PaymentsController(
    IPaymentService paymentService,
    SepaySignatureVerifier signatureVerifier,
    ILogger<PaymentsController> logger) : ControllerBase
{
    private Guid UserId => Guid.TryParse(User.FindFirst("sub")?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value, out var id)
        ? id
        : throw new PaymentException(401, "UNAUTHORIZED", "Vui lòng đăng nhập để tiếp tục.");

    /// <summary>
    /// Khởi tạo đơn hàng thanh toán mua gói trả phí bằng SePay.
    /// </summary>
    [Authorize]
    [HttpPost]
    public async Task<ActionResult<CreatePaymentResponse>> InitiateAsync(
        [FromBody] CreatePaymentRequest request,
        CancellationToken ct)
    {
        var response = await paymentService.InitiateAsync(UserId, request, ct);
        return Ok(response);
    }

    /// <summary>
    /// Lấy danh sách lịch sử giao dịch thanh toán của người dùng hiện tại.
    /// </summary>
    [Authorize]
    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<PaymentSummaryResponse>>> GetMyPaymentsAsync(CancellationToken ct)
    {
        var result = await paymentService.GetUserPaymentsAsync(UserId, ct);
        return Ok(result);
    }

    /// <summary>
    /// Lấy chi tiết/trạng thái một giao dịch thanh toán (dùng cho client polling kết quả).
    /// </summary>
    [Authorize]
    [HttpGet("{paymentId:guid}")]
    public async Task<ActionResult<PaymentSummaryResponse>> GetPaymentAsync(Guid paymentId, CancellationToken ct)
    {
        var result = await paymentService.GetPaymentAsync(UserId, paymentId, ct);
        if (result == null) return NotFound();
        return Ok(result);
    }

    /// <summary>
    /// Webhook nhận thông báo chuyển khoản tự động từ SePay.
    /// SePay yêu cầu trả về HTTP 200/201 với body {"success": true}.
    /// </summary>
    [HttpPost("webhook/sepay")]
    [AllowAnonymous]
    public async Task<IActionResult> HandleSepayWebhookAsync(CancellationToken ct)
    {
        // 1. Đọc raw body bytes để verify chữ ký HMAC-SHA256
        using var reader = new StreamReader(Request.Body, Encoding.UTF8);
        var bodyString = await reader.ReadToEndAsync(ct);
        var rawBytes = Encoding.UTF8.GetBytes(bodyString);

        var signature = Request.Headers["X-SePay-Signature"].FirstOrDefault();
        var timestamp = Request.Headers["X-SePay-Timestamp"].FirstOrDefault();

        // 2. Xác thực chữ ký nếu cấu hình SecretKey đã có
        if (!signatureVerifier.Verify(rawBytes, signature, timestamp))
        {
            logger.LogWarning("SePay webhook signature verification failed.");
            return Unauthorized(new { success = false, message = "Invalid signature." });
        }

        // 3. Deserialize payload
        SepayWebhookPayload? payload;
        try
        {
            var jsonOptions = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
            payload = JsonSerializer.Deserialize<SepayWebhookPayload>(bodyString, jsonOptions);
            if (payload == null)
            {
                return BadRequest(new { success = false, message = "Empty payload." });
            }
        }
        catch (JsonException ex)
        {
            logger.LogError(ex, "Failed to deserialize SePay webhook payload.");
            return BadRequest(new { success = false, message = "Malformed JSON." });
        }

        // 4. Xử lý logic nạp tiền / kích hoạt gói
        try
        {
            await paymentService.HandleSepayWebhookAsync(payload, ct);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error processing SePay payment for transaction {TransactionId}.", payload.Id);
            // Vẫn trả success: true nếu lỗi nội bộ không khắc phục được bằng retry ngay,
            // hoặc trả 500 nếu muốn SePay retry (SePay retry tối đa 7 lần).
            return StatusCode(500, new { success = false, message = "Internal processing error." });
        }

        // SePay yêu cầu response đúng định dạng này
        return Ok(new { success = true });
    }
}
