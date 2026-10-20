using System.Threading.Channels;
using HuTube.Application.Videos;

namespace HuTube.Api.Services;

// Finalization must outlive an individual HTTP connection. Keep concurrency
// bounded because media inspection and storage share the API instance's resources.
public sealed class VideoUploadCompletionWorker(
    IServiceScopeFactory scopes,
    VideoChunkUploadStore uploads,
    ILogger<VideoUploadCompletionWorker> logger) : BackgroundService
{
    private sealed record Job(VideoChunkUploadStore.Session Session, CreateVideoCommand Command,
        byte[]? Thumbnail, CancellationTokenSource Cancellation);
    private readonly Channel<Job> queue = Channel.CreateBounded<Job>(new BoundedChannelOptions(8)
    {
        SingleReader = true,
        FullMode = BoundedChannelFullMode.Wait
    });

    // Caller holds Session.Gate. Duplicate completions share the same job.
    public void Enqueue(VideoChunkUploadStore.Session session, CreateVideoCommand command, byte[]? thumbnail)
    {
        if (session.IsCompleting || session.CompletedVideoId.HasValue) return;
        session.IsCompleting = true;
        session.CompletionError = null;
        var cancellation = new CancellationTokenSource();
        session.CompletionCancellation = cancellation;
        if (queue.Writer.TryWrite(new(session, command, thumbnail, cancellation))) return;
        session.IsCompleting = false;
        session.CompletionCancellation = null;
        cancellation.Dispose();
        throw new ContentException(503, "UPLOAD_QUEUE_FULL", "Máy chủ đang xử lý nhiều video. Vui lòng thử lại sau.");
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var job in queue.Reader.ReadAllAsync(stoppingToken))
        {
            using var cancellation = job.Cancellation;
            using var jobToken = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken, cancellation.Token);
            Guid? videoId = null;
            ContentException? error = null;
            try
            {
                jobToken.Token.ThrowIfCancellationRequested();
                await using var scope = scopes.CreateAsyncScope();
                await using var source = File.OpenRead(job.Session.FilePath);
                await using var thumbnail = job.Thumbnail == null ? null : new MemoryStream(job.Thumbnail, writable: false);
                var command = job.Command with { Content = source, ThumbnailContent = thumbnail };
                var video = await scope.ServiceProvider.GetRequiredService<IContentService>()
                    .CreateVideoAsync(job.Session.ActorId, command, jobToken.Token);
                videoId = video.VideoId;
            }
            catch (OperationCanceledException) when (jobToken.IsCancellationRequested)
            {
                error = new ContentException(409, "UPLOAD_CANCELED", "Quá trình tải video đã bị hủy.");
            }
            catch (ContentException ex) { error = ex; }
            catch (Exception ex)
            {
                logger.LogError(ex, "Upload finalization failed for {UploadId}", job.Session.Request.UploadId);
                error = new ContentException(503, "UPLOAD_PROCESSING_FAILED", "Chưa thể hoàn tất xử lý video. Vui lòng thử lại.");
            }
            await job.Session.Gate.WaitAsync(CancellationToken.None);
            try
            {
                job.Session.CompletedVideoId = videoId;
                job.Session.CompletionError = error;
                job.Session.IsCompleting = false;
                job.Session.CompletionCancellation = null;
                job.Session.TouchedAt = DateTimeOffset.UtcNow;
                if (videoId.HasValue) uploads.RemoveSource(job.Session);
                else if (cancellation.IsCancellationRequested) uploads.RemoveSession(job.Session);
            }
            finally { job.Session.Gate.Release(); }
        }
    }
}
