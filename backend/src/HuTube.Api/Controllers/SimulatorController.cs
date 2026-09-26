using HuTube.Application.CfSeeding;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

[ApiController]
[Route("api/v1/simulator")]
public sealed class SimulatorController(ICfSeederService seeder) : ControllerBase
{
    [HttpPost("viewers")]
    public Task<IReadOnlyList<CfSeedViewerAccountResponse>> CreateViewersAsync(
        [FromBody] CreateCfSeedViewersRequest request, CancellationToken ct) =>
        seeder.CreateViewerAccountsAsync(request, ct);

    [HttpGet("users")]
    public Task<IReadOnlyList<CfSeedViewerAccountResponse>> GetUsersAsync(
        [FromQuery] string? search, [FromQuery] int limit = 100, CancellationToken ct = default) =>
        seeder.GetViewerAccountsAsync(search, limit, ct);
}
