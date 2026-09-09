using HuTube.Api.Authorization;
using HuTube.Application.Rbac;
using HuTube.Domain.Rbac;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

[ApiController, Authorize, Route("api/v1/admin")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class AdminController(RbacService rbac) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirst("sub")!.Value);

    [HttpGet("me")]
    public Task<AdminMeResponse> GetMeAsync(CancellationToken ct) =>
        rbac.GetAdminMeAsync(UserId, ct);

    [HttpGet("permissions"), RequirePermission(AdminPermissions.RoleView)]
    public Task<List<PermissionResponse>> GetPermissionsAsync(CancellationToken ct) =>
        rbac.GetAllPermissionsAsync(ct);

    [HttpGet("roles"), RequirePermission(AdminPermissions.RoleView)]
    public Task<List<RoleResponse>> GetRolesAsync(CancellationToken ct) =>
        rbac.GetAllRolesAsync(ct);

    [HttpGet("moderation/queue"), RequirePermission(AdminPermissions.ModerationViewQueue)]
    public IActionResult GetModerationQueue() =>
        Ok(new { items = Array.Empty<object>(), message = "Hàng đợi kiểm duyệt nội dung." });

    [HttpPost("moderation/approve"), RequirePermission(AdminPermissions.ModerationApprove)]
    public IActionResult ApproveContent() =>
        Ok(new { message = "Đã phê duyệt nội dung." });

    [HttpPost("moderation/reject"), RequirePermission(AdminPermissions.ModerationReject)]
    public IActionResult RejectContent() =>
        Ok(new { message = "Đã từ chối nội dung." });

    [HttpGet("audit-logs"), RequirePermission(AdminPermissions.AuditView)]
    public Task<List<AuditLogResponse>> GetAuditLogsAsync(CancellationToken ct) =>
        rbac.GetAuditLogsAsync(50, ct);
}
