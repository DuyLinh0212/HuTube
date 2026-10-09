using HuTube.Api.Authorization;
using HuTube.Application.Operations;
using HuTube.Domain.Rbac;
using HuTube.Infrastructure.Operations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace HuTube.Api.Controllers;

[ApiController, Authorize, Route("api/v1/admin/operations"), EnableRateLimiting("admin")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class AdminOperationsController(AdminOperationsService operations) : ControllerBase
{
    [HttpGet("system"), RequirePermission(AdminPermissions.SystemViewSetting)]
    public Task<AdminSystemOverviewResponse> GetSystemOverviewAsync(CancellationToken ct) =>
        operations.GetSystemOverviewAsync(ct);

    [HttpGet("reports"), RequirePermission(AdminPermissions.DashboardView)]
    public Task<AdminSystemReportResponse> GetReportAsync([FromQuery] int days = 30, CancellationToken ct = default) =>
        operations.GetReportAsync(days, ct);

    [HttpGet("audit-logs"), RequirePermission(AdminPermissions.AuditView)]
    public Task<AdminAuditLogPage> GetAuditLogsAsync(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 25,
        [FromQuery] string? search = null,
        [FromQuery] string? action = null,
        [FromQuery] DateTimeOffset? fromDate = null,
        [FromQuery] DateTimeOffset? toDate = null,
        CancellationToken ct = default) =>
        operations.GetAuditLogsAsync(page, pageSize, search, action, fromDate, toDate, ct);
}
