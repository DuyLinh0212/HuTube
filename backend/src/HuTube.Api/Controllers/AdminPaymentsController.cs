using HuTube.Api.Authorization;
using HuTube.Application.Payments;
using HuTube.Domain.Rbac;
using HuTube.Infrastructure.Payments;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace HuTube.Api.Controllers;

[ApiController, Authorize, Route("api/v1/admin/payments"), EnableRateLimiting("admin")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class AdminPaymentsController(AdminPaymentService payments) : ControllerBase
{
    [HttpGet, RequirePermission(AdminPermissions.PaymentView)]
    public Task<AdminPaymentPageResponse> GetPageAsync(
        [FromQuery] string? search = null,
        [FromQuery] string? status = null,
        [FromQuery] string? method = null,
        [FromQuery] string? type = null,
        [FromQuery] DateTimeOffset? fromDate = null,
        [FromQuery] DateTimeOffset? toDate = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken ct = default) =>
        payments.GetPageAsync(search, status, method, type, fromDate, toDate, page, pageSize, ct);

    [HttpGet("export"), RequirePermission(AdminPermissions.PaymentView)]
    public Task<IReadOnlyList<AdminPaymentItemResponse>> ExportAsync(
        [FromQuery] string? search = null,
        [FromQuery] string? status = null,
        [FromQuery] string? method = null,
        [FromQuery] string? type = null,
        [FromQuery] DateTimeOffset? fromDate = null,
        [FromQuery] DateTimeOffset? toDate = null,
        CancellationToken ct = default) =>
        payments.ExportAsync(search, status, method, type, fromDate, toDate, ct);

    [HttpGet("{paymentId:guid}"), RequirePermission(AdminPermissions.PaymentView)]
    public async Task<ActionResult<AdminPaymentDetailResponse>> GetDetailAsync(Guid paymentId, CancellationToken ct)
    {
        var result = await payments.GetDetailAsync(paymentId, ct);
        return result is null ? NotFound() : Ok(result);
    }
}
