using System.Security.Claims;
using HuTube.Application.Auth;
using HuTube.Application.Channels;
using HuTube.Application.Storage;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

[ApiController, Route("api/v1/channels")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class ChannelsController(
    IChannelService channelService,
    IObjectStorage storage) : ControllerBase
{
    private Guid? CurrentUserId
    {
        get
        {
            var sub = User.FindFirst("sub")?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            return Guid.TryParse(sub, out var id) ? id : null;
        }
    }

    private Guid RequireUserId => CurrentUserId
        ?? throw new AuthException(401, "UNAUTHORIZED", "Vui lòng đăng nhập để tiếp tục.");

    [HttpPost, Authorize]
    public async Task<ActionResult<ChannelDto>> CreateChannelAsync([FromBody] CreateChannelRequest request, CancellationToken ct)
    {
        var channel = await channelService.CreateChannelAsync(RequireUserId, request, ct);
        return StatusCode(201, channel);
    }

    [HttpGet("me"), Authorize]
    public async Task<ActionResult<ChannelDetailDto>> GetMyChannelAsync(CancellationToken ct)
    {
        var channel = await channelService.GetMyChannelAsync(RequireUserId, ct);
        if (channel == null) return NotFound(new { code = "CHANNEL_NOT_FOUND", message = "Bạn chưa tạo kênh nào." });
        return Ok(channel);
    }

    [HttpGet("check-handle"), AllowAnonymous]
    public Task<CheckHandleResponse> CheckHandleAsync([FromQuery] string handle, [FromQuery] Guid? currentChannelId, CancellationToken ct) =>
        channelService.CheckHandleAsync(handle, currentChannelId, ct);

    [HttpGet("{handle}"), AllowAnonymous]
    public Task<ChannelDetailDto> GetChannelByHandleAsync(string handle, CancellationToken ct) =>
        channelService.GetChannelByHandleAsync(handle, CurrentUserId, ct);

    [HttpPatch("{id:guid}"), Authorize]
    public Task<ChannelDto> UpdateChannelAsync(Guid id, [FromBody] UpdateChannelRequest request, CancellationToken ct) =>
        channelService.UpdateChannelAsync(RequireUserId, id, request, ct);

    [HttpDelete("{id:guid}"), Authorize]
    public async Task<ActionResult<MessageResponse>> DeleteChannelAsync(Guid id, CancellationToken ct)
    {
        await channelService.DeleteChannelAsync(RequireUserId, id, ct);
        return Ok(new MessageResponse("Kênh đã được xóa thành công."));
    }

    [HttpPost("{id:guid}/avatar"), Authorize]
    [RequestSizeLimit(5 * 1024 * 1024)]
    public async Task<ActionResult<ChannelDto>> UploadAvatarAsync(Guid id, IFormFile? file, CancellationToken ct)
    {
        if (file == null || file.Length == 0)
            throw new AuthException(400, "INVALID_FILE", "Vui lòng chọn file hình ảnh đại diện.");

        var allowedContentTypes = new[] { "image/jpeg", "image/png", "image/webp", "image/gif" };
        if (!allowedContentTypes.Contains(file.ContentType.ToLowerInvariant()))
            throw new AuthException(400, "INVALID_FILE_TYPE", "Chỉ hỗ trợ định dạng JPG, PNG, WEBP hoặc GIF.");

        await using var stream = file.OpenReadStream();
        var avatarUrl = await storage.SaveFileAsync("channel-avatars", file.FileName, stream, file.ContentType, ct);

        var updated = await channelService.UpdateChannelAsync(RequireUserId, id, new UpdateChannelRequest(null, null, null, avatarUrl, null, null, null, null), ct);
        return Ok(updated);
    }

    [HttpPost("{id:guid}/banner"), Authorize]
    [RequestSizeLimit(10 * 1024 * 1024)] // 10MB limit for banners
    public async Task<ActionResult<ChannelDto>> UploadBannerAsync(Guid id, IFormFile? file, CancellationToken ct)
    {
        if (file == null || file.Length == 0)
            throw new AuthException(400, "INVALID_FILE", "Vui lòng chọn file hình ảnh bìa kênh.");

        var allowedContentTypes = new[] { "image/jpeg", "image/png", "image/webp" };
        if (!allowedContentTypes.Contains(file.ContentType.ToLowerInvariant()))
            throw new AuthException(400, "INVALID_FILE_TYPE", "Chỉ hỗ trợ định dạng JPG, PNG hoặc WEBP.");

        await using var stream = file.OpenReadStream();
        var bannerUrl = await storage.SaveFileAsync("channel-banners", file.FileName, stream, file.ContentType, ct);

        var updated = await channelService.UpdateChannelAsync(RequireUserId, id, new UpdateChannelRequest(null, null, null, null, bannerUrl, null, null, null), ct);
        return Ok(updated);
    }
}
