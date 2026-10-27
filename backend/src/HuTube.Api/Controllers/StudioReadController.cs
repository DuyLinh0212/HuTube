using HuTube.Application.Storage;
using HuTube.Application.Videos;
using HuTube.Domain.Channels;
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
    [HttpGet("{channelId:guid}/hourly-analytics")]
    public async Task<ActionResult<StudioHourlyAnalytics>> HourlyAnalyticsAsync(
        Guid channelId, [FromQuery] int days = 7, [FromQuery] int utcOffsetMinutes = 0,
        [FromQuery] Guid? videoId = null, CancellationToken ct = default)
    {
        if (days is not (1 or 7 or 30) || utcOffsetMinutes is < -720 or > 840) return BadRequest();
        var actor = Guid.Parse(User.FindFirst("sub")!.Value);
        var owner = await db.Channels.AsNoTracking()
            .Where(c => c.ChannelId == channelId && c.Status != "deleted")
            .Select(c => (Guid?)c.OwnerUserId).SingleOrDefaultAsync(ct);
        if (!owner.HasValue) return NotFound();
        if (owner.Value != actor)
        {
            var role = await db.ChannelMembers.AsNoTracking()
                .Where(m => m.ChannelId == channelId && m.UserId == actor && m.Status == "active")
                .Select(m => m.RoleCode).SingleOrDefaultAsync(ct);
            if (!ChannelPermissions.RoleHas(role, ChannelPermissions.AnalyticsView)) return Forbid();
        }
        if (videoId.HasValue && !await db.Videos.AsNoTracking().AnyAsync(
            v => v.ChannelId == channelId && v.VideoId == videoId && v.Status != "deleted", ct)) return NotFound();

        var now = DateTimeOffset.UtcNow;
        var start = now.AddDays(-days);
        var totals = await db.ChannelAnalyticsEvents.AsNoTracking()
            .Where(e => e.ChannelId == channelId && e.OccurredAt >= start && e.OccurredAt <= now
                && (!videoId.HasValue || e.VideoId == videoId || e.Metric == "subscribers"))
            .GroupBy(e => new { e.Metric, Hour = e.OccurredAt.AddMinutes(utcOffsetMinutes).Hour })
            .Select(g => new { g.Key.Metric, g.Key.Hour, Value = g.Sum(e => e.Value) })
            .ToListAsync(ct);
        var hours = Enumerable.Range(0, 24).Select(hour => new StudioHourlyBucket(
            hour,
            totals.Where(x => x.Hour == hour && x.Metric == "views").Sum(x => x.Value),
            totals.Where(x => x.Hour == hour && x.Metric == "likes").Sum(x => x.Value),
            totals.Where(x => x.Hour == hour && x.Metric == "watchSeconds").Sum(x => x.Value),
            totals.Where(x => x.Hour == hour && x.Metric == "subscribers").Sum(x => x.Value))).ToArray();
        return new StudioHourlyAnalytics(start, now, utcOffsetMinutes, hours);
    }

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

public sealed record StudioHourlyBucket(int Hour, long Views, long Likes, long WatchSeconds, long Subscribers);
public sealed record StudioHourlyAnalytics(DateTimeOffset From, DateTimeOffset To, int UtcOffsetMinutes, IReadOnlyList<StudioHourlyBucket> Hours);
