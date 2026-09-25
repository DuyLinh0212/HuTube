using System.Security.Claims;
using HuTube.Application.Auth;
using HuTube.Application.Channels;
using HuTube.Application.Storage;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

[ApiController, Route("api/v1/channels")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class ChannelController(ChannelService channelService, IObjectStorage storage) : ControllerBase
{
    private Guid? CurrentUserId
    {
        get
        {
            var subject = User.FindFirst("sub")?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            return Guid.TryParse(subject, out var userId) ? userId : null;
        }
    }

    private Guid UserId => CurrentUserId
        ?? throw new ChannelException(401, "UNAUTHORIZED", "Vui lòng đăng nhập để tiếp tục.");

    [Authorize, HttpPost]
    public async Task<ActionResult<ChannelResponse>> CreateAsync(CreateChannelRequest request, CancellationToken ct)
    {
        var result = await channelService.CreateChannelAsync(UserId, request, ct);
        return StatusCode(StatusCodes.Status201Created, result);
    }

    [Authorize, HttpGet("me")]
    public async Task<ActionResult<ChannelResponse>> GetMyChannelAsync(CancellationToken ct)
    {
        var channel = await channelService.GetMyChannelAsync(UserId, ct);
        return channel == null
            ? NotFound(new { code = "CHANNEL_NOT_FOUND", message = "Bạn chưa tạo kênh nào." })
            : Ok(channel);
    }

    [Authorize, HttpGet("accessible")]
    public async Task<ActionResult<IReadOnlyList<ChannelResponse>>> GetAccessibleChannelsAsync(CancellationToken ct) =>
        Ok(await channelService.GetAccessibleChannelsAsync(UserId, ct));

    [Authorize, HttpGet("roles")]
    public ActionResult<IReadOnlyList<ChannelRoleResponse>> GetRoles() => Ok(ChannelService.Roles);

    [HttpGet("check-handle")]
    public Task<CheckHandleResponse> CheckHandleAsync([FromQuery] string handle, [FromQuery] Guid? currentChannelId, CancellationToken ct) =>
        channelService.CheckHandleAsync(handle, currentChannelId, ct);

    [HttpGet("{id:guid}")]
    public Task<ChannelResponse> GetByIdAsync(Guid id, CancellationToken ct) =>
        channelService.GetChannelAsync(id, CurrentUserId, ct);

    [HttpGet("handle/{handle}")]
    public Task<ChannelResponse> GetByHandleAsync(string handle, CancellationToken ct) =>
        channelService.GetChannelByHandleAsync(handle, CurrentUserId, ct);

    [Authorize, HttpPatch("{id:guid}")]
    public Task<ChannelResponse> UpdateAsync(Guid id, UpdateChannelRequest request, CancellationToken ct) =>
        channelService.UpdateChannelAsync(id, UserId, request, ct);

    [Authorize, HttpDelete("{id:guid}")]
    public async Task<IActionResult> DeleteAsync(Guid id, CancellationToken ct)
    {
        await channelService.DeleteChannelAsync(id, UserId, ct);
        return NoContent();
    }

    [Authorize, HttpPost("{id:guid}/avatar")]
    [RequestSizeLimit(5 * 1024 * 1024)]
    public Task<ActionResult<ChannelResponse>> UploadAvatarAsync(Guid id, IFormFile? file, CancellationToken ct) =>
        UploadImageAsync(id, file, "channel-avatars", 5 * 1024 * 1024, true, ct);

    [Authorize, HttpPost("{id:guid}/banner")]
    [RequestSizeLimit(10 * 1024 * 1024)]
    public Task<ActionResult<ChannelResponse>> UploadBannerAsync(Guid id, IFormFile? file, CancellationToken ct) =>
        UploadImageAsync(id, file, "channel-banners", 10 * 1024 * 1024, false, ct);

    [Authorize, HttpPost("{id:guid}/watermark")]
    [RequestSizeLimit(2 * 1024 * 1024)]
    public async Task<ActionResult<ChannelResponse>> UploadWatermarkAsync(Guid id, IFormFile? file, CancellationToken ct)
    {
        await channelService.EnsureBrandingPermissionAsync(id, UserId, ct);
        if (file == null || file.Length == 0) throw new ChannelException(400, "INVALID_FILE", "Vui lòng chọn file watermark.");
        if (file.Length > 2 * 1024 * 1024) throw new ChannelException(400, "FILE_TOO_LARGE", "Watermark tối đa 2 MiB.");
        var allowed = new HashSet<string>(["image/jpeg", "image/png", "image/webp"], StringComparer.OrdinalIgnoreCase);
        if (!allowed.Contains(file.ContentType)) throw new ChannelException(400, "INVALID_FILE_TYPE", "Watermark chỉ hỗ trợ JPG, PNG hoặc WEBP.");
        await using var stream = file.OpenReadStream();
        var imageUrl = await storage.SaveFileAsync("channel-watermarks", file.FileName, stream, file.ContentType, ct);
        return Ok(await channelService.UpdateChannelAsync(id, UserId,
            new UpdateChannelRequest(null, null, null, null, WatermarkUrl: imageUrl), ct));
    }

    [Authorize, HttpPost("{id:guid}/members/invite")]
    public async Task<ActionResult<ChannelInvitationResponse>> InviteMemberAsync(Guid id, InviteMemberRequest request, CancellationToken ct)
    {
        var result = await channelService.InviteMemberAsync(id, UserId, request, ct);
        return StatusCode(StatusCodes.Status201Created, result);
    }

    [Authorize, HttpGet("{id:guid}/invitations")]
    public Task<List<ChannelInvitationResponse>> GetPendingInvitationsAsync(Guid id, CancellationToken ct) =>
        channelService.GetPendingInvitationsAsync(id, UserId, ct);

    [Authorize, HttpDelete("{id:guid}/invitations/{invitationId:guid}")]
    public async Task<IActionResult> RevokeInvitationAsync(Guid id, Guid invitationId, CancellationToken ct)
    {
        await channelService.RevokeInvitationAsync(id, invitationId, UserId, ct);
        return NoContent();
    }

    [Authorize, HttpGet("invitations/me")]
    public Task<List<ChannelInvitationResponse>> GetMyInvitationsAsync(CancellationToken ct) =>
        channelService.GetMyInvitationsAsync(UserId, ct);

    [Authorize, HttpPost("invitations/{invitationId:guid}/accept")]
    public Task<ChannelMemberResponse> AcceptInvitationAsync(Guid invitationId, CancellationToken ct) =>
        channelService.AcceptInvitationAsync(invitationId, UserId, ct);

    [Authorize, HttpPost("invitations/{invitationId:guid}/decline")]
    public async Task<IActionResult> DeclineInvitationAsync(Guid invitationId, CancellationToken ct)
    {
        await channelService.DeclineInvitationAsync(invitationId, UserId, ct);
        return NoContent();
    }

    [Authorize, HttpGet("{id:guid}/members")]
    public Task<List<ChannelMemberResponse>> GetMembersAsync(Guid id, CancellationToken ct) =>
        channelService.GetMembersAsync(id, UserId, ct);

    [Authorize, HttpPatch("{id:guid}/members/{targetUserId:guid}/role")]
    public Task<ChannelMemberResponse> ChangeMemberRoleAsync(Guid id, Guid targetUserId, ChangeMemberRoleRequest request, CancellationToken ct) =>
        channelService.ChangeMemberRoleAsync(id, targetUserId, UserId, request, ct);

    [Authorize, HttpDelete("{id:guid}/members/{targetUserId:guid}")]
    public async Task<IActionResult> RemoveMemberAsync(Guid id, Guid targetUserId, CancellationToken ct)
    {
        await channelService.RemoveMemberAsync(id, targetUserId, UserId, ct);
        return NoContent();
    }

    [Authorize, HttpPost("{id:guid}/subscribe")]
    public async Task<ActionResult<SubscriptionResponse>> SubscribeAsync(Guid id, CancellationToken ct)
    {
        var result = await channelService.SubscribeAsync(id, UserId, ct);
        return Ok(result);
    }

    [Authorize, HttpDelete("{id:guid}/subscribe")]
    public async Task<IActionResult> UnsubscribeAsync(Guid id, CancellationToken ct)
    {
        await channelService.UnsubscribeAsync(id, UserId, ct);
        return NoContent();
    }

    [Authorize, HttpGet("{id:guid}/subscribe-status")]
    public async Task<ActionResult<SubscriptionResponse>> GetSubscriptionStatusAsync(Guid id, CancellationToken ct)
    {
        var result = await channelService.GetSubscriptionStatusAsync(id, UserId, ct);
        if (result == null) return NotFound(new { code = "NOT_SUBSCRIBED", message = "Chưa đăng ký kênh này." });
        return Ok(result);
    }

    [Authorize, HttpPatch("{id:guid}/subscribe-notifications")]
    public Task<SubscriptionResponse> UpdateSubscriptionNotificationsAsync(
        Guid id, UpdateSubscriptionNotificationsRequest request, CancellationToken ct) =>
        channelService.UpdateSubscriptionNotificationsAsync(id, UserId, request.Enabled, ct);

    private async Task<ActionResult<ChannelResponse>> UploadImageAsync(
        Guid channelId,
        IFormFile? file,
        string folder,
        long maximumBytes,
        bool avatar,
        CancellationToken ct)
    {
        // Authorize before touching external storage so an unauthorized account cannot
        // consume Cloudinary quota even though the subsequent channel update is denied.
        await channelService.EnsureBrandingPermissionAsync(channelId, UserId, ct);

        if (file == null || file.Length == 0)
            throw new ChannelException(400, "INVALID_FILE", "Vui lòng chọn một file hình ảnh.");
        if (file.Length > maximumBytes)
            throw new ChannelException(400, "FILE_TOO_LARGE", $"Kích thước ảnh tối đa là {maximumBytes / 1024 / 1024}MB.");

        var allowed = avatar
            ? new HashSet<string>(["image/jpeg", "image/png", "image/webp", "image/gif"], StringComparer.OrdinalIgnoreCase)
            : new HashSet<string>(["image/jpeg", "image/png", "image/webp"], StringComparer.OrdinalIgnoreCase);
        if (!allowed.Contains(file.ContentType))
            throw new ChannelException(400, "INVALID_FILE_TYPE", "Chỉ hỗ trợ hình ảnh JPG, PNG, WEBP" + (avatar ? " hoặc GIF." : "."));

        await using var stream = file.OpenReadStream();
        var imageUrl = await storage.SaveFileAsync(folder, file.FileName, stream, file.ContentType, ct);
        var update = avatar
            ? new UpdateChannelRequest(null, null, imageUrl, null)
            : new UpdateChannelRequest(null, null, null, imageUrl);
        return Ok(await channelService.UpdateChannelAsync(channelId, UserId, update, ct));
    }
}
