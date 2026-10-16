using System.Security.Claims;
using System.Text.Json;
using HuTube.Api.Services;
using HuTube.Application.Videos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace HuTube.Api.Controllers;

[ApiController, Authorize, Route("api/v1/videos/upload-sessions")]
public sealed class VideoUploadSessionsController(IContentService content, VideoChunkUploadStore uploads) : ControllerBase
{
    private Guid UserId => Guid.TryParse(User.FindFirst("sub")?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value, out var id)
        ? id : throw new ContentException(401, "UNAUTHORIZED", "Vui lòng đăng nhập để tải video.");

    [HttpPost, EnableRateLimiting("upload-preflight")]
    public async Task<VideoUploadSessionResponse> Start(VideoUploadSessionRequest request, CancellationToken ct)
    {
        // A previous completion may have committed while its HTTP response was
        // lost. Resume it without charging the file against quota a second time.
        var existing = uploads.TryResume(UserId, request);
        if (existing != null) return existing;
        await content.PreflightAsync(UserId, new(request.ChannelId, request.FileSize, request.Duration,
            request.ContentType, request.SourceQuality), ct);
        return uploads.Start(UserId, request);
    }

    [HttpPost("{uploadId:guid}/chunks/{index:int}"), RequestSizeLimit(10L * 1024 * 1024), EnableRateLimiting("upload-chunk")]
    public async Task<object> Append(Guid uploadId, int index, IFormFile chunk, CancellationToken ct) =>
        new { nextChunk = await uploads.AppendAsync(UserId, uploadId, index, chunk, ct) };

    [HttpPost("{uploadId:guid}/complete"), RequestSizeLimit(8L * 1024 * 1024), EnableRateLimiting("upload")]
    public async Task<ActionResult<VideoResponse>> Complete(Guid uploadId, [FromForm] UploadVideoForm form, CancellationToken ct)
    {
        var session = uploads.Require(UserId, uploadId);
        await session.Gate.WaitAsync(ct);
        try
        {
            if (form.ChannelId != session.Request.ChannelId)
                throw new ContentException(400, "UPLOAD_CHANNEL_MISMATCH", "Kênh tải video không khớp với phiên tải lên.");
            if (session.CompletedVideoId.HasValue)
                return Ok(await content.GetVideoAsync(session.CompletedVideoId.Value, UserId, ct));
            if ((long)session.NextChunk * VideoChunkUploadStore.ChunkSize < session.Request.FileSize
                || !System.IO.File.Exists(session.FilePath) || new FileInfo(session.FilePath).Length != session.Request.FileSize)
                throw new ContentException(409, "UPLOAD_INCOMPLETE", "Video chưa được tải lên đầy đủ. Hãy thử lại.");
            if (form.Thumbnail?.Length > 5L * 1024 * 1024)
                throw new ContentException(400, "THUMBNAIL_TOO_LARGE", "Ảnh thumbnail không được vượt quá 5 MB.");
            IReadOnlyList<ChapterRequest> chapters;
            IReadOnlyList<VideoCardRequest> cards;
            try
            {
                var json = new JsonSerializerOptions(JsonSerializerDefaults.Web);
                chapters = string.IsNullOrWhiteSpace(form.ChaptersJson) ? [] : JsonSerializer.Deserialize<List<ChapterRequest>>(form.ChaptersJson, json) ?? [];
                cards = string.IsNullOrWhiteSpace(form.VideoCardsJson) ? [] : JsonSerializer.Deserialize<List<VideoCardRequest>>(form.VideoCardsJson, json) ?? [];
            }
            catch (JsonException) { throw new ContentException(400, "INVALID_VIDEO_METADATA", "Dữ liệu chương hoặc video liên quan không hợp lệ."); }
            await using var source = System.IO.File.OpenRead(session.FilePath);
            await using var thumbnail = form.Thumbnail?.OpenReadStream();
            var result = await content.CreateVideoAsync(UserId, new CreateVideoCommand(form.ChannelId, form.Title,
                form.Description, form.CategoryId, form.LanguageCode, form.Visibility, form.AgeRestricted,
                session.Request.Duration, session.Request.SourceQuality, session.Request.FileSize,
                session.Request.FileName, session.Request.ContentType, source,
                form.Thumbnail?.FileName, form.Thumbnail?.ContentType, thumbnail, form.Tags, chapters,
                uploadId.ToString("D"), DeferLowerRenditions: true, AllowComments: form.AllowComments, VideoCards: cards), ct);
            session.CompletedVideoId = result.VideoId;
            session.TouchedAt = DateTimeOffset.UtcNow;
            // Dispose the reader before deleting, including on Windows.
            await source.DisposeAsync();
            uploads.RemoveSource(session);
            return Created($"/api/v1/videos/{result.VideoId}", result);
        }
        finally { session.Gate.Release(); }
    }

    [HttpDelete("{uploadId:guid}"), EnableRateLimiting("upload-preflight")]
    public async Task<IActionResult> Cancel(Guid uploadId, CancellationToken ct)
    {
        await uploads.CancelAsync(UserId, uploadId, ct);
        return NoContent();
    }
}
