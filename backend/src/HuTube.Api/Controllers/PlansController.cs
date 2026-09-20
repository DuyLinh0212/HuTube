using System.Security.Claims;
using HuTube.Application.Plans;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

[ApiController]
[Route("api/v1/plans")]
public sealed class PlansController(IPlanService planService) : ControllerBase
{
    private Guid UserId => Guid.TryParse(User.FindFirst("sub")?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value, out var id)
        ? id
        : throw new PlanException(401, "UNAUTHORIZED", "Vui lòng đăng nhập để tiếp tục.");

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<PlanResponse>>> GetPlansAsync(CancellationToken ct)
    {
        var result = await planService.GetPlansAsync(ct);
        return Ok(result);
    }

    [HttpGet("{planId:guid}")]
    public async Task<ActionResult<PlanResponse>> GetPlanByIdAsync(Guid planId, CancellationToken ct)
    {
        var result = await planService.GetPlanByIdAsync(planId, ct);
        return Ok(result);
    }

    [HttpGet("{planId:guid}/share")]
    public async Task<ActionResult<PlanShareResponse>> GetPlanShareAsync(Guid planId, CancellationToken ct)
    {
        var result = await planService.GetPlanShareAsync(planId, ct);
        return Ok(result);
    }

    [Authorize]
    [HttpGet("my-plan")]
    public async Task<ActionResult<PlanDetailResponse>> GetMyPlanAsync(CancellationToken ct)
    {
        var result = await planService.GetMyPlanAsync(UserId, ct);
        return Ok(result);
    }

    [Authorize]
    [HttpPost("{planId:guid}/subscribe")]
    public async Task<ActionResult<PlanResponse>> SubscribeAsync(Guid planId, [FromBody] PlanSubscriptionRequest request, CancellationToken ct)
    {
        var result = await planService.SubscribeAsync(UserId, planId, request, ct);
        return Ok(result);
    }

    [Authorize]
    [HttpPost("members/invite")]
    [HttpPost("my-subscription/members")]
    public async Task<ActionResult<PlanMemberResponse>> InviteMemberAsync([FromBody] PlanInviteRequest request, CancellationToken ct)
    {
        var result = await planService.InviteMemberAsync(UserId, request.Email, request.AllocatedStorage, ct);
        return Ok(result);
    }

    [Authorize]
    [HttpPost("members/{memberId:guid}/accept")]
    [HttpPost("invitations/{memberId:guid}/accept")]
    public async Task<ActionResult<PlanMemberResponse>> AcceptInvitationAsync(Guid memberId, [FromBody] PlanAcceptInvitationRequest request, CancellationToken ct)
    {
        var result = await planService.AcceptInvitationAsync(UserId, memberId, request.Token, ct);
        return Ok(result);
    }

    [Authorize]
    [HttpDelete("members/{memberId:guid}")]
    [HttpDelete("my-subscription/members/{memberId:guid}")]
    public async Task<IActionResult> RemoveMemberAsync(Guid memberId, CancellationToken ct)
    {
        await planService.RemoveMemberAsync(UserId, memberId, ct);
        return NoContent();
    }

    [Authorize]
    [HttpPatch("members/{memberId:guid}/storage")]
    [HttpPatch("my-subscription/members/{memberId:guid}/storage")]
    public async Task<ActionResult<PlanMemberResponse>> UpdateMemberStorageAsync(Guid memberId, [FromBody] UpdatePlanMemberStorageRequest request, CancellationToken ct)
    {
        var result = await planService.UpdateMemberStorageAsync(UserId, memberId, request.AllocatedStorage, ct);
        return Ok(result);
    }

    [Authorize]
    [HttpPatch("my-subscription/owner-storage")]
    public async Task<IActionResult> UpdateOwnerStorageAsync([FromBody] UpdateOwnerStorageRequest request, CancellationToken ct)
    {
        await planService.UpdateOwnerStorageAsync(UserId, request.AllocatedStorage, ct);
        return NoContent();
    }
}
