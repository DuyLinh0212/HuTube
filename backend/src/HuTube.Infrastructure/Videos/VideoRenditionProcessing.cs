using System.Threading.Channels;
using HuTube.Application.Storage;
using HuTube.Application.Videos;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace HuTube.Infrastructure.Videos;

public sealed record DeferredVideoRenditionJob(
    Guid VideoId,
    string SourceFilePath,
    string SourceQuality,
    string WorkingDirectory);

public sealed class VideoRenditionProcessingQueue
{
    private readonly Channel<DeferredVideoRenditionJob> channel =
        Channel.CreateUnbounded<DeferredVideoRenditionJob>(new UnboundedChannelOptions
        {
            SingleReader = true,
            AllowSynchronousContinuations = false
        });

    public void Enqueue(DeferredVideoRenditionJob job) => channel.Writer.TryWrite(job);

    internal IAsyncEnumerable<DeferredVideoRenditionJob> ReadAllAsync(CancellationToken ct) =>
        channel.Reader.ReadAllAsync(ct);
}

public sealed class VideoRenditionProcessingWorker(
    VideoRenditionProcessingQueue queue,
    IServiceScopeFactory scopeFactory,
    ILogger<VideoRenditionProcessingWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            await foreach (var job in queue.ReadAllAsync(stoppingToken))
            {
                try
                {
                    await using var scope = scopeFactory.CreateAsyncScope();
                    var processor = scope.ServiceProvider.GetRequiredService<VideoRenditionProcessor>();
                    await processor.ProcessAsync(job, stoppingToken);
                }
                catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
                catch (Exception ex)
                {
                    logger.LogError(ex, "Deferred rendition processing failed for video {VideoId}", job.VideoId);
                }
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
    }
}

public sealed class VideoRenditionProcessor(
    HuTubeDbContext db,
    IObjectStorage storage,
    IVideoTranscoder transcoder,
    TimeProvider clock,
    ILogger<VideoRenditionProcessor> logger)
{
    public async Task ProcessAsync(DeferredVideoRenditionJob job, CancellationToken ct)
    {
        var generatedPaths = new List<string>();
        try
        {
            var video = await db.Videos.SingleOrDefaultAsync(x => x.VideoId == job.VideoId, ct)
                ?? throw new InvalidOperationException($"Video {job.VideoId} không còn tồn tại.");
            if (!File.Exists(job.SourceFilePath))
                throw new FileNotFoundException("Không tìm thấy file nguồn để tạo rendition.", job.SourceFilePath);

            var generated = await transcoder.CreateLowerRenditionsAsync(
                job.SourceFilePath, job.SourceQuality, job.WorkingDirectory, ct);
            foreach (var rendition in generated)
            {
                await using var renditionStream = File.OpenRead(rendition.FilePath);
                var storedPath = await storage.SaveVideoAsync(
                    $"video-renditions/{job.VideoId:N}", $"{rendition.Quality}.mp4",
                    renditionStream, "video/mp4", ct);
                generatedPaths.Add(storedPath);

                var row = await db.VideoRenditions.SingleOrDefaultAsync(
                    x => x.VideoId == job.VideoId && x.QualityLabel == rendition.Quality, ct);
                if (row == null)
                {
                    db.VideoRenditions.Add(new VideoRendition
                    {
                        VideoId = job.VideoId,
                        QualityLabel = rendition.Quality,
                        Width = rendition.Width,
                        Height = rendition.Height,
                        BitrateKbps = rendition.BitrateKbps,
                        Codec = "h264/aac",
                        FileUrl = storedPath,
                        FileSize = rendition.FileSize,
                        Status = "ready",
                        CreatedAt = clock.GetUtcNow(),
                        UpdatedAt = clock.GetUtcNow()
                    });
                }
                else
                {
                    row.Width = rendition.Width;
                    row.Height = rendition.Height;
                    row.BitrateKbps = rendition.BitrateKbps;
                    row.Codec = "h264/aac";
                    row.FileUrl = storedPath;
                    row.FileSize = rendition.FileSize;
                    row.Status = "ready";
                    row.UpdatedAt = clock.GetUtcNow();
                }
            }

            var generatedQualities = generated.Select(x => x.Quality).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var expectedQualities = VideoRules.LowerQualities(job.SourceQuality);
            var unfinished = await db.VideoRenditions
                .Where(x => x.VideoId == job.VideoId && expectedQualities.Contains(x.QualityLabel)
                    && !generatedQualities.Contains(x.QualityLabel))
                .ToListAsync(ct);
            foreach (var row in unfinished)
            {
                row.Status = "failed";
                row.UpdatedAt = clock.GetUtcNow();
            }
            await db.SaveChangesAsync(ct);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            try
            {
                var failed = await db.VideoRenditions
                    .Where(x => x.VideoId == job.VideoId && x.Status == "processing")
                    .ToListAsync(CancellationToken.None);
                foreach (var row in failed)
                {
                    row.Status = "failed";
                    row.UpdatedAt = clock.GetUtcNow();
                }
                await db.SaveChangesAsync(CancellationToken.None);
            }
            catch (Exception statusError)
            {
                logger.LogError(statusError, "Could not mark deferred renditions as failed for video {VideoId}", job.VideoId);
            }
            foreach (var path in generatedPaths)
            {
                try { await storage.DeleteFileAsync(path, CancellationToken.None); }
                catch (Exception cleanupError) { logger.LogWarning(cleanupError, "Could not clean rendition {StoredPath}", path); }
            }
            logger.LogError(ex, "Could not generate deferred renditions for video {VideoId}", job.VideoId);
        }
        finally
        {
            try { if (Directory.Exists(job.WorkingDirectory)) Directory.Delete(job.WorkingDirectory, true); }
            catch (IOException cleanupError) { logger.LogWarning(cleanupError, "Could not clean rendition workspace {Directory}", job.WorkingDirectory); }
        }
    }
}
