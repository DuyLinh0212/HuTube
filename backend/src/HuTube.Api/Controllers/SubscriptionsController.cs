using System.Security.Claims;
using HuTube.Application.Channels;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

[ApiController, Route("api/v1/subscriptions")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class SubscriptionsController(ChannelService channelService) : ControllerBase
{
    private Guid UserId
    {
        get
        {
            var subject = User.FindFirst("sub")?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (Guid.TryParse(subject, out var userId)) return userId;
            throw new ChannelException(401, "UNAUTHORIZED", "Vui lòng đăng nhập để tiếp tục.");
        }
    }

    [Authorize, HttpGet]
    public async Task<ActionResult<IReadOnlyList<SubscribedChannelResponse>>> GetSubscribedChannelsAsync(CancellationToken ct)
    {
        var result = await channelService.GetSubscribedChannelsAsync(UserId, ct);
        return Ok(result);
    }
}
