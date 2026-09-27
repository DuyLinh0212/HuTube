using HuTube.Api.Authorization;
using HuTube.Infrastructure.Recommendations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

[ApiController, Authorize, RequireSuperAdmin]
[Route("api/v1/admin/recommendations")]
public sealed class RecommendationAdminController(RecommendationAdminService admin) : ControllerBase
{
    private Guid ActorId => Guid.Parse(User.FindFirst("sub")!.Value);

    [HttpGet("status")]
    public Task<MatrixDiffResponse> StatusAsync(CancellationToken ct) => admin.DiffAsync(ct);

    [HttpGet("matrix.csv")]
    public async Task<IActionResult> MatrixAsync(CancellationToken ct) =>
        File(await admin.ExportMatrixAsync(ct), "text/csv; charset=utf-8", "interactions_current.csv");

    [HttpGet("matrix-preview")]
    public Task<MatrixPreviewResponse> MatrixPreviewAsync(CancellationToken ct) => admin.PreviewMatrixAsync(ct);

    [HttpPost("model-jobs")]
    public async Task<IActionResult> UpdateModelAsync(CancellationToken ct)
    {
        var job = await admin.QueueModelAsync(ActorId, ct);
        return Accepted($"/api/v1/admin/recommendations/jobs/{job.JobId}", new { jobId = job.JobId });
    }

    [HttpGet("jobs/{jobId:guid}")]
    public Task<HuTube.Domain.Videos.RecommendationJob> GetJobAsync(Guid jobId, CancellationToken ct) => admin.JobAsync(jobId, ct);

    [HttpGet("users")]
    public Task<IReadOnlyList<AdminUserOption>> UsersAsync([FromQuery] string? search, CancellationToken ct) => admin.UsersAsync(search, ct);

    [HttpGet("videos")]
    public Task<IReadOnlyList<AdminVideoOption>> VideosAsync([FromQuery] string? search, CancellationToken ct) => admin.VideosAsync(search, ct);

    [HttpPost("bots")]
    public Task<IReadOnlyList<AdminUserOption>> BotsAsync([FromBody] CreateBotsRequest request, CancellationToken ct) => admin.CreateBotsAsync(ActorId, request, ct);

    [HttpPost("simulation-jobs")]
    public async Task<IActionResult> SimulateAsync([FromBody] SimulatorRequest request, CancellationToken ct)
    {
        var job = await admin.QueueSimulatorAsync(ActorId, request, ct);
        return Accepted($"/api/v1/admin/recommendations/jobs/{job.JobId}", new { jobId = job.JobId });
    }

    [HttpPost("jobs/{jobId:guid}/stop")]
    public async Task<IActionResult> StopAsync(Guid jobId, CancellationToken ct)
    {
        await admin.StopAsync(jobId, ct);
        return Accepted($"/api/v1/admin/recommendations/jobs/{jobId}", new { jobId });
    }
}
