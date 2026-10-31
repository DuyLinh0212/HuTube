using System.Security.Claims;
using HuTube.Api.Authorization;
using HuTube.Application.Operations;
using HuTube.Domain.Rbac;
using HuTube.Infrastructure.Operations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace HuTube.Api.Controllers;

[ApiController, Authorize, Route("api/v1/admin/database-backups"), EnableRateLimiting("admin")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class AdminDatabaseBackupsController(AdminDatabaseBackupService backups) : ControllerBase
{
    [HttpGet, RequirePermission(AdminPermissions.DatabaseBackupView, AdminPermissions.DatabaseBackupManage)]
    public async Task<IActionResult> GetOverviewAsync(
        [FromQuery] DateOnly? fromDate,
        [FromQuery] DateOnly? toDate,
        CancellationToken ct)
    {
        try { return Ok(await backups.GetOverviewAsync(fromDate, toDate, ct)); }
        catch (ArgumentException ex) { return BadRequest(new { message = ex.Message }); }
    }

    [HttpPut("schedule"), RequirePermission(AdminPermissions.DatabaseBackupManage)]
    public async Task<IActionResult> UpdateScheduleAsync(
        [FromBody] UpdateDatabaseBackupScheduleRequest request,
        CancellationToken ct)
    {
        if (!TryGetActor(out var actorId)) return Unauthorized();
        try
        {
            return Ok(await backups.UpdateScheduleAsync(request, actorId,
                HttpContext.Connection.RemoteIpAddress?.ToString(), Request.Headers.UserAgent.ToString(), ct));
        }
        catch (ArgumentException ex) { return BadRequest(new { message = ex.Message }); }
    }

    [HttpPost("runs"), RequirePermission(AdminPermissions.DatabaseBackupManage)]
    public async Task<IActionResult> QueueManualBackupAsync(CancellationToken ct)
    {
        if (!TryGetActor(out var actorId)) return Unauthorized();
        try
        {
            var run = await backups.QueueManualBackupAsync(actorId,
                HttpContext.Connection.RemoteIpAddress?.ToString(), Request.Headers.UserAgent.ToString(), ct);
            return Accepted(run);
        }
        catch (DatabaseBackupAlreadyRunningException ex)
        {
            return Conflict(new { code = "BACKUP_ALREADY_RUNNING", message = ex.Message });
        }
    }

    [HttpGet("runs/{runId:guid}/download-url"), RequirePermission(AdminPermissions.DatabaseBackupView, AdminPermissions.DatabaseBackupManage)]
    public async Task<IActionResult> GetDownloadUrlAsync(Guid runId, CancellationToken ct)
    {
        if (!TryGetActor(out var actorId)) return Unauthorized();
        try
        {
            return Ok(await backups.GetDownloadUrlAsync(runId, actorId,
                HttpContext.Connection.RemoteIpAddress?.ToString(), Request.Headers.UserAgent.ToString(), ct));
        }
        catch (DatabaseBackupNotAvailableException ex)
        {
            return NotFound(new { code = "BACKUP_NOT_AVAILABLE", message = ex.Message });
        }
        catch (DatabaseBackupStorageUnavailableException ex)
        {
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new { code = "BACKUP_STORAGE_UNAVAILABLE", message = ex.Message });
        }
    }

    private bool TryGetActor(out Guid actorId) =>
        Guid.TryParse(User.FindFirstValue("sub") ?? User.FindFirstValue(ClaimTypes.NameIdentifier), out actorId);
}
