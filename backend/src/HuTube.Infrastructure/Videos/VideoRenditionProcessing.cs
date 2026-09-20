using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
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
    string WorkingDirectory)
{
    public DeferredVideoRenditionJob(Guid videoId, string sourceQuality)
        : this(videoId, "", sourceQuality, "")
    {
    }
}

public sealed class VideoRenditionProcessingQueue
{
    private readonly ConcurrentDictionary<Guid, byte> scheduledVideos = new();
    private readonly Channel<DeferredVideoRenditionJob> channel =
        Channel.CreateUnbounded<DeferredVideoRenditionJob>(new UnboundedChannelOptions
        {
            SingleReader = true,
            AllowSynchronousContinuations = false
        });

    public void Enqueue(DeferredVideoRenditionJob job)
    {
        if (!scheduledVideos.TryAdd(job.VideoId, 0)) return;
        if (!channel.Writer.TryWrite(job)) scheduledVideos.TryRemove(job.VideoId, out _);
    }

    public void MarkCompleted(Guid videoId) => scheduledVideos.TryRemove(videoId, out _);

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
            try
            {
                await RecoverPendingJobsAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
            catch (Exception ex)
            {
                logger.LogError(ex, "Không thể khôi phục hàng đợi encode rendition từ database.");
            }

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
                finally
                {
                    queue.MarkCompleted(job.VideoId);
                }
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
    }

    private async Task RecoverPendingJobsAsync(CancellationToken ct)
    {
        await using var scope = scopeFactory.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<HuTubeDbContext>();
        var pending = await (
            from rendition in db.VideoRenditions.AsNoTracking()
            join source in db.VideoRenditions.AsNoTracking()
                on rendition.VideoId equals source.VideoId
            where rendition.Status == "processing"
                && source.Status == "ready"
                && source.Codec == "source"
            group rendition by new { rendition.VideoId, SourceQuality = source.QualityLabel } into grouped
            select new
            {
                grouped.Key.VideoId,
                grouped.Key.SourceQuality,
                UpdatedAt = grouped.Max(x => x.UpdatedAt)
            })
            .OrderByDescending(x => x.UpdatedAt)
            .ToListAsync(ct);

        foreach (var item in pending)
        {
            queue.Enqueue(new DeferredVideoRenditionJob(item.VideoId, item.SourceQuality));
            logger.LogInformation(
                "Đã khôi phục job encode rendition cho video {VideoId}, source {SourceQuality}.",
                item.VideoId, item.SourceQuality);
        }
    }
}

