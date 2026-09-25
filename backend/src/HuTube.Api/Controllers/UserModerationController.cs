using System.Security.Claims;
using HuTube.Application.Auth;
using HuTube.Application.Storage;
using HuTube.Application.Videos;
using HuTube.Infrastructure.Videos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

public sealed record ReportTargetRequest(Guid ViolationTypeId, string Description);

[ApiController, Route("api/v1"), Authorize]
public sealed class UserModerationController(
    ReportService reportService,
    AppealService appealService,
    StrikeService strikeService,
    IObjectStorage storage) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirst("sub")?.Value 
        ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value 
        ?? throw new AuthException(401, "UNAUTHORIZED", "Vui lòng đăng nhập để tiếp tục."));

    [HttpPost("reports")]
    public async Task<ActionResult<ReportDto>> CreateReportAsync([FromBody] CreateContentReportRequest request,
        [FromHeader(Name = "Idempotency-Key")] string? idempotencyKey, CancellationToken ct)
    {
        var result = await reportService.CreateReportAsync(UserId, request with { IdempotencyKey = idempotencyKey ?? request.IdempotencyKey }, ct);
        return StatusCode(StatusCodes.Status201Created, result);
    }

    [HttpPost("videos/{id:guid}/report")]
    public async Task<ActionResult<ReportDto>> ReportVideoAsync(Guid id, [FromBody] ReportTargetRequest request,
        [FromHeader(Name = "Idempotency-Key")] string? idempotencyKey, CancellationToken ct)
    {
        var result = await reportService.CreateReportAsync(UserId, new CreateContentReportRequest("video", id, request.ViolationTypeId, request.Description, idempotencyKey), ct);
        return StatusCode(StatusCodes.Status201Created, result);
    }

    [HttpPost("channels/{id:guid}/report")]
    public async Task<ActionResult<ReportDto>> ReportChannelAsync(Guid id, [FromBody] ReportTargetRequest request,
        [FromHeader(Name = "Idempotency-Key")] string? idempotencyKey, CancellationToken ct)
    {
        var result = await reportService.CreateReportAsync(UserId, new CreateContentReportRequest("channel", id, request.ViolationTypeId, request.Description, idempotencyKey), ct);
        return StatusCode(StatusCodes.Status201Created, result);
    }

    [HttpPost("appeals")]
    public async Task<ActionResult<AppealDto>> CreateAppealAsync([FromBody] CreateAppealRequest request, CancellationToken ct)
    {
        var result = await appealService.CreateAppealAsync(UserId, request, ct);
        return StatusCode(StatusCodes.Status201Created, result);
    }

    [HttpPost("appeals/{appealId:guid}/evidence")]
    [RequestSizeLimit(10 * 1024 * 1024 + 65536)]
    public async Task<ActionResult<AppealEvidenceUploadResponse>> UploadAppealEvidenceAsync(Guid appealId, [FromForm] IFormFile? file, CancellationToken ct)
    {
        if (file == null || file.Length == 0) throw new AuthException(400, "EVIDENCE_REQUIRED", "Chọn một tệp bằng chứng để tải lên.");
        if (file.Length > 10 * 1024 * 1024) throw new AuthException(400, "EVIDENCE_SIZE_INVALID", "Bằng chứng tối đa 10 MiB.");
        await using var input = file.OpenReadStream();
        await using var buffer = new MemoryStream();
        await input.CopyToAsync(buffer, ct);
        var result = await appealService.UploadEvidenceAsync(UserId, appealId, file.ContentType, buffer.ToArray(), ct);
        return Ok(result);
    }

    [HttpGet("appeals/{appealId:guid}/evidence")]
    public async Task<IActionResult> GetAppealEvidenceAsync(Guid appealId, CancellationToken ct)
    {
        var path = await appealService.GetEvidenceStoragePathAsync(UserId, appealId, false, ct);
        return await ReadAppealEvidenceAsync(path, ct);
    }

    [HttpGet("appeals/my")]
    public Task<List<AppealDto>> GetMyAppealsAsync(CancellationToken ct) =>
        appealService.GetMyAppealsAsync(UserId, ct);

    [HttpGet("channels/{channelId:guid}/strikes")]
    public Task<ChannelStrikeStatusResponse> GetChannelStrikesAsync(Guid channelId, CancellationToken ct) =>
        strikeService.GetChannelStrikeStatusAsync(channelId, ct);

    private async Task<IActionResult> ReadAppealEvidenceAsync(string path, CancellationToken ct)
    {
        if (path.StartsWith("r2://", StringComparison.OrdinalIgnoreCase))
            return Redirect(await storage.GetReadUrlAsync(path, TimeSpan.FromMinutes(10), ct));
        var stream = await storage.OpenReadAsync(path, ct);
        var contentType = Path.GetExtension(path).ToLowerInvariant() switch
        {
            ".png" => "image/png", ".jpg" or ".jpeg" => "image/jpeg", ".webp" => "image/webp", ".pdf" => "application/pdf", _ => "application/octet-stream"
        };
        return File(stream, contentType, enableRangeProcessing: false);
    }
}
