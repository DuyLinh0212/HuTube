using System.Security.Claims;
using HuTube.Application.Auth;
using HuTube.Application.Videos;
using HuTube.Infrastructure.Videos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

public sealed record ReportTargetRequest(Guid ViolationTypeId, string Description);

[ApiController, Route("api/v1"), Authorize]
public sealed class UserModerationController(
    ReportService reportService,
    AppealService appealService,
    StrikeService strikeService) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirst("sub")?.Value 
        ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value 
        ?? throw new AuthException(401, "UNAUTHORIZED", "Vui lòng đăng nhập để tiếp tục."));

    [HttpPost("reports")]
    public async Task<ActionResult<ReportDto>> CreateReportAsync([FromBody] CreateContentReportRequest request, CancellationToken ct)
    {
        var result = await reportService.CreateReportAsync(UserId, request, ct);
        return StatusCode(StatusCodes.Status201Created, result);
    }

    [HttpPost("videos/{id:guid}/report")]
    public async Task<ActionResult<ReportDto>> ReportVideoAsync(Guid id, [FromBody] ReportTargetRequest request, CancellationToken ct)
    {
        var result = await reportService.CreateReportAsync(UserId, new CreateContentReportRequest("video", id, request.ViolationTypeId, request.Description), ct);
        return StatusCode(StatusCodes.Status201Created, result);
    }

    [HttpPost("channels/{id:guid}/report")]
    public async Task<ActionResult<ReportDto>> ReportChannelAsync(Guid id, [FromBody] ReportTargetRequest request, CancellationToken ct)
    {
        var result = await reportService.CreateReportAsync(UserId, new CreateContentReportRequest("channel", id, request.ViolationTypeId, request.Description), ct);
        return StatusCode(StatusCodes.Status201Created, result);
    }

    [HttpPost("appeals")]
    public async Task<ActionResult<AppealDto>> CreateAppealAsync([FromBody] CreateAppealRequest request, CancellationToken ct)
    {
        var result = await appealService.CreateAppealAsync(UserId, request, ct);
        return StatusCode(StatusCodes.Status201Created, result);
    }

    [HttpGet("appeals/my")]
    public Task<List<AppealDto>> GetMyAppealsAsync(CancellationToken ct) =>
        appealService.GetMyAppealsAsync(UserId, ct);

    [HttpGet("channels/{channelId:guid}/strikes")]
    public Task<ChannelStrikeStatusResponse> GetChannelStrikesAsync(Guid channelId, CancellationToken ct) =>
        strikeService.GetChannelStrikeStatusAsync(channelId, ct);
}
