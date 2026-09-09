using System.Security.Claims;
using HuTube.Application.Account;
using HuTube.Application.Auth;
using HuTube.Application.Storage;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

[ApiController, Route("api/v1/account"), Authorize]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class AccountController(
    IAccountService accountService,
    IObjectStorage storage) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirst("sub")?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value
        ?? throw new AuthException(401, "UNAUTHORIZED", "Vui lòng đăng nhập để tiếp tục."));

    [HttpGet("profile")]
    public Task<UserProfileDto> GetProfileAsync(CancellationToken ct) =>
        accountService.GetProfileAsync(UserId, ct);

    [HttpPatch("profile")]
    public Task<UserProfileDto> UpdateProfileAsync([FromBody] UpdateProfileRequest request, CancellationToken ct) =>
        accountService.UpdateProfileAsync(UserId, request, ct);

    [HttpPost("change-password")]
    public async Task<ActionResult<MessageResponse>> ChangePasswordAsync([FromBody] ChangePasswordRequest request, CancellationToken ct)
    {
        await accountService.ChangePasswordAsync(UserId, request, ct);
        return Ok(new MessageResponse("Đổi mật khẩu thành công. Vui lòng sử dụng mật khẩu mới cho các lần đăng nhập tiếp theo."));
    }

    [HttpGet("notifications")]
    public Task<NotificationSettingsDto> GetNotificationsAsync(CancellationToken ct) =>
        accountService.GetNotificationSettingsAsync(UserId, ct);

    [HttpPut("notifications")]
    public Task<NotificationSettingsDto> UpdateNotificationsAsync([FromBody] UpdateNotificationSettingsRequest request, CancellationToken ct) =>
        accountService.UpdateNotificationSettingsAsync(UserId, request, ct);

    [HttpGet("settings")]
    public Task<UserPreferencesDto> GetPreferencesAsync(CancellationToken ct) =>
        accountService.GetPreferencesAsync(UserId, ct);

    [HttpPut("settings")]
    public Task<UserPreferencesDto> UpdatePreferencesAsync([FromBody] UpdateUserPreferencesRequest request, CancellationToken ct) =>
        accountService.UpdatePreferencesAsync(UserId, request, ct);

    [HttpPost("avatar")]
    [RequestSizeLimit(5 * 1024 * 1024)] // 5MB limit
    public async Task<ActionResult<UserProfileDto>> UploadAvatarAsync(IFormFile? file, CancellationToken ct)
    {
        if (file == null || file.Length == 0)
            throw new AuthException(400, "INVALID_FILE", "Vui lòng chọn file hình ảnh đại diện.");

        if (file.Length > 5 * 1024 * 1024)
            throw new AuthException(400, "FILE_TOO_LARGE", "Kích thước ảnh tối đa là 5MB.");

        var allowedContentTypes = new[] { "image/jpeg", "image/png", "image/webp", "image/gif" };
        if (!allowedContentTypes.Contains(file.ContentType.ToLowerInvariant()))
            throw new AuthException(400, "INVALID_FILE_TYPE", "Chỉ hỗ trợ định dạng JPG, PNG, WEBP hoặc GIF.");

        await using var stream = file.OpenReadStream();
        var avatarUrl = await storage.SaveFileAsync("avatars", file.FileName, stream, file.ContentType, ct);

        var updated = await accountService.UpdateProfileAsync(UserId, new UpdateProfileRequest(null, null, avatarUrl), ct);
        return Ok(updated);
    }
}
