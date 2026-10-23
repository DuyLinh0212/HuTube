using HuTube.Application.Storage;
using HuTube.Application.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Api.Controllers;

// Compact projection shared by the overview, analytics and video selectors.
// No renditions, viewer state, tags, chapters or editor payload per video.
[ApiController, Authorize, Route("api/v1/studio/channels")]
public sealed class StudioReadController(HuTubeDbContext db, IContentService content, IObjectStorage storage) : ControllerBase
{
    [HttpGet("{channelId:guid}/metrics")]
    public async Task<IReadOnlyList<StudioVideoSummary>> MetricsAsync(Guid channelId, CancellationToken ct, [FromQuery] bool includeStats = true)
    {
        // Reuse the existing channel read permission policy, including shared roles.
        var actor = Guid.Parse(User.FindFirst("sub")!.Value);
        await content.GetManagedVideosAsync(actor, channelId, null, null, null, null, null, 1, 1, ct);
        var rows = await db.Videos.AsNoTracking().Where(v => v.ChannelId == channelId && v.Status != "deleted")
            .OrderByDescending(v => v.CreatedAt).Select(v => new {
                v.VideoId, v.ChannelId, v.Title, v.ThumbnailUrl, v.Duration, v.Visibility, v.Status, v.ModerationStatus,
                v.LanguageCode, v.CreatedAt, v.PublishedAt,
                ModerationReason = db.Channels.Any(c => c.ChannelId == channelId && c.OwnerUserId == actor) ? v.ModerationReason : null,
                Views = includeStats ? db.ViewingHistories.LongCount(x => x.VideoId == v.VideoId) : 0,
                Likes = includeStats ? db.VideoReactions.LongCount(x => x.VideoId == v.VideoId && x.Type == "like") : 0,
                Dislikes = includeStats ? db.VideoReactions.LongCount(x => x.VideoId == v.VideoId && x.Type == "dislike") : 0,
                Comments = includeStats ? db.Comments.Count(x => x.VideoId == v.VideoId && x.Status == "visible") : 0,
                Shares = includeStats ? db.ShareHistories.LongCount(x => x.VideoId == v.VideoId) : 0,
                WatchSeconds = includeStats ? db.ViewingHistories.Where(x => x.VideoId == v.VideoId).Sum(x => (long?)x.WatchDuration) ?? 0 : 0,
                Rating = includeStats ? db.VideoRatings.Where(x => x.VideoId == v.VideoId).Average(x => (double?)x.Score) : null,
                RatingCount = includeStats ? db.VideoRatings.Count(x => x.VideoId == v.VideoId) : 0
            }).ToListAsync(ct);
        var result = new List<StudioVideoSummary>(rows.Count);
        foreach (var row in rows)
            result.Add(new(row.VideoId, row.ChannelId, row.Title,
                row.ThumbnailUrl == null ? null : await storage.GetReadUrlAsync(row.ThumbnailUrl, TimeSpan.FromMinutes(60), ct),
                row.Duration, row.Visibility, row.Status, row.ModerationStatus, row.LanguageCode, row.CreatedAt, row.PublishedAt,
                new(row.Views, row.Likes, row.Dislikes, row.Comments,
                    row.Rating.HasValue ? Math.Round((decimal)row.Rating.Value, 2) : null, row.RatingCount, row.Shares, row.WatchSeconds), row.ModerationReason));
        return result;
    }
}

public sealed record StudioVideoSummary(Guid VideoId, Guid ChannelId, string Title, string? ThumbnailUrl,
    int Duration, string Visibility, string Status, string ModerationStatus, string? LanguageCode,
    DateTimeOffset CreatedAt, DateTimeOffset? PublishedAt, VideoStatsResponse Stats, string? ModerationReason);
