using HuTube.Api.Authorization;
using HuTube.Application.Plans;
using HuTube.Application.Policies;
using HuTube.Application.Rbac;
using HuTube.Application.Storage;
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
    AdminContentService adminContent,
    AppealService appealService,
    IObjectStorage storage) : ControllerBase
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

    [HttpDelete("roles/{roleId:guid}"), RequirePermission(AdminPermissions.RoleDelete)]
    public async Task<IActionResult> DeleteRoleAsync(Guid roleId, [FromQuery] string? reason, CancellationToken ct)
    {
        await rbac.DeleteRoleAsync(UserId, roleId, reason, ct);
        return NoContent();
    }

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

    [HttpPost("moderation/{caseId:guid}/resolve"), RequirePermission(AdminPermissions.ModerationReview, AdminPermissions.ModerationApprove, AdminPermissions.ModerationReject)]
    public async Task<ModerationDecisionResponse> ResolveCaseAsync(
        Guid caseId,
        [FromBody] ResolveModerationRequest request,
        CancellationToken ct)
    {
        var decision = request.Decision?.Trim().ToLowerInvariant();
        var permission = decision switch
        {
            "approve" or "age_restricted" or "recommendation_restricted" => AdminPermissions.ModerationApprove,
            "reject" => AdminPermissions.ModerationReject,
            _ => AdminPermissions.ModerationReview
        };
        if (!await rbac.HasPermissionAsync(UserId, permission, ct))
            throw new RbacException(403, "PERMISSION_DENIED", $"Bạn không có quyền '{permission}' để thực hiện quyết định này.");
        return await moderation.ResolveCaseAsync(UserId, caseId, request, ct);
    }

    // Keep the legacy endpoint routable so callers without moderation.approve
    // receive 403 instead of a misleading 404. Case-specific resolution above
    // remains the canonical moderation API.
    [HttpPost("moderation/approve"), RequirePermission(AdminPermissions.ModerationApprove)]
    public IActionResult LegacyApproveAsync() => BadRequest(new { code = "CASE_ID_REQUIRED" });

    [HttpGet("policies"), RequirePermission(AdminPermissions.SystemViewSetting, AdminPermissions.PolicyView, AdminPermissions.ModerationReview, AdminPermissions.ModerationViewQueue)]
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

    [HttpGet("topics"), RequirePermission(AdminPermissions.SystemViewSetting, AdminPermissions.TaxonomyManage, AdminPermissions.CfSeedManage)]
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

    [HttpGet("tags"), RequirePermission(AdminPermissions.SystemViewSetting, AdminPermissions.TaxonomyManage)]
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

    [HttpGet("channels"), RequirePermission(AdminPermissions.ChannelView)]
    public Task<PageResult<AdminChannelListItem>> GetAdminChannelsAsync([FromQuery] string? search = null, [FromQuery] string? status = null,
        [FromQuery] string? sortBy = null, [FromQuery] bool? sortDescending = null,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 25, CancellationToken ct = default) =>
        adminContent.GetChannelsAsync(search, status, sortBy, sortDescending, page, pageSize, ct);

    [HttpGet("channels/{channelId:guid}"), RequirePermission(AdminPermissions.ChannelView)]
    public Task<AdminChannelDetailResponse> GetAdminChannelAsync(Guid channelId, CancellationToken ct) => adminContent.GetChannelAsync(channelId, ct);

    [HttpPost("channels/{channelId:guid}/suspend"), RequirePermission(AdminPermissions.ChannelSuspend)]
    public async Task<IActionResult> SuspendChannelAsync(Guid channelId, [FromBody] AdminContentActionRequest request, CancellationToken ct)
    { await adminContent.ChangeChannelStatusAsync(UserId, channelId, "suspended", request, ct); return NoContent(); }

    [HttpPost("channels/{channelId:guid}/ban"), RequirePermission(AdminPermissions.ChannelBan)]
    public async Task<IActionResult> BanChannelAsync(Guid channelId, [FromBody] AdminContentActionRequest request, CancellationToken ct)
    { await adminContent.ChangeChannelStatusAsync(UserId, channelId, "banned", request, ct); return NoContent(); }

    [HttpPost("channels/{channelId:guid}/unban"), RequirePermission(AdminPermissions.ChannelUnban)]
    public async Task<IActionResult> UnbanChannelAsync(Guid channelId, [FromBody] AdminContentActionRequest request, CancellationToken ct)
    { await adminContent.ChangeChannelStatusAsync(UserId, channelId, "active", request, ct); return NoContent(); }

    [HttpDelete("channels/{channelId:guid}"), RequirePermission(AdminPermissions.ChannelDelete)]
    public async Task<IActionResult> DeleteChannelAsync(Guid channelId, [FromBody] AdminContentActionRequest request, CancellationToken ct)
    { await adminContent.ChangeChannelStatusAsync(UserId, channelId, "deleted", request, ct); return NoContent(); }

    [HttpPost("channels/{channelId:guid}/restore"), RequirePermission(AdminPermissions.ChannelDelete)]
    public async Task<IActionResult> RestoreChannelAsync(Guid channelId, [FromBody] AdminContentActionRequest request, CancellationToken ct)
    { await adminContent.ChangeChannelStatusAsync(UserId, channelId, "active", request, ct); return NoContent(); }

    [HttpGet("videos"), RequirePermission(AdminPermissions.VideoView)]
    public async Task<PageResult<AdminVideoListItem>> GetAdminVideosAsync([FromQuery] string? search = null, [FromQuery] string? status = null,
        [FromQuery] string? visibility = null, [FromQuery] Guid? categoryId = null, [FromQuery] string? timeRange = null,
        [FromQuery] DateTimeOffset? fromDate = null, [FromQuery] DateTimeOffset? toDate = null,
        [FromQuery] string? sortBy = null, [FromQuery] bool? sortDescending = null,
        [FromQuery] Guid? channelId = null, [FromQuery] int page = 1,
        [FromQuery] int pageSize = 25, CancellationToken ct = default)
    {
        var includePrivate = await rbac.HasPermissionAsync(UserId, AdminPermissions.VideoViewPrivate, ct);
        return await adminContent.GetVideosAsync(search, status, visibility, categoryId, timeRange, fromDate, toDate, sortBy, sortDescending, channelId, includePrivate, page, pageSize, ct);
    }

    [HttpGet("videos/statistics"), RequirePermission(AdminPermissions.VideoView)]
    public Task<AdminVideoStatisticsResponse> GetAdminVideoStatisticsAsync(CancellationToken ct) =>
        adminContent.GetVideoStatisticsAsync(ct);

    [HttpGet("videos/{videoId:guid}"), RequirePermission(AdminPermissions.VideoView)]
    public async Task<AdminVideoDetailResponse> GetAdminVideoAsync(Guid videoId, CancellationToken ct)
    {
        var includePrivate = await rbac.HasPermissionAsync(UserId, AdminPermissions.VideoViewPrivate, ct);
        return await adminContent.GetVideoAsync(videoId, includePrivate, ct);
    }

    [HttpPut("videos/{videoId:guid}/metadata"), RequirePermission(AdminPermissions.VideoEditMetadata)]
    public async Task<IActionResult> UpdateAdminVideoAsync(Guid videoId, [FromBody] UpdateAdminVideoRequest request, CancellationToken ct)
    { await adminContent.UpdateVideoAsync(UserId, videoId, request, ct); return NoContent(); }

    [HttpPost("videos/{videoId:guid}/hide"), RequirePermission(AdminPermissions.VideoHide)]
    public async Task<IActionResult> HideAdminVideoAsync(Guid videoId, [FromBody] AdminContentActionRequest request, CancellationToken ct)
    { await adminContent.ChangeVideoStatusAsync(UserId, videoId, "hide", request, ct); return NoContent(); }

    [HttpPost("videos/{videoId:guid}/unhide"), RequirePermission(AdminPermissions.VideoUnhide)]
    public async Task<IActionResult> UnhideAdminVideoAsync(Guid videoId, [FromBody] AdminContentActionRequest request, CancellationToken ct)
    { await adminContent.ChangeVideoStatusAsync(UserId, videoId, "unhide", request, ct); return NoContent(); }

    [HttpPost("videos/{videoId:guid}/remove"), RequirePermission(AdminPermissions.VideoRemove)]
    public async Task<IActionResult> RemoveAdminVideoAsync(Guid videoId, [FromBody] AdminContentActionRequest request, CancellationToken ct)
    { await adminContent.ChangeVideoStatusAsync(UserId, videoId, "remove", request, ct); return NoContent(); }

    [HttpPost("videos/{videoId:guid}/restore"), RequirePermission(AdminPermissions.VideoRestore)]
    public async Task<IActionResult> RestoreAdminVideoAsync(Guid videoId, [FromBody] AdminContentActionRequest request, CancellationToken ct)
    { await adminContent.ChangeVideoStatusAsync(UserId, videoId, "restore", request, ct); return NoContent(); }

    // ================= SPRINT 6: MODERATION REPORTS =================

    [HttpGet("reports"), RequirePermission(AdminPermissions.ReportView)]
    public Task<List<ReportDto>> GetReportsQueueAsync(
        [FromQuery] string? targetType = null,
        [FromQuery] string? status = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken ct = default) =>
        reportService.GetReportsQueueAsync(targetType, status, page, pageSize, ct);

    [HttpGet("reports/cases"), RequirePermission(AdminPermissions.ReportView)]
    public Task<PageResult<ReportCaseSummary>> GetReportCasesAsync(
        [FromQuery] string? targetType = null, [FromQuery] string? status = null,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 50, CancellationToken ct = default) =>
        reportService.GetReportCasesAsync(targetType, status, page, pageSize, ct);

    [HttpGet("reports/cases/{caseId:guid}"), RequirePermission(AdminPermissions.ReportView)]
    public Task<ReportCaseDetail> GetReportCaseAsync(Guid caseId, CancellationToken ct) => reportService.GetReportCaseAsync(caseId, ct);

    [HttpPost("reports/cases/{caseId:guid}/claim"), RequirePermission(AdminPermissions.ReportClaim)]
    public async Task<IActionResult> ClaimReportCaseAsync(Guid caseId, CancellationToken ct)
    {
        await reportService.ClaimReportCaseAsync(UserId, caseId, ct);
        return NoContent();
    }

    [HttpPost("reports/cases/{caseId:guid}/release"), RequirePermission(AdminPermissions.ReportClaim)]
    public async Task<IActionResult> ReleaseReportCaseAsync(Guid caseId, CancellationToken ct)
    {
        await reportService.ReleaseReportCaseAsync(UserId, caseId, ct);
        return NoContent();
    }

    [HttpPost("reports/cases/{caseId:guid}/dispositions"), RequirePermission(AdminPermissions.ReportResolve)]
    public async Task<IActionResult> UpdateReportDispositionsAsync(Guid caseId, [FromBody] UpdateReportDispositionsRequest request, CancellationToken ct)
    {
        await reportService.UpdateReportDispositionsAsync(UserId, caseId, request, ct);
        return NoContent();
    }

    [HttpPost("reports/cases/{caseId:guid}/resolve"), RequirePermission(AdminPermissions.ReportResolve)]
    public async Task<ActionResult<ReportResolutionResponse>> ResolveReportCaseAsync(Guid caseId, [FromBody] ResolveReportCaseRequest request, CancellationToken ct)
    {
        var decision = request.Decision?.Trim();
        if ((string.Equals(decision, "upload_restriction", StringComparison.OrdinalIgnoreCase)
            || string.Equals(decision, "strike", StringComparison.OrdinalIgnoreCase))
            && !await rbac.HasPermissionAsync(UserId, AdminPermissions.StrikeManage, ct)) return Forbid();
        if (string.Equals(decision, "lock_channel", StringComparison.OrdinalIgnoreCase)
            && !await rbac.HasPermissionAsync(UserId, AdminPermissions.ChannelLock, ct)) return Forbid();
        return Ok(await reportService.ResolveReportCaseAsync(UserId, caseId, request, ct));
    }

    [HttpPost("reports/{reportId:guid}/claim"), RequirePermission(AdminPermissions.ReportClaim)]
    public async Task<IActionResult> ClaimReportAsync(Guid reportId, CancellationToken ct)
    {
        await reportService.ClaimReportAsync(UserId, reportId, ct);
        return NoContent();
    }

    [HttpPost("reports/{reportId:guid}/release"), RequirePermission(AdminPermissions.ReportClaim)]
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

    [HttpGet("appeals/{appealId:guid}/evidence"), RequirePermission(AdminPermissions.AppealView)]
    public async Task<IActionResult> GetAdminAppealEvidenceAsync(Guid appealId, CancellationToken ct)
    {
        var path = await appealService.GetEvidenceStoragePathAsync(UserId, appealId, true, ct);
        if (path.StartsWith("r2://", StringComparison.OrdinalIgnoreCase))
            return Redirect(await storage.GetReadUrlAsync(path, TimeSpan.FromMinutes(10), ct));
        var stream = await storage.OpenReadAsync(path, ct);
        var contentType = Path.GetExtension(path).ToLowerInvariant() switch
        {
            ".png" => "image/png", ".jpg" or ".jpeg" => "image/jpeg", ".webp" => "image/webp", ".pdf" => "application/pdf", _ => "application/octet-stream"
        };
        return File(stream, contentType, enableRangeProcessing: false);
    }

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
