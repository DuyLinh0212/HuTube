using HuTube.Api.Authorization;
using HuTube.Api.Services;
using HuTube.Application.CfSeeding;
using HuTube.Application.Videos;
using HuTube.Domain.Rbac;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

public sealed class UploadCfSeedVideoForm
{
    public Guid BatchId { get; set; }
    public Guid UserId { get; set; }
    public Guid ChannelId { get; set; }
    public Guid CategoryId { get; set; }
    public string Title { get; set; } = "";
    public string Visibility { get; set; } = "public";
    public int Duration { get; set; }
    public string SourceQuality { get; set; } = "720p";
    public int Sequence { get; set; }
    public bool UseExistingAccount { get; set; }
    public IFormFile? Video { get; set; }
}

public sealed record StartCfSeedUploadRequest(Guid UploadId, string FileName, string ContentType, long FileSize, int TotalChunks);
public sealed record StartCfSeedUploadResponse(Guid UploadId, int ChunkSize);
public sealed record CfSeedChunkResponse(int NextChunk);
public sealed record CompleteCfSeedUploadRequest(Guid BatchId, Guid UserId, Guid ChannelId, Guid CategoryId,
    string Title, string Visibility, int Duration, string SourceQuality, int Sequence,
    bool UseExistingAccount = false);

[ApiController]
[Authorize]
[Route("api/v1/admin/cf-seeder")]
[RequirePermission(AdminPermissions.CfSeedManage)]
public sealed class CfSeederController(ICfSeederService seeder, CfSeedChunkUploadStore chunks) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirst("sub")!.Value);

    [HttpPost("accounts")]
    public Task<CfSeedProvisionResponse> CreateAccountsAsync(
        [FromBody] CreateCfSeedAccountsRequest request, CancellationToken ct) =>
        seeder.CreateAccountsAsync(UserId, request, ct);

    [HttpGet("users")]
    public Task<IReadOnlyList<CfSeedAccountResponse>> GetExistingAccountsAsync(
        [FromQuery] string? search, CancellationToken ct) => seeder.GetExistingAccountsAsync(search, ct);

    [HttpPost("videos"), DisableRequestSizeLimit]
    public async Task<ActionResult<CfSeedVideoResponse>> UploadVideoAsync(
        [FromForm] UploadCfSeedVideoForm form, CancellationToken ct)
    {
        if (form.Video == null || form.Video.Length == 0)
            throw new ContentException(400, "VIDEO_REQUIRED", "Vui lòng chọn file video.");
        await using var stream = form.Video.OpenReadStream();
        var result = await seeder.UploadVideoAsync(UserId, new UploadCfSeedVideoCommand(
            form.BatchId, form.UserId, form.ChannelId, form.CategoryId, form.Title,
            form.Visibility, form.Duration, form.SourceQuality, form.Video.Length,
            form.Video.FileName, form.Video.ContentType, stream, form.Sequence, form.UseExistingAccount), ct);
        return Created($"/api/v1/videos/{result.VideoId}", result);
    }

    [HttpPost("upload-sessions")]
    public ActionResult<StartCfSeedUploadResponse> StartUpload([FromBody] StartCfSeedUploadRequest request)
    {
        var session = chunks.Start(UserId, request.UploadId, request.FileName, request.ContentType, request.FileSize, request.TotalChunks);
        return Ok(new StartCfSeedUploadResponse(session.UploadId, session.ChunkSize));
    }

    [HttpPost("upload-sessions/{uploadId:guid}/chunks/{chunkIndex:int}")]
    [RequestSizeLimit(32L * 1024 * 1024)]
    public async Task<ActionResult<CfSeedChunkResponse>> UploadChunk(Guid uploadId, int chunkIndex,
        IFormFile? chunk, CancellationToken ct)
    {
        if (chunk == null || chunk.Length == 0)
            throw new ContentException(400, "CF_SEED_CHUNK_REQUIRED", "Thiếu dữ liệu phần video.");
        var next = await chunks.AppendAsync(UserId, uploadId, chunkIndex, chunk, ct);
        return Ok(new CfSeedChunkResponse(next));
    }

    [HttpPost("upload-sessions/{uploadId:guid}/complete")]
    public async Task<ActionResult<CfSeedVideoResponse>> CompleteUpload(Guid uploadId,
        [FromBody] CompleteCfSeedUploadRequest request, CancellationToken ct)
    {
        var ready = await chunks.PrepareCompletionAsync(UserId, uploadId, ct);
        if (ready.CompletedResponse != null) return Ok(ready.CompletedResponse);
        try
        {
            CfSeedVideoResponse result;
            await using (var stream = new FileStream(ready.FilePath, FileMode.Open, FileAccess.Read,
                FileShare.Read, 128 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan))
                result = await seeder.UploadVideoAsync(UserId, new UploadCfSeedVideoCommand(
                    request.BatchId, request.UserId, request.ChannelId, request.CategoryId, request.Title,
                    request.Visibility, request.Duration, request.SourceQuality, ready.FileSize,
                    ready.FileName, ready.ContentType, stream, request.Sequence, request.UseExistingAccount), ct);
            await chunks.MarkCompletedAsync(UserId, uploadId, result, CancellationToken.None);
            return Created($"/api/v1/videos/{result.VideoId}", result);
        }
        catch
        {
            await chunks.ReleaseForRetryAsync(UserId, uploadId);
            throw;
        }
    }
}
