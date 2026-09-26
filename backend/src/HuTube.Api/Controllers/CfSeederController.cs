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
    public int SourceWidth { get; set; }
    public int SourceHeight { get; set; }
    public string? Description { get; set; }
    public IFormFile? Video { get; set; }
}

public sealed class UploadCfSeedRenditionForm
{
    public string Quality { get; set; } = "";
    public int Width { get; set; }
    public int Height { get; set; }
    public int? BitrateKbps { get; set; }
    public string? Codec { get; set; }
    public IFormFile? Video { get; set; }
}

public sealed record StartCfSeedUploadRequest(Guid UploadId, string FileName, string ContentType, long FileSize, int TotalChunks);
public sealed record StartCfSeedUploadResponse(Guid UploadId, int ChunkSize);
public sealed record CfSeedChunkResponse(int NextChunk);
public sealed record CompleteCfSeedUploadRequest(Guid BatchId, Guid UserId, Guid ChannelId, Guid CategoryId,
    string Title, string Visibility, int Duration, string SourceQuality, int Sequence,
    bool UseExistingAccount = false, int SourceWidth = 0, int SourceHeight = 0, string? Description = null);
public sealed record CompleteCfSeedRenditionUploadRequest(Guid VideoId, string Quality, int Width, int Height,
    int? BitrateKbps, string? Codec);

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

    [HttpPost("viewers")]
    public Task<IReadOnlyList<CfSeedViewerAccountResponse>> CreateViewersAsync(
        [FromBody] CreateCfSeedViewersRequest request, CancellationToken ct) =>
        seeder.CreateViewerAccountsAsync(request, ct);

    [HttpGet("users")]
    public Task<IReadOnlyList<CfSeedAccountResponse>> GetExistingAccountsAsync(
        [FromQuery] string? search, CancellationToken ct) => seeder.GetExistingAccountsAsync(search, ct);

    [HttpGet("videos/{videoId:guid}/processing")]
    public Task<CfSeedVideoProcessingResponse> GetVideoProcessingAsync(Guid videoId, CancellationToken ct) =>
        seeder.GetVideoProcessingAsync(videoId, ct);

    [HttpPost("videos"), DisableRequestSizeLimit,
        RequestFormLimits(MultipartBodyLengthLimit = 256L * 1024 * 1024 * 1024)]
    public async Task<ActionResult<CfSeedVideoResponse>> UploadVideoAsync(
        [FromForm] UploadCfSeedVideoForm form, CancellationToken ct)
    {
        if (form.Video == null || form.Video.Length == 0)
            throw new ContentException(400, "VIDEO_REQUIRED", "Vui lòng chọn file video.");
        await using var stream = form.Video.OpenReadStream();
        var result = await seeder.UploadVideoAsync(UserId, new UploadCfSeedVideoCommand(
            form.BatchId, form.UserId, form.ChannelId, form.CategoryId, form.Title,
            form.Visibility, form.Duration, form.SourceQuality, form.Video.Length,
            form.Video.FileName, form.Video.ContentType, stream, form.Sequence, form.UseExistingAccount,
            form.SourceWidth, form.SourceHeight, form.Description), ct);
        return Created($"/api/v1/videos/{result.VideoId}", result);
    }

    [HttpPost("videos/{videoId:guid}/renditions"), DisableRequestSizeLimit,
        RequestFormLimits(MultipartBodyLengthLimit = 256L * 1024 * 1024 * 1024)]
    public async Task<ActionResult<CfSeedRenditionResponse>> UploadRenditionAsync(Guid videoId,
        [FromForm] UploadCfSeedRenditionForm form, CancellationToken ct)
    {
        if (form.Video == null || form.Video.Length == 0)
            throw new ContentException(400, "VIDEO_REQUIRED", "Vui lòng chọn file rendition.");
        await using var stream = form.Video.OpenReadStream();
        var result = await seeder.UploadRenditionAsync(UserId, new UploadCfSeedRenditionCommand(
            videoId, form.Quality, form.Width, form.Height, form.BitrateKbps, form.Codec,
            form.Video.Length, form.Video.FileName, form.Video.ContentType, stream), ct);
        return Ok(result);
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
        if (ready.CompletedRenditionResponse != null)
            throw new ContentException(409, "CF_SEED_UPLOAD_KIND_MISMATCH", "Phiên upload này đã được dùng cho một rendition.");
        if (ready.CompletedResponse != null) return Ok(ready.CompletedResponse);
        try
        {
            CfSeedVideoResponse result;
            await using (var stream = new FileStream(ready.FilePath, FileMode.Open, FileAccess.Read,
                FileShare.Read, 128 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan))
                result = await seeder.UploadVideoAsync(UserId, new UploadCfSeedVideoCommand(
                    request.BatchId, request.UserId, request.ChannelId, request.CategoryId, request.Title,
                    request.Visibility, request.Duration, request.SourceQuality, ready.FileSize,
                    ready.FileName, ready.ContentType, stream, request.Sequence, request.UseExistingAccount,
                    request.SourceWidth, request.SourceHeight, request.Description), ct);
            await chunks.MarkCompletedAsync(UserId, uploadId, result, CancellationToken.None);
            return Created($"/api/v1/videos/{result.VideoId}", result);
        }
        catch
        {
            await chunks.ReleaseForRetryAsync(UserId, uploadId);
            throw;
        }
    }

    [HttpPost("upload-sessions/{uploadId:guid}/complete-rendition")]
    public async Task<ActionResult<CfSeedRenditionResponse>> CompleteRenditionUpload(Guid uploadId,
        [FromBody] CompleteCfSeedRenditionUploadRequest request, CancellationToken ct)
    {
        var ready = await chunks.PrepareCompletionAsync(UserId, uploadId, ct);
        if (ready.CompletedRenditionResponse != null) return Ok(ready.CompletedRenditionResponse);
        if (ready.CompletedResponse != null)
            throw new ContentException(409, "CF_SEED_UPLOAD_KIND_MISMATCH", "Phiên upload này đã được dùng cho video nguồn.");
        try
        {
            CfSeedRenditionResponse result;
            await using (var stream = new FileStream(ready.FilePath, FileMode.Open, FileAccess.Read,
                FileShare.Read, 128 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan))
                result = await seeder.UploadRenditionAsync(UserId, new UploadCfSeedRenditionCommand(
                    request.VideoId, request.Quality, request.Width, request.Height, request.BitrateKbps,
                    request.Codec, ready.FileSize, ready.FileName, ready.ContentType, stream), ct);
            await chunks.MarkRenditionCompletedAsync(UserId, uploadId, result, CancellationToken.None);
            return Ok(result);
        }
        catch
        {
            await chunks.ReleaseForRetryAsync(UserId, uploadId);
            throw;
        }
    }
}
