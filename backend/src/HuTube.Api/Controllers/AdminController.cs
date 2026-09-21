using HuTube.Api.Authorization;
using HuTube.Application.Plans;
using HuTube.Application.Policies;
using HuTube.Application.Rbac;
using HuTube.Application.Taxonomy;
using HuTube.Application.Users;
using HuTube.Application.Videos;
using HuTube.Domain.Rbac;
using HuTube.Infrastructure.Policies;
using HuTube.Infrastructure.Taxonomy;
using HuTube.Infrastructure.Users;
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
    PolicyService policyService,
    TaxonomyService taxonomy,
    AdminUserService users,
    StrikeService strikeService,
    ReportService reportService,
    AppealService appealService) : ControllerBase
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

    [HttpGet("plans/subscriptions/{userId:guid}"), RequirePermission(AdminPermissions.PlanView)]
    public async Task<ActionResult<PlanDetailResponse>> GetUserSubscriptionAsync(Guid userId, CancellationToken ct)
    {
        var result = await plans.GetMyPlanAsync(userId, ct);
        return result == null ? NotFound() : Ok(result);
    }

    [HttpGet("me")]
    public Task<AdminMeResponse> GetMeAsync(CancellationToken ct) =>
        rbac.GetAdminMeAsync(UserId, ct);

    [HttpGet("users"), RequirePermission(AdminPermissions.UserView)]
    public Task<AdminUserListResponse> GetUsersAsync(
        [FromQuery] string? search = null,
        [FromQuery] string? role = null,
        [FromQuery] string? status = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        CancellationToken ct = default) =>
        users.GetUsersAsync(search, role, status, page, pageSize, ct);

    [HttpGet("users/{userId:guid}"), RequirePermission(AdminPermissions.UserView)]
    public Task<AdminUserDetailResponse> GetUserAsync(Guid userId, CancellationToken ct) =>
        users.GetUserAsync(userId, ct);

    [HttpPost("users/{userId:guid}/lock"), RequirePermission(AdminPermissions.UserBan)]
    public Task<AdminUserDetailResponse> LockUserAsync(Guid userId, [FromBody] AdminUserActionRequest request, CancellationToken ct) =>
        users.LockAsync(UserId, userId, request, ct);

    [HttpPost("users/{userId:guid}/unlock"), RequirePermission(AdminPermissions.UserBan)]
    public Task<AdminUserDetailResponse> UnlockUserAsync(Guid userId, [FromBody] AdminUserActionRequest request, CancellationToken ct) =>
        users.UnlockAsync(UserId, userId, request, ct);

    [HttpPut("users/{userId:guid}/role"), RequirePermission(AdminPermissions.UserEdit)]
    public Task<AdminUserDetailResponse> UpdateUserRoleAsync(Guid userId, [FromBody] UpdateAdminUserRoleRequest request, CancellationToken ct) =>
        users.UpdateRoleAsync(UserId, userId, request, ct);

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

    // Keep the legacy endpoint routable so callers without moderation.approve
    // receive 403 instead of a misleading 404. Case-specific resolution above
    // remains the canonical moderation API.
    [HttpPost("moderation/approve"), RequirePermission(AdminPermissions.ModerationApprove)]
    public IActionResult LegacyApproveAsync() => BadRequest(new { code = "CASE_ID_REQUIRED" });

    [HttpGet("policies"), RequirePermission(AdminPermissions.SystemViewSetting)]
    public Task<List<PolicyDto>> GetAdminPoliciesAsync(
        [FromQuery] string? group = null,
        [FromQuery] string? status = null,
        CancellationToken ct = default) =>
        policyService.GetAdminPoliciesAsync(group, status, ct);

    [HttpPost("policies"), RequirePermission(AdminPermissions.PolicyManage, AdminPermissions.SystemEditSetting)]
    public async Task<ActionResult<PolicyDto>> CreatePolicyAsync(
        [FromBody] CreatePolicyRequest request,
        CancellationToken ct)
    {
        var created = await policyService.CreatePolicyAsync(UserId, request, ct);
        return Created($"/api/v1/admin/policies/{created.PolicyId}", created);
    }

    [HttpPut("policies/{policyId:guid}/publish"), RequirePermission(AdminPermissions.PolicyManage, AdminPermissions.SystemEditSetting)]
    public Task<PolicyDto> PublishPolicyVersionAsync(
        Guid policyId,
        [FromBody] UpdatePolicyRequest request,
        CancellationToken ct) =>
        policyService.PublishPolicyVersionAsync(UserId, policyId, request, ct);

    [HttpGet("topics"), RequirePermission(AdminPermissions.SystemViewSetting)]
    public Task<List<AdminTopicResponse>> GetTopicsAsync(
        [FromQuery] string? status = null,
        CancellationToken ct = default) =>
        taxonomy.GetTopicsAsync(status, ct);

    [HttpPost("topics"), RequirePermission(AdminPermissions.TaxonomyManage)]
    public async Task<ActionResult<AdminTopicResponse>> CreateTopicAsync(
        [FromBody] CreateTopicRequest request,
        CancellationToken ct)
    {
        var created = await taxonomy.CreateTopicAsync(UserId, request, ct);
        return Created($"/api/v1/admin/topics/{created.CategoryId}", created);
    }

    [HttpPut("topics/{categoryId:guid}"), RequirePermission(AdminPermissions.TaxonomyManage)]
    public Task<AdminTopicResponse> UpdateTopicAsync(
        Guid categoryId,
        [FromBody] UpdateTopicRequest request,
        CancellationToken ct) =>
        taxonomy.UpdateTopicAsync(UserId, categoryId, request, ct);

    [HttpPost("topics/{categoryId:guid}/archive"), RequirePermission(AdminPermissions.TaxonomyManage)]
    public async Task<IActionResult> ArchiveTopicAsync(Guid categoryId, CancellationToken ct)
    {
        await taxonomy.ArchiveTopicAsync(UserId, categoryId, ct);
        return NoContent();
    }

    [HttpGet("tags"), RequirePermission(AdminPermissions.SystemViewSetting)]
    public Task<List<AdminTagResponse>> GetTagsAsync(
        [FromQuery] string? search = null,
        CancellationToken ct = default) =>
        taxonomy.GetTagsAsync(search, ct);

    [HttpPost("tags"), RequirePermission(AdminPermissions.TaxonomyManage)]
    public async Task<ActionResult<AdminTagResponse>> CreateTagAsync(
        [FromBody] CreateTagRequest request,
        CancellationToken ct)
    {
        var created = await taxonomy.CreateTagAsync(UserId, request, ct);
        return Created($"/api/v1/admin/tags/{created.TagId}", created);
    }

    [HttpPut("tags/{tagId:guid}"), RequirePermission(AdminPermissions.TaxonomyManage)]
    public Task<AdminTagResponse> UpdateTagAsync(
        Guid tagId,
        [FromBody] UpdateTagRequest request,
        CancellationToken ct) =>
        taxonomy.UpdateTagAsync(UserId, tagId, request, ct);

    [HttpDelete("tags/{tagId:guid}"), RequirePermission(AdminPermissions.TaxonomyManage)]
    public async Task<IActionResult> DeleteTagAsync(Guid tagId, CancellationToken ct)
    {
        await taxonomy.DeleteTagAsync(UserId, tagId, ct);
        return NoContent();
    }

    [HttpGet("audit-logs"), RequirePermission(AdminPermissions.AuditView)]
    public Task<List<AuditLogResponse>> GetAuditLogsAsync(CancellationToken ct) =>
        rbac.GetAuditLogsAsync(50, ct);

    // ================= SPRINT 6: MODERATION REPORTS =================

    [HttpGet("reports"), RequirePermission(AdminPermissions.ReportView)]
    public Task<List<ReportDto>> GetReportsQueueAsync(
        [FromQuery] string? targetType = null,
        [FromQuery] string? status = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken ct = default) =>
        reportService.GetReportsQueueAsync(targetType, status, page, pageSize, ct);

    [HttpPost("reports/{reportId:guid}/claim"), RequirePermission(AdminPermissions.ReportResolve)]
    public async Task<IActionResult> ClaimReportAsync(Guid reportId, CancellationToken ct)
    {
        await reportService.ClaimReportAsync(UserId, reportId, ct);
        return NoContent();
    }

    [HttpPost("reports/{reportId:guid}/release"), RequirePermission(AdminPermissions.ReportResolve)]
    public async Task<IActionResult> ReleaseReportAsync(Guid reportId, CancellationToken ct)
    {
        await reportService.ReleaseReportAsync(UserId, reportId, ct);
        return NoContent();
    }

    [HttpPost("reports/{reportId:guid}/resolve"), RequirePermission(AdminPermissions.ReportResolve)]
    public Task<ReportResolutionResponse> ResolveReportAsync(
        Guid reportId,
        [FromBody] ResolveReportRequest request,
        CancellationToken ct) =>
        reportService.ResolveReportAsync(UserId, reportId, request, ct);

    // ================= SPRINT 6: APPEALS =================

    [HttpGet("appeals"), RequirePermission(AdminPermissions.AppealView)]
    public Task<List<AppealDto>> GetAdminAppealsAsync(
        [FromQuery] string? targetType = null,
        [FromQuery] string? status = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken ct = default) =>
        appealService.GetAdminAppealsAsync(targetType, status, page, pageSize, ct);

    [HttpPost("appeals/{appealId:guid}/claim"), RequirePermission(AdminPermissions.AppealResolve)]
    public async Task<IActionResult> ClaimAppealAsync(Guid appealId, CancellationToken ct)
    {
        await appealService.ClaimAppealAsync(UserId, appealId, ct);
        return NoContent();
    }

    [HttpPost("appeals/{appealId:guid}/release"), RequirePermission(AdminPermissions.AppealResolve)]
    public async Task<IActionResult> ReleaseAppealAsync(Guid appealId, CancellationToken ct)
    {
        await appealService.ReleaseAppealAsync(UserId, appealId, ct);
        return NoContent();
    }

    [HttpPost("appeals/{appealId:guid}/resolve"), RequirePermission(AdminPermissions.AppealResolve)]
    public Task<AppealResolutionResponse> ResolveAppealAsync(
        Guid appealId,
        [FromBody] ResolveAppealRequest request,
        CancellationToken ct) =>
        appealService.ResolveAppealAsync(UserId, appealId, request, ct);

    // ================= SPRINT 6: STRIKES =================

    [HttpGet("strikes"), RequirePermission(AdminPermissions.StrikeView)]
    public Task<List<ChannelStrikeDto>> GetAdminStrikesAsync(
        [FromQuery] Guid? channelId = null,
        [FromQuery] string? status = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken ct = default) =>
        strikeService.GetAdminStrikesAsync(channelId, status, page, pageSize, ct);

    [HttpPost("strikes"), RequirePermission(AdminPermissions.StrikeManage)]
    public async Task<ActionResult<ChannelStrikeDto>> CreateManualStrikeAsync(
        [FromBody] CreateStrikeRequest request,
        CancellationToken ct)
    {
        var created = await strikeService.CreateManualStrikeAsync(UserId, request, ct);
        return Created($"/api/v1/admin/strikes/{created.StrikeId}", created);
    }

    [HttpPost("strikes/{strikeId:guid}/revoke"), RequirePermission(AdminPermissions.StrikeManage)]
    public Task<ChannelStrikeDto> RevokeStrikeAsync(
        Guid strikeId,
        [FromBody] RevokeStrikeRequest request,
        CancellationToken ct) =>
        strikeService.RevokeStrikeAsync(UserId, strikeId, request, ct);

    // ================= SPRINT 6: CHANNEL LOCK / UNLOCK =================

    [HttpPost("channels/{channelId:guid}/lock"), RequirePermission(AdminPermissions.ChannelLock)]
    public async Task<IActionResult> LockChannelAsync(
        Guid channelId,
        [FromBody] LockChannelRequest request,
        CancellationToken ct)
    {
        await strikeService.SetChannelLockAsync(UserId, channelId, true, request.Reason, ct);
        return NoContent();
    }

    [HttpPost("channels/{channelId:guid}/unlock"), RequirePermission(AdminPermissions.ChannelLock)]
    public async Task<IActionResult> UnlockChannelAsync(
        Guid channelId,
        [FromBody] UnlockChannelRequest request,
        CancellationToken ct)
    {
        await strikeService.SetChannelLockAsync(UserId, channelId, false, request.Reason, ct);
        return NoContent();
    }
}
