using System.Security.Claims;
using HuTube.Application.Auth;
using HuTube.Application.Notifications;
using HuTube.Infrastructure.Notifications;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

[ApiController, Authorize, Route("api/v1/notifications")]
public sealed class NotificationsController(INotificationService notifications, PushDeviceService devices) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirst("sub")?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value
        ?? throw new AuthException(401, "UNAUTHORIZED", "Vui lòng đăng nhập để tiếp tục."));
    private Guid SessionId => Guid.TryParse(User.FindFirst("sid")?.Value, out var sessionId) ? sessionId
        : throw new AuthException(401, "UNAUTHORIZED", "Phiên đăng nhập không hợp lệ.");

    [HttpPut("devices")]
    public async Task<IActionResult> RegisterDeviceAsync(RegisterPushDeviceRequest request, CancellationToken ct)
    { await devices.RegisterAsync(UserId, SessionId, request, ct); return NoContent(); }

    [HttpDelete("devices")]
    public async Task<IActionResult> RemoveDeviceAsync([FromBody] RemovePushDeviceRequest request, CancellationToken ct)
    { await devices.RemoveAsync(UserId, SessionId, request.Token, ct); return NoContent(); }

    [HttpGet]
    public Task<NotificationPage> GetAsync([FromQuery] int page = 1, [FromQuery] int pageSize = 5, CancellationToken ct = default) =>
        notifications.GetAsync(UserId, page, pageSize, ct);

    [HttpPatch("{id:guid}/read")]
    public async Task<IActionResult> ReadAsync(Guid id, CancellationToken ct) { await notifications.MarkReadAsync(UserId, id, ct); return NoContent(); }

    [HttpPost("read-all")]
    public async Task<IActionResult> ReadAllAsync(CancellationToken ct) { await notifications.MarkAllReadAsync(UserId, ct); return NoContent(); }
}
