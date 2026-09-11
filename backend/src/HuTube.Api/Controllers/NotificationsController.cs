using System.Security.Claims;
using HuTube.Application.Auth;
using HuTube.Application.Notifications;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

[ApiController, Authorize, Route("api/v1/notifications")]
public sealed class NotificationsController(INotificationService notifications) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirst("sub")?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value
        ?? throw new AuthException(401, "UNAUTHORIZED", "Vui lòng đăng nhập để tiếp tục."));

    [HttpGet]
    public Task<NotificationPage> GetAsync([FromQuery] int page = 1, [FromQuery] int pageSize = 5, CancellationToken ct = default) =>
        notifications.GetAsync(UserId, page, pageSize, ct);

    [HttpPatch("{id:guid}/read")]
    public async Task<IActionResult> ReadAsync(Guid id, CancellationToken ct) { await notifications.MarkReadAsync(UserId, id, ct); return NoContent(); }

    [HttpPost("read-all")]
    public async Task<IActionResult> ReadAllAsync(CancellationToken ct) { await notifications.MarkAllReadAsync(UserId, ct); return NoContent(); }
}
