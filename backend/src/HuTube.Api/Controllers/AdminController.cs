using HuTube.Api.Authorization;
using HuTube.Application.Rbac;
using HuTube.Application.Plans;
using HuTube.Domain.Rbac;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

[ApiController, Authorize, Route("api/v1/admin")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class AdminController(RbacService rbac, IPlanService plans) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirst("sub")!.Value);

    [HttpGet("plans"), RequirePermission(AdminPermissions.PlanView)]
    public Task<IReadOnlyList<PlanResponse>> GetPlansAsync(CancellationToken ct) => plans.GetAdminPlansAsync(ct);

    [HttpPost("plans"), RequirePermission(AdminPermissions.PlanCreate)]
    public async Task<ActionResult<PlanResponse>> CreatePlanAsync(CreatePlanRequest request, CancellationToken ct)
    {
        var result = await plans.CreatePlanAsync(UserId, request, ct);
        return Created($"/api/v1/admin/plans/{result.PlanId}", result);
    }

    [HttpPut("plans/{planId:guid}"), RequirePermission(AdminPermissions.PlanEdit)]
    public Task<PlanResponse> UpdatePlanAsync(Guid planId, UpdatePlanRequest request, CancellationToken ct) =>
        plans.UpdatePlanAsync(UserId, planId, request, ct);

    [HttpPost("plans/{planId:guid}/archive"), RequirePermission(AdminPermissions.PlanArchive)]
    public async Task<IActionResult> ArchivePlanAsync(Guid planId, CancellationToken ct)
    {
        await plans.ArchivePlanAsync(UserId, planId, ct);
        return NoContent();
    }

    [HttpGet("me")]
    public Task<AdminMeResponse> GetMeAsync(CancellationToken ct) =>
        rbac.GetAdminMeAsync(UserId, ct);

    [HttpGet("permissions"), RequirePermission(AdminPermissions.RoleView)]
    public Task<List<PermissionResponse>> GetPermissionsAsync(CancellationToken ct) =>
        rbac.GetAllPermissionsAsync(ct);

    [HttpGet("roles"), RequirePermission(AdminPermissions.RoleView)]
    public Task<List<RoleResponse>> GetRolesAsync(CancellationToken ct) =>
        rbac.GetAllRolesAsync(ct);

    [HttpPost("roles"), RequirePermission(AdminPermissions.RoleEdit)]
    public async Task<ActionResult<RoleResponse>> CreateRoleAsync([FromBody] CreateRoleRequest request, CancellationToken ct)
    {
        var created = await rbac.CreateRoleAsync(UserId, request, ct);
        return Created($"/api/v1/admin/roles/{created.RoleId}", created);
    }

    [HttpPut("roles/{roleId:guid}"), RequirePermission(AdminPermissions.RoleEdit)]
    public Task<RoleResponse> UpdateRoleAsync(Guid roleId, [FromBody] UpdateRoleRequest request, CancellationToken ct) =>
        rbac.UpdateRoleAsync(UserId, roleId, request, ct);

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
