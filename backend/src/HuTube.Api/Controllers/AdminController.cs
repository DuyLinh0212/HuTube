using HuTube.Api.Authorization;
using HuTube.Application.Plans;
using HuTube.Application.Policies;
using HuTube.Application.Rbac;
using HuTube.Application.Videos;
using HuTube.Domain.Rbac;
using HuTube.Infrastructure.Policies;
using HuTube.Infrastructure.Videos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

[ApiController, Authorize, Route("api/v1/admin")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class AdminController(
    RbacService rbac,
    IPlanService plans,
    ModerationService moderation,
    PolicyService policyService) : ControllerBase
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
    public Task<List<ModerationQueueItemResponse>> GetModerationQueueAsync(
        [FromQuery] string? status = null,
        [FromQuery] string? riskLevel = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken ct = default) =>
        moderation.GetQueueAsync(status, riskLevel, page, pageSize, ct);

    [HttpPost("moderation/{caseId:guid}/claim"), RequirePermission(AdminPermissions.ModerationClaim)]
    public async Task<IActionResult> ClaimCaseAsync(Guid caseId, CancellationToken ct)
    {
        await moderation.ClaimCaseAsync(UserId, caseId, ct);
        return Ok(new { message = "Đã nhận xử lý phiếu kiểm duyệt thành công." });
    }

    [HttpPost("moderation/{caseId:guid}/release"), RequirePermission(AdminPermissions.ModerationClaim)]
    public async Task<IActionResult> ReleaseCaseAsync(Guid caseId, CancellationToken ct)
    {
        await moderation.ReleaseCaseAsync(UserId, caseId, ct);
        return Ok(new { message = "Đã hủy nhận và trả phiếu về hàng đợi thành công." });
    }

    [HttpPost("moderation/{caseId:guid}/resolve"), RequirePermission(AdminPermissions.ModerationReview)]
    public Task<ModerationDecisionResponse> ResolveCaseAsync(
        Guid caseId,
        [FromBody] ResolveModerationRequest request,
        CancellationToken ct) =>
        moderation.ResolveCaseAsync(UserId, caseId, request, ct);

    [HttpGet("policies"), RequirePermission(AdminPermissions.SystemViewSetting)]
    public Task<List<PolicyDto>> GetAdminPoliciesAsync(
        [FromQuery] string? group = null,
        [FromQuery] string? status = null,
        CancellationToken ct = default) =>
        policyService.GetAdminPoliciesAsync(group, status, ct);

    [HttpPost("policies"), RequirePermission(AdminPermissions.SystemEditSetting)]
    public async Task<ActionResult<PolicyDto>> CreatePolicyAsync(
        [FromBody] CreatePolicyRequest request,
        CancellationToken ct)
    {
        var created = await policyService.CreatePolicyAsync(UserId, request, ct);
        return Created($"/api/v1/admin/policies/{created.PolicyId}", created);
    }

    [HttpPut("policies/{policyId:guid}/publish"), RequirePermission(AdminPermissions.SystemEditSetting)]
    public Task<PolicyDto> PublishPolicyVersionAsync(
        Guid policyId,
        [FromBody] UpdatePolicyRequest request,
        CancellationToken ct) =>
        policyService.PublishPolicyVersionAsync(UserId, policyId, request, ct);

    [HttpGet("audit-logs"), RequirePermission(AdminPermissions.AuditView)]
    public Task<List<AuditLogResponse>> GetAuditLogsAsync(CancellationToken ct) =>
        rbac.GetAuditLogsAsync(50, ct);
}
