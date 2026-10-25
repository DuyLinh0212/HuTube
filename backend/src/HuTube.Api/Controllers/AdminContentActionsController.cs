using HuTube.Api.Authorization;
using HuTube.Application.Rbac;
using HuTube.Application.Videos;
using HuTube.Domain.Rbac;
using HuTube.Infrastructure.Videos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace HuTube.Api.Controllers;

[ApiController, Authorize, Route("api/v1/admin"), EnableRateLimiting("admin")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class AdminContentActionsController(AdminContentService content, StrikeService strikes, RbacService rbac) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirst("sub")!.Value);

    [HttpPut("channels/{channelId:guid}/metadata"), RequirePermission(AdminPermissions.ChannelEdit)]
    public async Task<IActionResult> EditChannelAsync(Guid channelId, UpdateAdminChannelRequest request, CancellationToken ct)
    {
        await content.UpdateChannelAsync(UserId, channelId, request, ct);
        return NoContent();
    }

    [HttpGet("channels/export"), RequirePermission(AdminPermissions.ChannelExport)]
    public Task<PageResult<AdminChannelListItem>> ExportChannelsAsync([FromQuery] string? search = null,
        [FromQuery] string? status = null, [FromQuery] string? sortBy = null, [FromQuery] bool? sortDescending = null,
        CancellationToken ct = default) => content.ExportAsync(page =>
            content.GetChannelsAsync(search, status, sortBy, sortDescending, page, 100, ct), ct);

    [HttpGet("videos/export"), RequirePermission(AdminPermissions.VideoExport)]
    public async Task<PageResult<AdminVideoListItem>> ExportVideosAsync([FromQuery] string? search = null,
        [FromQuery] string? status = null, [FromQuery] string? visibility = null, [FromQuery] Guid? categoryId = null,
        [FromQuery] string? timeRange = null, [FromQuery] DateTimeOffset? fromDate = null, [FromQuery] DateTimeOffset? toDate = null,
        [FromQuery] string? sortBy = null, [FromQuery] bool? sortDescending = null, [FromQuery] Guid? channelId = null,
        CancellationToken ct = default)
    {
        var includePrivate = await rbac.HasPermissionAsync(UserId, AdminPermissions.VideoViewPrivate, ct);
        return await content.ExportAsync(page => content.GetVideosAsync(search, status, visibility, categoryId, timeRange,
            fromDate, toDate, sortBy, sortDescending, channelId, includePrivate, page, 100, ct), ct);
    }

    [HttpGet("channels/{channelId:guid}/strikes"), RequirePermission(AdminPermissions.ChannelStrike, AdminPermissions.ChannelRemoveStrike)]
    public Task<List<ChannelStrikeDto>> GetChannelStrikesAsync(Guid channelId, CancellationToken ct) =>
        strikes.GetAdminStrikesAsync(channelId, "active", 1, 100, ct);

    [HttpPost("channels/{channelId:guid}/strikes"), RequirePermission(AdminPermissions.ChannelStrike)]
    public async Task<ActionResult<ChannelStrikeDto>> StrikeChannelAsync(Guid channelId, CreateTargetStrikeRequest request, CancellationToken ct)
    {
        var result = await strikes.CreateManualStrikeAsync(UserId,
            new CreateStrikeRequest(channelId, request.PolicyCode, request.Severity, request.Reason, request.InternalNote), ct);
        return Created($"/api/v1/admin/channels/{channelId}/strikes", result);
    }

    [HttpPost("channels/{channelId:guid}/strikes/{strikeId:guid}/revoke"), RequirePermission(AdminPermissions.ChannelRemoveStrike)]
    public Task<ChannelStrikeDto> RemoveChannelStrikeAsync(Guid channelId, Guid strikeId, RevokeStrikeRequest request, CancellationToken ct) =>
        strikes.RevokeChannelStrikeAsync(UserId, channelId, strikeId, request, ct);

    [HttpPost("videos/{videoId:guid}/strikes"), RequirePermission(AdminPermissions.VideoStrike)]
    public async Task<ActionResult<ChannelStrikeDto>> StrikeVideoAsync(Guid videoId, CreateTargetStrikeRequest request, CancellationToken ct)
    {
        var result = await strikes.CreateVideoStrikeAsync(UserId, videoId, request, ct);
        return Created($"/api/v1/admin/videos/{videoId}/strikes", result);
    }
}
