using HuTube.Application.Auth;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace HuTube.Api.Controllers;

[ApiController, Authorize, Route("api/v1/auth/session/player-preferences")]
[EnableRateLimiting("feed"), ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class SessionPlayerPreferencesController(AuthService auth) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirst("sub")!.Value);
    private Guid SessionId => Guid.Parse(User.FindFirst("sid")!.Value);

    [HttpGet]
    public Task<SessionPlayerPreferences> GetAsync(CancellationToken ct) => auth.GetPlayerPreferencesAsync(UserId, SessionId, ct);

    [HttpPut]
    public Task<SessionPlayerPreferences> UpdateAsync(UpdateSessionPlayerPreferencesRequest request, CancellationToken ct) =>
        auth.UpdatePlayerPreferencesAsync(UserId, SessionId, request, ct);
}