public sealed class VideoRenditionProcessor(
    HuTubeDbContext db,
    IObjectStorage storage,
    IVideoTranscoder transcoder,
    TimeProvider clock,
    ILogger<VideoRenditionProcessor> logger,
    IHttpClientFactory httpClientFactory)
{
    public async Task ProcessAsync(DeferredVideoRenditionJob job, CancellationToken ct)
    {
        string? workingDirectory = null;
        string? currentStoredPath = null;
        try
        {
            var video = await db.Videos.SingleOrDefaultAsync(x => x.VideoId == job.VideoId, ct)
                ?? throw new InvalidOperationException($"Video {job.VideoId} không còn tồn tại.");

            workingDirectory = string.IsNullOrWhiteSpace(job.WorkingDirectory)
                ? FindReusableWorkspace(video.FileSize)
                    ?? Path.Combine(Path.GetTempPath(), "hutube-video-processing", $"recovery-{job.VideoId:N}-{Guid.NewGuid():N}")
                : job.WorkingDirectory;
            Directory.CreateDirectory(workingDirectory);
            var sourceFilePath = await EnsureSourceFileAsync(video, job.SourceFilePath, workingDirectory, ct);

            var expectedQualities = VideoRules.LowerQualities(job.SourceQuality);
            var generatedQualities = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var quality in expectedQualities)
            {
                var rendition = await transcoder.CreateRenditionAsync(
                    sourceFilePath, job.SourceQuality, quality, workingDirectory, ct);
                if (rendition == null) continue;

                await using var renditionStream = File.OpenRead(rendition.FilePath);
                currentStoredPath = await storage.SaveVideoAsync(
                    $"video-renditions/{job.VideoId:N}", $"{rendition.Quality}.mp4",
                    renditionStream, "video/mp4", ct);

                await PersistRenditionAsync(job.VideoId, rendition, currentStoredPath, ct);
                generatedQualities.Add(rendition.Quality);
                currentStoredPath = null;
            }

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
            if (currentStoredPath != null)
            {
                try { await storage.DeleteFileAsync(currentStoredPath, CancellationToken.None); }
                catch (Exception cleanupError) { logger.LogWarning(cleanupError, "Could not clean rendition {StoredPath}", currentStoredPath); }
            }
            logger.LogError(ex, "Could not generate deferred renditions for video {VideoId}", job.VideoId);
        }
        finally
        {
            try
            {
                if (!string.IsNullOrWhiteSpace(workingDirectory) && Directory.Exists(workingDirectory))
                    Directory.Delete(workingDirectory, true);
            }
            catch (IOException cleanupError) { logger.LogWarning(cleanupError, "Could not clean rendition workspace {Directory}", workingDirectory); }
        }
    }

    private async Task PersistRenditionAsync(
        Guid videoId,
        TranscodedVideo rendition,
        string storedPath,
        CancellationToken ct)
    {
        var row = await db.VideoRenditions.SingleOrDefaultAsync(
            x => x.VideoId == videoId && x.QualityLabel == rendition.Quality, ct);
        if (row == null)
        {
            db.VideoRenditions.Add(new VideoRendition
            {
                VideoId = videoId,
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
        await db.SaveChangesAsync(ct);
    }

    private static string? FindReusableWorkspace(long sourceFileSize)
    {
        var root = Path.Combine(Path.GetTempPath(), "hutube-video-processing");
        if (!Directory.Exists(root)) return null;
        foreach (var directory in Directory.EnumerateDirectories(root)
                     .OrderByDescending(Directory.GetLastWriteTimeUtc))
        {
            foreach (var source in Directory.EnumerateFiles(directory, "source.*"))
            {
                try
                {
                    if (new FileInfo(source).Length == sourceFileSize) return directory;
                }
                catch (FileNotFoundException) { }
                catch (DirectoryNotFoundException) { }
            }
        }
        return null;
    }

    private async Task<string> EnsureSourceFileAsync(
        HuTube.Domain.Videos.Video video,
        string sourceFilePath,
        string workingDirectory,
        CancellationToken ct)
    {
        if (!string.IsNullOrWhiteSpace(sourceFilePath) && File.Exists(sourceFilePath)
            && new FileInfo(sourceFilePath).Length == video.FileSize)
            return sourceFilePath;

        var existingSource = Directory.EnumerateFiles(workingDirectory, "source.*")
            .FirstOrDefault(path =>
            {
                try { return new FileInfo(path).Length == video.FileSize; }
                catch (FileNotFoundException) { return false; }
                catch (DirectoryNotFoundException) { return false; }
            });
        if (existingSource != null) return existingSource;

        var sourceUrl = await storage.GetReadUrlAsync(video.VideoUrl, TimeSpan.FromMinutes(30), ct);
        if (!Uri.TryCreate(sourceUrl, UriKind.Absolute, out var uri)
            || uri.Scheme is not ("http" or "https"))
            throw new InvalidOperationException("Không thể tải source video để khôi phục job encode.");

        var extension = Path.GetExtension(uri.AbsolutePath);
        if (string.IsNullOrWhiteSpace(extension)) extension = ".mp4";
        var recoveredSource = Path.Combine(workingDirectory, "source" + extension);
        await DownloadSourceInRangesAsync(httpClientFactory.CreateClient(), uri, recoveredSource, video.FileSize, ct);
        if (!File.Exists(recoveredSource) || new FileInfo(recoveredSource).Length != video.FileSize)
            throw new InvalidOperationException("Source video tải về bị rỗng.");
        return recoveredSource;
    }

    private static async Task DownloadSourceInRangesAsync(
        HttpClient client,
        Uri sourceUri,
        string destination,
        long expectedLength,
        CancellationToken ct)
    {
        var temporaryPath = destination + ".part";
        try
        {
            using var probeRequest = new HttpRequestMessage(HttpMethod.Get, sourceUri);
            probeRequest.Headers.Range = new RangeHeaderValue(0, 0);
            using var probeResponse = await client.SendAsync(probeRequest, HttpCompletionOption.ResponseHeadersRead, ct);
            if (!probeResponse.IsSuccessStatusCode)
                throw new InvalidOperationException($"Không thể tải source video (HTTP {(int)probeResponse.StatusCode}).");

            if (probeResponse.StatusCode == HttpStatusCode.OK)
            {
                await using var output = File.Create(temporaryPath);
                await probeResponse.Content.CopyToAsync(output, ct);
            }
            else
            {
                var totalLength = probeResponse.Content.Headers.ContentRange?.Length ?? expectedLength;
                if (totalLength <= 0 || totalLength != expectedLength)
                    throw new InvalidOperationException("Kích thước source video từ storage không khớp metadata.");

                const int chunkSize = 1 * 1024 * 1024;
                var offsets = new List<long>();
                for (long start = 0; start < totalLength; start += chunkSize) offsets.Add(start);
                await using (var output = new FileStream(
                    temporaryPath, FileMode.Create, FileAccess.Write, FileShare.ReadWrite, chunkSize, useAsync: true))
                {
                    output.SetLength(totalLength);
                }

                await Parallel.ForEachAsync(
                    offsets,
                    new ParallelOptions { MaxDegreeOfParallelism = 16, CancellationToken = ct },
                    async (start, token) =>
                    {
                        var end = Math.Min(totalLength - 1, start + chunkSize - 1);
                        using var rangeRequest = new HttpRequestMessage(HttpMethod.Get, sourceUri);
                        rangeRequest.Headers.Range = new RangeHeaderValue(start, end);
                        using var rangeResponse = await client.SendAsync(rangeRequest, HttpCompletionOption.ResponseHeadersRead, token);
                        if (rangeResponse.StatusCode != HttpStatusCode.PartialContent)
                            throw new InvalidOperationException($"Storage không trả source theo range (HTTP {(int)rangeResponse.StatusCode}).");

                        var bytes = await rangeResponse.Content.ReadAsByteArrayAsync(token);
                        if (bytes.LongLength != end - start + 1)
                            throw new InvalidOperationException("Tải thiếu một phần source video từ storage.");
                        await using var output = new FileStream(
                            temporaryPath, FileMode.Open, FileAccess.Write, FileShare.ReadWrite, bytes.Length, useAsync: true);
                        output.Position = start;
                        await output.WriteAsync(bytes, token);
                    });
            }

            if (!File.Exists(temporaryPath) || new FileInfo(temporaryPath).Length != expectedLength)
                throw new InvalidOperationException("Source video tải về không đủ dữ liệu.");
            File.Move(temporaryPath, destination, true);
        }
        finally
        {
            if (File.Exists(temporaryPath)) File.Delete(temporaryPath);
        }
    }
}
