using HuTube.Application.Storage;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace HuTube.Infrastructure.Videos;

/// <summary>
/// Removes the source and rendition objects after the appeal window has ended.
/// Pending appeals hold the media until a reviewer makes a final decision.
/// </summary>
public sealed class VideoMediaRetentionCleanupService(
    IServiceScopeFactory scopeFactory,
    TimeProvider clock,
    ILogger<VideoMediaRetentionCleanupService> logger) : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromHours(6);
    private const int BatchSize = 100;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            await RunCleanupSafelyAsync(stoppingToken);

            using var timer = new PeriodicTimer(Interval, clock);
            while (await timer.WaitForNextTickAsync(stoppingToken))
                await RunCleanupSafelyAsync(stoppingToken);
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
        }
    }

    private async Task RunCleanupSafelyAsync(CancellationToken ct)
    {
        try
        {
            await CleanupBatchAsync(ct);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Không thể dọn media video đã hết thời hạn khiếu nại.");
        }
    }

    private async Task CleanupBatchAsync(CancellationToken ct)
    {
        await using var scope = scopeFactory.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<HuTubeDbContext>();
        var storage = scope.ServiceProvider.GetRequiredService<IObjectStorage>();
        var now = clock.GetUtcNow();

        var videos = await db.Videos
            .Where(video => video.Status == "blocked"
                && video.ModerationStatus == "rejected"
                && video.MediaRetentionUntil.HasValue
                && video.MediaRetentionUntil <= now
                && video.MediaPurgedAt == null
                && !db.Appeals.Any(appeal => appeal.TargetType == AppealTargetTypes.Video
                    && appeal.TargetId == video.VideoId
                    && (appeal.Status == AppealStatuses.Pending
                        || appeal.Status == AppealStatuses.Reviewing
                        || appeal.Status == "escalated")))
            .OrderBy(video => video.MediaRetentionUntil)
            .Take(BatchSize)
            .ToListAsync(ct);

        if (videos.Count == 0) return;

        var videoIds = videos.Select(video => video.VideoId).ToArray();
        var renditions = await db.VideoRenditions
            .Where(rendition => videoIds.Contains(rendition.VideoId))
            .ToListAsync(ct);

        foreach (var video in videos)
        {
            var videoRenditions = renditions.Where(rendition => rendition.VideoId == video.VideoId).ToArray();
            var paths = videoRenditions.Select(rendition => rendition.FileUrl)
                .Append(video.VideoUrl)
                .Append(video.ThumbnailUrl)
                .Where(path => !string.IsNullOrWhiteSpace(path))
                .Distinct(StringComparer.Ordinal)
                .ToArray();

            try
            {
                foreach (var path in paths)
                    await storage.DeleteFileAsync(path!, ct);

                video.MediaPurgedAt = now;
                video.VideoUrl = "";
                video.ThumbnailUrl = null;
                video.UpdatedAt = now;
                foreach (var rendition in videoRenditions)
                {
                    rendition.FileUrl = "";
                    rendition.Status = "deleted";
                    rendition.UpdatedAt = now;
                }

                logger.LogInformation("Đã dọn media video {VideoId} sau thời hạn khiếu nại.", video.VideoId);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Không dọn được toàn bộ media video {VideoId}; lần chạy sau sẽ thử lại.", video.VideoId);
            }
        }

        await db.SaveChangesAsync(ct);
    }
}
