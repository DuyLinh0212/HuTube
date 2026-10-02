using System.Data;
using System.Net.Http;
using System.Text.Json;
using HuTube.Application.Recommendations;
using HuTube.Application.Serialization;
using HuTube.Application.Storage;
using HuTube.Application.Notifications;
using HuTube.Application.Videos;
using HuTube.Domain.Channels;
using HuTube.Domain.Plans;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace HuTube.Infrastructure.Videos;

public sealed class ContentService(
    HuTubeDbContext db,
    IObjectStorage storage,
    IVideoTranscoder transcoder,
    INotificationService notifications,
    FeatureOptions features,
    TimeProvider clock,
    ILogger<ContentService> logger,
    IHttpClientFactory httpClientFactory,
    VideoRenditionProcessingQueue renditionQueue,
    IRecommendationClient recommendationClient) : IContentService
{
    private sealed record ViewerHistoryRow(int WatchDuration, decimal Progress);
    private sealed class ExploreCategoryRow
    {
        public Guid VideoId { get; init; }
        public Guid ChannelId { get; init; }
        public string ChannelName { get; init; } = "";
        public string ChannelHandle { get; init; } = "";
        public Guid? CategoryId { get; init; }
        public string Title { get; init; } = "";
        public string? ThumbnailUrl { get; init; }
        public int Duration { get; init; }
        public string Visibility { get; init; } = "public";
        public DateTimeOffset? PublishedAt { get; init; }
        public long Views { get; init; }
        public int CategoryRank { get; init; }
        public int GlobalRank { get; init; }
    }
    private sealed class FeaturedChannelRow
    {
        public Guid ChannelId { get; init; }
        public string Name { get; init; } = "";
        public string Handle { get; init; } = "";
        public string? AvatarUrl { get; init; }
        public long SubscriberCount { get; init; }
    }
    private static readonly TimeSpan ViewSessionCooldown = TimeSpan.FromMinutes(30);
    private DateTimeOffset Now => clock.GetUtcNow();

    public async Task<ExploreHubResponse> GetExploreHubAsync(CancellationToken ct = default)
    {
        // Keep both category top-3 and global top-12 in one SQL window query.
        // PostgreSQL executes ROW_NUMBER() OVER (PARTITION BY category_id ...)
        // server-side; EF Core cannot translate the equivalent LINQ shape.
        var exploreRows = await db.Database.SqlQuery<ExploreCategoryRow>($"""
            WITH view_counts AS (
                SELECT video_id, COUNT(*)::bigint AS views
                FROM public.viewing_histories
                GROUP BY video_id
            ), public_rows AS (
                SELECT
                    video.video_id AS "VideoId",
                    video.channel_id AS "ChannelId",
                    channel.name AS "ChannelName",
                    channel.handle AS "ChannelHandle",
                    video.category_id AS "CategoryId",
                    video.title AS "Title",
                    video.thumbnail_url AS "ThumbnailUrl",
                    video.duration AS "Duration",
                    video.visibility AS "Visibility",
                    video.published_at AS "PublishedAt",
                    COALESCE(view_counts.views, 0)::bigint AS "Views"
                FROM public.videos AS video
                INNER JOIN public.channels AS channel ON channel.channel_id = video.channel_id
                LEFT JOIN view_counts ON view_counts.video_id = video.video_id
                WHERE video.status = 'published'
                  AND video.moderation_status = 'approved'
                  AND video.visibility = 'public'
            ), ranked AS (
                SELECT public_rows.*,
                       ROW_NUMBER() OVER (
                           PARTITION BY "CategoryId"
                           ORDER BY "Views" DESC, "PublishedAt" DESC NULLS LAST, "VideoId"
                       )::int AS "CategoryRank",
                       ROW_NUMBER() OVER (
                           ORDER BY "Views" DESC, "PublishedAt" DESC NULLS LAST, "VideoId"
                       )::int AS "GlobalRank"
                FROM public_rows
            )
            SELECT "VideoId", "ChannelId", "ChannelName", "ChannelHandle", "CategoryId",
                   "Title", "ThumbnailUrl", "Duration", "Visibility", "PublishedAt", "Views",
                   "CategoryRank", "GlobalRank"
            FROM ranked
            WHERE ("CategoryId" IS NOT NULL AND "CategoryRank" <= 3) OR "GlobalRank" <= 12
            """).ToListAsync(ct);
        var categoryRows = exploreRows.Where(row => row.CategoryId.HasValue && row.CategoryRank <= 3).ToList();
        var exploreUrls = await ResolveReadUrlsAsync(categoryRows.Select(row => row.ThumbnailUrl), ct);
        var categoryIds = categoryRows.Select(row => row.CategoryId!.Value).Distinct().ToArray();
        var categories = await db.Categories.AsNoTracking()
            .Where(category => categoryIds.Contains(category.CategoryId) && category.Status == "active")
            .ToDictionaryAsync(category => category.CategoryId, ct);
        var rankings = categoryRows
            .Where(row => categories.ContainsKey(row.CategoryId!.Value))
            .GroupBy(row => row.CategoryId!.Value)
            .OrderBy(group => categories[group.Key].Name)
            .Take(8)
            .Select(group => new CategoryRankingGroup(group.Key, categories[group.Key].Name, categories[group.Key].Slug,
                group.Select(row => new VideoCardResponse(row.VideoId, row.ChannelId, row.ChannelName, row.ChannelHandle,
                    row.Title, row.ThumbnailUrl == null ? null : exploreUrls.GetValueOrDefault(row.ThumbnailUrl),
                    row.Duration, row.Visibility, row.PublishedAt, row.Views)).ToList()))
            .ToList();

        // Use one global top-12 result for both the ranking block and trending.
        var topRows = exploreRows.Where(row => row.GlobalRank <= 12)
            .OrderBy(row => row.GlobalRank).ToList();
        foreach (var path in topRows.Select(row => row.ThumbnailUrl).Where(path => path != null && !exploreUrls.ContainsKey(path!)))
            exploreUrls[path!] = await ReadUrlAsync(path!, ct);
        var topCards = topRows.Select(row => new VideoCardResponse(row.VideoId, row.ChannelId, row.ChannelName,
            row.ChannelHandle, row.Title, row.ThumbnailUrl == null ? null : exploreUrls.GetValueOrDefault(row.ThumbnailUrl),
            row.Duration, row.Visibility, row.PublishedAt, row.Views)).ToList();

        // Featured creators use the same pre-aggregated counts without relying on
        // an EF left-join null conditional in ORDER BY/WHERE (unsupported by the
        // provider version used by this project).
        var topChannels = await db.Database.SqlQuery<FeaturedChannelRow>($"""
            WITH subscriber_counts AS (
                SELECT channel_id, COUNT(*)::bigint AS count
                FROM public.subscriptions
                WHERE status = 'active'
                GROUP BY channel_id
            ), video_counts AS (
                SELECT channel_id, COUNT(*)::bigint AS count
                FROM public.videos
                WHERE status = 'published' AND moderation_status = 'approved'
                GROUP BY channel_id
            )
            SELECT channel.channel_id AS "ChannelId",
                   channel.name AS "Name",
                   channel.handle AS "Handle",
                   channel.avatar_url AS "AvatarUrl",
                   COALESCE(subscriber_counts.count, 0)::bigint AS "SubscriberCount"
            FROM public.channels AS channel
            LEFT JOIN subscriber_counts ON subscriber_counts.channel_id = channel.channel_id
            LEFT JOIN video_counts ON video_counts.channel_id = channel.channel_id
            WHERE channel.status = 'active'
              AND (COALESCE(subscriber_counts.count, 0) > 0 OR COALESCE(video_counts.count, 0) > 0)
            ORDER BY COALESCE(subscriber_counts.count, 0) DESC,
                     COALESCE(video_counts.count, 0) DESC,
                     channel.created_at DESC
            LIMIT 5
            """).ToListAsync(ct);

        var creators = new List<FeaturedCreatorResponse>();
        foreach (var ch in topChannels)
        {
            var avatar = ch.AvatarUrl == null ? null : await ReadUrlAsync(ch.AvatarUrl, ct);
            creators.Add(new(ch.ChannelId, ch.Name, ch.Handle, avatar, ch.SubscriberCount, true));
        }

        var trendingCards = topCards.Take(10).ToList();
        return new ExploreHubResponse(rankings, creators, trendingCards, topCards);
    }

    public async Task<IReadOnlyList<CategoryResponse>> GetCategoriesAsync(CancellationToken ct = default) =>
        await db.Categories.AsNoTracking().Where(x => x.Status == "active").OrderBy(x => x.Name)
            .Select(x => new CategoryResponse(x.CategoryId, x.Name, x.Slug, x.Description)).ToListAsync(ct);

    public async Task<PageResult<VideoCardResponse>> GetFeedAsync(
        string feed,
        string? sort,
        Guid? categoryId,
        string? tag,
        int page,
        int pageSize,
        Guid? currentUserId = null,
        CancellationToken ct = default)
    {
        (page, pageSize) = Page(page, pageSize);
        // Read the current viewing history for every home/recommended page. A model snapshot
        // cannot know about views recorded after it was trained.
        var hideViewed = currentUserId.HasValue && string.Equals(feed, "home", StringComparison.OrdinalIgnoreCase);
        var viewedIds = hideViewed
            ? await db.ViewingHistories.AsNoTracking().Where(x => x.UserId == currentUserId!.Value)
                .GroupBy(x => x.VideoId)
                .Select(group => new { VideoId = group.Key, LastViewedAt = group.Max(x => x.ViewedAt) })
                .OrderByDescending(x => x.LastViewedAt).Take(5000)
                .Select(x => x.VideoId).ToListAsync(ct)
            : [];

        // Use the model across every home/recommended page, with live exclusions.
        if (string.Equals(feed, "home", StringComparison.OrdinalIgnoreCase)
            && currentUserId.HasValue
            && !categoryId.HasValue
            && string.IsNullOrWhiteSpace(tag)
            && recommendationClient.IsEnabled)
        {
            try
            {
                var recommended = await recommendationClient.GetRecommendationsAsync(currentUserId.Value, (int)Math.Min((long)page * pageSize, 100), viewedIds, ct);
                if (recommended != null && recommended.Count > 0)
                {
                    var recIds = recommended.Select(r => r.VideoId).Where(id => !viewedIds.Contains(id)).ToList();
                    var recViewCounts = db.ViewingHistories.AsNoTracking()
                        .Where(history => recIds.Contains(history.VideoId))
                        .GroupBy(history => history.VideoId)
                        .Select(group => new { VideoId = group.Key, Views = group.LongCount() });
                    var recVideos = await (from video in db.Videos.AsNoTracking()
                                           join channel in db.Channels.AsNoTracking() on video.ChannelId equals channel.ChannelId
                                           join views in recViewCounts on video.VideoId equals views.VideoId into viewRows
                                           from views in viewRows.DefaultIfEmpty()
                                           where recIds.Contains(video.VideoId)
                                                 && !db.ViewingHistories.Any(history => history.UserId == currentUserId!.Value && history.VideoId == video.VideoId)
                                                 && video.Status == "published"
                                                 && video.ModerationStatus == "approved"
                                                 && video.Visibility == "public"
                                           select new
                                           {
                                               video.VideoId,
                                               video.ChannelId,
                                               ChannelName = channel.Name,
                                               ChannelHandle = channel.Handle,
                                               video.Title,
                                               video.ThumbnailUrl,
                                               video.Duration,
                                               video.Visibility,
                                               video.PublishedAt,
                                               Views = (long?)views.Views
                                           }).ToListAsync(ct);

                    // Sắp xếp các video theo đúng thứ tự điểm ranking mà Model đề xuất
                    var orderedVideos = recIds
                        .Select(id => recVideos.FirstOrDefault(v => v.VideoId == id))
                        .Where(v => v != null)
                        .ToList();

                    if (orderedVideos.Count > 0)
                    {
                        var pageVideos = orderedVideos.Skip((int)Math.Min((long)(page - 1) * pageSize, int.MaxValue)).Take(pageSize).ToList();
                        // Nếu số lượng video đề xuất ít hơn pageSize, bù thêm video phổ biến chưa có trong danh sách
                        if (pageVideos.Count < pageSize)
                        {
                            var existingIds = orderedVideos.Select(v => v!.VideoId).ToHashSet();
                            var fallbackCount = pageSize - pageVideos.Count;
                            var fallbackSkip = (int)Math.Min(Math.Max(0L, (long)(page - 1) * pageSize - orderedVideos.Count), int.MaxValue);
                            var fallbackViewCounts = db.ViewingHistories.AsNoTracking()
                                .GroupBy(history => history.VideoId)
                                .Select(group => new { VideoId = group.Key, Views = group.LongCount() });
                            var fallbackQuery = from video in db.Videos.AsNoTracking()
                                                join channel in db.Channels.AsNoTracking() on video.ChannelId equals channel.ChannelId
                                                join views in fallbackViewCounts on video.VideoId equals views.VideoId into viewRows
                                                from views in viewRows.DefaultIfEmpty()
                                                where !existingIds.Contains(video.VideoId)
                                                      && !db.ViewingHistories.Any(history => history.UserId == currentUserId!.Value && history.VideoId == video.VideoId)
                                                      && video.Status == "published"
                                                      && video.ModerationStatus == "approved"
                                                      && video.Visibility == "public"
                                                select new
                                                {
                                                    video.VideoId,
                                                    video.ChannelId,
                                                    ChannelName = channel.Name,
                                                    ChannelHandle = channel.Handle,
                                                    video.Title,
                                                    video.ThumbnailUrl,
                                                    video.Duration,
                                                    video.Visibility,
                                                    video.PublishedAt,
                                                    Views = (long?)views.Views
                                                };
                            var fallbackVideos = await fallbackQuery
                                .OrderByDescending(row => row.Views ?? 0L).ThenByDescending(row => row.PublishedAt)
                                .Skip(fallbackSkip).Take(fallbackCount).ToListAsync(ct);

                            pageVideos.AddRange(fallbackVideos);
                        }

                        var cardsList = new List<VideoCardResponse>(pageVideos.Count);
                        foreach (var row in pageVideos)
                        {
                            cardsList.Add(new(row!.VideoId, row.ChannelId, row.ChannelName, row.ChannelHandle,
                                row.Title, row.ThumbnailUrl == null ? null : await ReadUrlAsync(row.ThumbnailUrl, ct),
                                row.Duration, row.Visibility, row.PublishedAt, row.Views ?? 0L));
                        }

                        var totalCount = await db.Videos.AsNoTracking()
                            .Where(x => x.Status == "published" && x.ModerationStatus == "approved" && x.Visibility == "public")
                            .Where(x => !db.ViewingHistories.Any(history => history.UserId == currentUserId!.Value && history.VideoId == x.VideoId))
                            .CountAsync(ct);
                        return new(cardsList, page, pageSize, totalCount);
                    }
                }
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Error while processing personalized feed for user {UserId}. Falling back to default feed.", currentUserId.Value);
            }
        }

        var query = db.Videos.AsNoTracking().Where(x => x.Status == "published" && x.ModerationStatus == "approved" && x.Visibility == "public");
        if (hideViewed)
            query = query.Where(x => !db.ViewingHistories.Any(history => history.UserId == currentUserId!.Value && history.VideoId == x.VideoId));
        if (categoryId.HasValue) query = query.Where(x => x.CategoryId == categoryId);
        if (!string.IsNullOrWhiteSpace(tag))
        {
            var normalizedTag = tag.Trim();
            query = query.Where(x => db.VideoTags.Any(videoTag => videoTag.VideoId == x.VideoId &&
                db.Tags.Any(tagRow => tagRow.TagId == videoTag.TagId && EF.Functions.ILike(tagRow.Name, normalizedTag))));
        }
        var filteredTotal = await query.CountAsync(ct);
        var hasColdStartFilter = categoryId.HasValue || !string.IsNullOrWhiteSpace(tag);
        var fallbackToDefault = hasColdStartFilter && filteredTotal == 0;
        var total = filteredTotal;
        if (fallbackToDefault)
        {
            // Guest cold-start falls back from Category/Tag to the public newest/popular catalogue.
            query = db.Videos.AsNoTracking().Where(x => x.Status == "published" && x.ModerationStatus == "approved" && x.Visibility == "public");
            if (hideViewed)
                query = query.Where(x => !db.ViewingHistories.Any(history => history.UserId == currentUserId!.Value && history.VideoId == x.VideoId));
            total = await query.CountAsync(ct);
        }
        var feedViewCounts = db.ViewingHistories.AsNoTracking().GroupBy(x => x.VideoId)
            .Select(group => new { VideoId = group.Key, Count = group.LongCount() });
        var rows = from video in query
                   join channel in db.Channels.AsNoTracking() on video.ChannelId equals channel.ChannelId
                   join view in feedViewCounts on video.VideoId equals view.VideoId into viewRows
                   from view in viewRows.DefaultIfEmpty()
                   select new { video.VideoId, video.ChannelId, ChannelName = channel.Name, ChannelHandle = channel.Handle,
                       video.Title, video.ThumbnailUrl, video.Duration, video.Visibility, video.PublishedAt,
                       Views = (long?)view.Count };
        rows = (feed.ToLowerInvariant(), sort?.ToLowerInvariant()) switch
        {
            ("home", _) => rows.OrderByDescending(x => x.Views ?? 0L).ThenByDescending(x => x.PublishedAt),
            (_, "popular") => rows.OrderByDescending(x => x.Views ?? 0L).ThenByDescending(x => x.PublishedAt),
            (_, "trending") => rows.OrderByDescending(x => x.Views ?? 0L).ThenByDescending(x => x.PublishedAt),
            _ => rows.OrderByDescending(x => x.PublishedAt)
        };
        var pageRows = await rows.Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        var cards = new List<VideoCardResponse>();
        foreach (var row in pageRows) cards.Add(new(row.VideoId, row.ChannelId, row.ChannelName, row.ChannelHandle,
            row.Title, row.ThumbnailUrl == null ? null : await ReadUrlAsync(row.ThumbnailUrl, ct), row.Duration, row.Visibility, row.PublishedAt, row.Views ?? 0L));
        return new(cards, page, pageSize, total);
    }

    public async Task<PageResult<VideoCardResponse>> GetSubscriptionsFeedAsync(Guid userId, int page, int pageSize, CancellationToken ct = default)
    {
        var (p, size) = Page(page, pageSize);
        var subscribedChannelIds = db.Subscriptions.AsNoTracking()
            .Where(s => s.UserId == userId && s.Status == "active")
            .Select(s => s.ChannelId)
            .Distinct();

        if (!await subscribedChannelIds.AnyAsync(ct))
        {
            return new([], p, size, 0);
        }

        var query = db.Videos.AsNoTracking()
            .Where(x => subscribedChannelIds.Contains(x.ChannelId) && x.Status == "published" && x.ModerationStatus == "approved" && x.Visibility == "public");

        var total = await query.CountAsync(ct);
        var subscriptionViewCounts = db.ViewingHistories.AsNoTracking().GroupBy(history => history.VideoId)
            .Select(group => new { VideoId = group.Key, Count = group.LongCount() });
        var rows = from video in query
                   join channel in db.Channels.AsNoTracking() on video.ChannelId equals channel.ChannelId
                   join view in subscriptionViewCounts on video.VideoId equals view.VideoId into viewRows
                   from view in viewRows.DefaultIfEmpty()
                   orderby video.PublishedAt descending
                   select new
                   {
                       video.VideoId,
                       video.ChannelId,
                       ChannelName = channel.Name,
                       ChannelHandle = channel.Handle,
                       video.Title,
                       video.ThumbnailUrl,
                       video.Duration,
                       video.Visibility,
                       video.PublishedAt,
                        Views = (long?)view.Count
                   };

        var pageRows = await rows.Skip((p - 1) * size).Take(size).ToListAsync(ct);
        var cards = new List<VideoCardResponse>();
        foreach (var row in pageRows)
        {
            cards.Add(new(row.VideoId, row.ChannelId, row.ChannelName, row.ChannelHandle,
                row.Title, row.ThumbnailUrl == null ? null : await ReadUrlAsync(row.ThumbnailUrl, ct), row.Duration, row.Visibility, row.PublishedAt, row.Views ?? 0L));
        }
        return new(cards, p, size, total);
    }

    public async Task<PageResult<VideoCardResponse>> SearchVideosAsync(SearchVideosQuery search, CancellationToken ct = default)
    {
        var (page, pageSize) = Page(search.Page, search.PageSize);
        var query = db.Videos.AsNoTracking().Where(x => x.Status == "published" && x.ModerationStatus == "approved" && x.Visibility == "public");

        var term = search.Query?.Trim();
        var cleanTerm = term?.TrimStart('@');
        if (!string.IsNullOrWhiteSpace(term))
        {
            var tokens = term.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (tokens.Length <= 1)
            {
                query = query.Where(x =>
                    EF.Functions.ILike(x.Title, $"%{term}%") ||
                    (x.Description != null && EF.Functions.ILike(x.Description, $"%{term}%")) ||
                    db.Channels.Any(c => c.ChannelId == x.ChannelId && (
                        EF.Functions.ILike(c.Name, $"%{term}%") ||
                        EF.Functions.ILike(c.Handle, $"%{term}%") ||
                        (cleanTerm != null && EF.Functions.ILike(c.Handle, $"%{cleanTerm}%")))) ||
                    db.VideoTags.Any(vt => vt.VideoId == x.VideoId && db.Tags.Any(t => t.TagId == vt.TagId && EF.Functions.ILike(t.Name, $"%{term}%")))
                );
            }
            else
            {
                foreach (var token in tokens)
                {
                    var t = token.TrimStart('@');
                    query = query.Where(x =>
                        EF.Functions.ILike(x.Title, $"%{token}%") ||
                        (x.Description != null && EF.Functions.ILike(x.Description, $"%{token}%")) ||
                        db.Channels.Any(c => c.ChannelId == x.ChannelId && (
                            EF.Functions.ILike(c.Name, $"%{token}%") ||
                            EF.Functions.ILike(c.Handle, $"%{token}%") ||
                            EF.Functions.ILike(c.Handle, $"%{t}%"))) ||
                        db.VideoTags.Any(vt => vt.VideoId == x.VideoId && db.Tags.Any(tTag => tTag.TagId == vt.TagId && EF.Functions.ILike(tTag.Name, $"%{token}%")))
                    );
                }
            }
        }

        if (search.CategoryId.HasValue)
        {
            query = query.Where(x => x.CategoryId == search.CategoryId.Value);
        }

        if (!string.IsNullOrWhiteSpace(search.Tag))
        {
            var normalizedTag = search.Tag.Trim().TrimStart('#');
            query = query.Where(x => db.VideoTags.Any(vt => vt.VideoId == x.VideoId &&
                db.Tags.Any(t => t.TagId == vt.TagId && EF.Functions.ILike(t.Name, normalizedTag))));
        }

        if (search.ChannelId.HasValue)
        {
            query = query.Where(x => x.ChannelId == search.ChannelId.Value);
        }

        if (!string.IsNullOrWhiteSpace(search.DateRange))
        {
            var now = Now;
            var todayUtc = new DateTimeOffset(now.UtcDateTime.Date, TimeSpan.Zero);
            var weekAgo = now.AddDays(-7);
            var monthAgo = now.AddDays(-30);
            var yearAgo = now.AddDays(-365);

            query = search.DateRange.Trim().ToLowerInvariant() switch
            {
                "today" or "day" => query.Where(x => x.PublishedAt.HasValue && x.PublishedAt.Value >= todayUtc),
                "this_week" or "week" => query.Where(x => x.PublishedAt.HasValue && x.PublishedAt.Value >= weekAgo),
                "this_month" or "month" => query.Where(x => x.PublishedAt.HasValue && x.PublishedAt.Value >= monthAgo),
                "this_year" or "year" => query.Where(x => x.PublishedAt.HasValue && x.PublishedAt.Value >= yearAgo),
                _ => query
            };
        }

        if (!string.IsNullOrWhiteSpace(search.DurationRange))
        {
            query = search.DurationRange.Trim().ToLowerInvariant() switch
            {
                "short" => query.Where(x => x.Duration < 240),
                "medium" => query.Where(x => x.Duration >= 240 && x.Duration <= 1200),
                "long" => query.Where(x => x.Duration > 1200),
                _ => query
            };
        }

        var total = await query.CountAsync(ct);

        var viewCounts = db.ViewingHistories.AsNoTracking().GroupBy(x => x.VideoId)
            .Select(group => new { VideoId = group.Key, Count = group.LongCount() });
        var likeCounts = db.VideoReactions.AsNoTracking().Where(x => x.Type == "like").GroupBy(x => x.VideoId)
            .Select(group => new { VideoId = group.Key, Count = group.LongCount() });
        var commentCounts = db.Comments.AsNoTracking().Where(x => x.Status == "visible").GroupBy(x => x.VideoId)
            .Select(group => new { VideoId = group.Key, Count = group.LongCount() });
        var rows = from video in query
                   join channel in db.Channels.AsNoTracking() on video.ChannelId equals channel.ChannelId
                   join view in viewCounts on video.VideoId equals view.VideoId into viewRows
                   from view in viewRows.DefaultIfEmpty()
                   join like in likeCounts on video.VideoId equals like.VideoId into likeRows
                   from like in likeRows.DefaultIfEmpty()
                   join comment in commentCounts on video.VideoId equals comment.VideoId into commentRows
                   from comment in commentRows.DefaultIfEmpty()
                   select new
                   {
                       video.VideoId,
                       video.ChannelId,
                       ChannelName = channel.Name,
                       ChannelHandle = channel.Handle,
                       video.Title,
                       video.ThumbnailUrl,
                       video.Duration,
                       video.Visibility,
                       video.PublishedAt,
                       Views = (long?)view.Count,
                       Likes = (long?)like.Count,
                       Comments = (long?)comment.Count
                   };

        var sort = search.Sort?.Trim().ToLowerInvariant() ?? "relevance";
        rows = sort switch
        {
            "newest" => rows.OrderByDescending(x => x.PublishedAt),
            "views" or "popular" => rows.OrderByDescending(x => x.Views ?? 0L).ThenByDescending(x => x.PublishedAt),
            "engagement" => rows.OrderByDescending(x => (x.Likes ?? 0L) + (x.Comments ?? 0L)).ThenByDescending(x => x.Views ?? 0L),
            "random" => rows.OrderBy(_ => EF.Functions.Random()),
            _ when !string.IsNullOrWhiteSpace(term) =>
                rows.OrderByDescending(x => EF.Functions.ILike(x.Title, $"{term}%"))
                    .ThenByDescending(x => EF.Functions.ILike(x.Title, $"%{term}%"))
                    .ThenByDescending(x => EF.Functions.ILike(x.ChannelName, $"%{term}%") || (cleanTerm != null && EF.Functions.ILike(x.ChannelHandle, $"%{cleanTerm}%")))
                    .ThenByDescending(x => x.Views ?? 0L)
                    .ThenByDescending(x => x.PublishedAt),
            _ => rows.OrderByDescending(x => x.Views ?? 0L).ThenByDescending(x => x.PublishedAt)
        };

        var pageRows = await rows.Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        var cards = new List<VideoCardResponse>();
        foreach (var row in pageRows)
        {
            cards.Add(new(
                row.VideoId,
                row.ChannelId,
                row.ChannelName,
                row.ChannelHandle,
                row.Title,
                row.ThumbnailUrl == null ? null : await ReadUrlAsync(row.ThumbnailUrl, ct),
                row.Duration,
                row.Visibility,
                row.PublishedAt,
                row.Views ?? 0L));
        }

        return new(cards, page, pageSize, total);
    }

    public async Task<PageResult<WatchHistoryResponse>> GetWatchHistoryAsync(Guid userId, int page, int pageSize,
        DateTimeOffset? before = null, CancellationToken ct = default)
    {
        (page, pageSize) = Page(page, pageSize);
        var windowEnd = before.HasValue && before.Value < Now ? before.Value : Now;
        var windowStart = windowEnd.AddDays(-30);
        // Keep only the newest row for each video. A correlated NOT EXISTS is
        // translated reliably by PostgreSQL, unlike joining a GroupBy/First
        // projection to the video query.
        var latest = db.ViewingHistories.AsNoTracking()
            .Where(history => history.UserId == userId)
            .Where(history => !db.ViewingHistories.Any(other =>
                other.UserId == userId &&
                other.VideoId == history.VideoId &&
                  (other.ViewedAt > history.ViewedAt ||
                  (other.ViewedAt == history.ViewedAt && other.ViewingHistoryId > history.ViewingHistoryId))));
        latest = latest.Where(history => history.ViewedAt >= windowStart && history.ViewedAt < windowEnd);
        var query = from history in latest
                    join video in LibraryVisibleVideos(userId) on history.VideoId equals video.VideoId
                    join channel in db.Channels.AsNoTracking() on video.ChannelId equals channel.ChannelId
                    orderby history.ViewedAt descending
                    select new { video.VideoId, video.ChannelId, ChannelName = channel.Name, ChannelHandle = channel.Handle,
                        video.Title, video.ThumbnailUrl, video.Duration, history.WatchDuration, history.Progress, history.ViewedAt };

        var total = await query.CountAsync(ct);
        var rows = await query.Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        var items = new List<WatchHistoryResponse>(rows.Count);
        foreach (var row in rows)
        {
            items.Add(new(row.VideoId, row.ChannelId, row.ChannelName, row.ChannelHandle, row.Title,
                row.ThumbnailUrl == null ? null : await ReadUrlAsync(row.ThumbnailUrl, ct), row.Duration,
                row.WatchDuration, row.Progress, row.ViewedAt));
        }

        return new(items, page, pageSize, total);
    }

    public async Task ClearWatchHistoryAsync(Guid userId, CancellationToken ct = default)
    {
        var items = await db.ViewingHistories.Where(x => x.UserId == userId).ToListAsync(ct);
        if (items.Count > 0)
        {
            db.ViewingHistories.RemoveRange(items);
            await db.SaveChangesAsync(ct);
        }
    }

    public async Task DeleteWatchHistoryItemAsync(Guid userId, Guid videoId, CancellationToken ct = default)
    {
        var items = await db.ViewingHistories.Where(x => x.UserId == userId && x.VideoId == videoId).ToListAsync(ct);
        if (items.Count > 0)
        {
            db.ViewingHistories.RemoveRange(items);
            await db.SaveChangesAsync(ct);
        }
    }

    public async Task<PageResult<LibraryVideoResponse>> GetLikedVideosAsync(Guid userId, int? rating, int page, int pageSize, CancellationToken ct = default)
    {
        if (rating is < 1 or > 5)
            throw Error(400, "INVALID_RATING_FILTER", "Bộ lọc đánh giá phải từ 1 đến 5 sao.");

        (page, pageSize) = Page(page, pageSize);
        var query = from reaction in db.VideoReactions.AsNoTracking()
                    where reaction.UserId == userId && reaction.Type == "like"
                    join video in LibraryVisibleVideos(userId) on reaction.VideoId equals video.VideoId
                    select new { Video = video, reaction.UpdatedAt };
        if (rating.HasValue)
        {
            var selectedRating = rating.Value;
            query = query.Where(row => db.VideoRatings.Any(videoRating =>
                videoRating.UserId == userId && videoRating.VideoId == row.Video.VideoId && videoRating.Score == selectedRating));
        }
        query = query.OrderByDescending(row => row.UpdatedAt);

        var total = await query.CountAsync(ct);
        var rows = await query.Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        var details = await ToResponsesAsync(rows.Select(row => row.Video).ToList(), userId, ct);
        var detailById = details.ToDictionary(detail => detail.VideoId);
        var items = new List<LibraryVideoResponse>(rows.Count);
        foreach (var row in rows)
        {
            var detail = detailById[row.Video.VideoId];
            var state = detail.ViewerState;
            items.Add(ToLibraryResponse(detail, state?.ResumeAtSeconds ?? 0, state?.Progress ?? 0, row.UpdatedAt));
        }

        return new(items, page, pageSize, total);
    }

    public async Task<VideoResponse> GetVideoAsync(Guid videoId, Guid? viewerId, CancellationToken ct = default)
    {
        var video = await RequireVideoAsync(videoId, ct);
        await EnsureCanViewAsync(video, viewerId, ct);
        return await ToResponseAsync(video, viewerId, ct);
    }

    public async Task<PlaybackResponse> GetPlaybackAsync(Guid videoId, Guid? viewerId, CancellationToken ct = default)
    {
        var video = await RequireVideoAsync(videoId, ct);
        await EnsureCanViewAsync(video, viewerId, ct);
        var maxHeight = viewerId.HasValue ? await MaxDownloadHeightAsync(viewerId.Value, ct) : 720;
        var renditionRows = await db.VideoRenditions.AsNoTracking().Where(x => x.VideoId == videoId && x.Status == "ready" && x.Height <= maxHeight).OrderBy(x => x.Height).ToListAsync(ct);
        var renditions = new List<RenditionResponse>();
        foreach (var row in renditionRows) renditions.Add(new(row.QualityLabel, row.Width, row.Height, row.FileSize, await ReadUrlAsync(row.FileUrl, ct)));
        var history = viewerId.HasValue ? await db.ViewingHistories.AsNoTracking().Where(x => x.UserId == viewerId && x.VideoId == videoId)
            .OrderByDescending(x => x.ViewedAt).FirstOrDefaultAsync(ct) : null;
        return new(video.VideoId, video.Title, video.Visibility, video.Duration, renditions, history?.WatchDuration ?? 0, history?.Progress ?? 0);
    }

    public async Task<VideoResponse> CreateVideoAsync(Guid actorId, CreateVideoCommand command, CancellationToken ct = default)
    {
        var channel = await RequireChannelPermissionAsync(command.ChannelId, actorId, ChannelPermissions.VideoUpload, ct);
        var idempotencyKey = command.IdempotencyKey?.Trim();
        if (idempotencyKey is { Length: > 128 }) throw Error(400, "INVALID_IDEMPOTENCY_KEY", "Idempotency-Key không được vượt quá 128 ký tự.");
        if (!string.IsNullOrWhiteSpace(idempotencyKey))
        {
            var previous = await db.Videos.AsNoTracking().SingleOrDefaultAsync(x => x.ChannelId == command.ChannelId && x.IdempotencyKey == idempotencyKey, ct);
            if (previous != null) return await ToResponseAsync(previous, actorId, ct);
        }
        if (string.IsNullOrWhiteSpace(command.Title) || command.Title.Trim().Length > 100)
            throw Error(400, "INVALID_TITLE", "Tiêu đề cần từ 1 đến 100 ký tự.");
        if (command.Duration <= 0) throw Error(400, "INVALID_DURATION", "Thời lượng video phải lớn hơn 0.");
        VideoRules.ValidateVisibility(command.Visibility);
        EnsureVisibilityAvailable(command.Visibility);
        if (command.CategoryId.HasValue && !await db.Categories.AnyAsync(x => x.CategoryId == command.CategoryId && x.Status == "active", ct))
            throw Error(400, "INVALID_CATEGORY", "Danh mục không tồn tại hoặc đã ngừng hoạt động.");

        await PreflightAsync(actorId, new(command.ChannelId, command.FileSize, command.Duration, command.ContentType, command.SourceQuality), ct);

        var quota = await db.ChannelQuotas.SingleOrDefaultAsync(x => x.ChannelId == channel.ChannelId, ct);
        // Upload limits belong to the channel owner’s subscription. A Manager/Editor
        // may upload on behalf of the channel, but must not downgrade or bypass the
        // owner’s quota simply because the actor has a different plan.
        if (quota != null)
        {
            if (!ChannelQuotaRules.CanReserve(quota.StorageUsed, command.FileSize, quota.StorageLimit))
                throw Error(409, "CHANNEL_QUOTA_EXCEEDED", "Kênh không còn đủ dung lượng lưu trữ.");
        }

        IReadOnlyList<VideoChapter> chapters;
        try { chapters = VideoRules.ValidateChapters(command.Chapters.Select(x => new VideoChapter(x.StartSeconds, x.Title)), command.Duration); }
        catch (VideoValidationException ex) { throw Error(400, ex.Code, ex.Message); }
        var tags = NormalizeTags(command.Tags);
        var temporaryDirectory = Path.Combine(Path.GetTempPath(), "hutube-video-processing", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(temporaryDirectory);
        var sourceExtension = Path.GetExtension(command.FileName);
        if (string.IsNullOrWhiteSpace(sourceExtension)) sourceExtension = ".mp4";
        var sourceFile = Path.Combine(temporaryDirectory, "source" + sourceExtension);
        string? videoUrl = null;
        string? thumbnailUrl = null;
        try
        {
            await using (var local = File.Create(sourceFile)) await command.Content.CopyToAsync(local, ct);
            if (command.ThumbnailContent != null && command.ThumbnailFileName != null && command.ThumbnailContentType != null)
                thumbnailUrl = await storage.SaveFileAsync("video-thumbnails", command.ThumbnailFileName, command.ThumbnailContent, command.ThumbnailContentType, ct);
            else
            {
                string? generatedThumbnailPath = null;
                try
                {
                    generatedThumbnailPath = await transcoder.CreateThumbnailAsync(sourceFile, temporaryDirectory, ct);
                }
                catch (OperationCanceledException) { throw; }
                catch (Exception ex)
                {
                    // A thumbnail is optional; a missing FFmpeg binary or an
                    // unsupported codec must not discard an otherwise valid upload.
                    logger.LogWarning(ex, "Không thể tự tạo thumbnail cho video {FileName}; tiếp tục upload không có thumbnail.", command.FileName);
                }
                if (!string.IsNullOrWhiteSpace(generatedThumbnailPath))
                {
                    await using var generatedThumbnail = File.OpenRead(generatedThumbnailPath);
                    thumbnailUrl = await storage.SaveFileAsync(
                        "video-thumbnails", $"{Guid.NewGuid():N}.jpg", generatedThumbnail, "image/jpeg", ct);
                }
            }
            await using (var local = File.OpenRead(sourceFile))
                videoUrl = await storage.SaveVideoAsync("videos", command.FileName, local, command.ContentType, ct);
        }
        catch
        {
            if (videoUrl != null) await storage.DeleteFileAsync(videoUrl, CancellationToken.None);
            if (thumbnailUrl != null) await storage.DeleteFileAsync(thumbnailUrl, CancellationToken.None);
            try { Directory.Delete(temporaryDirectory, true); }
            catch (IOException ex) { logger.LogWarning(ex, "Không thể xóa thư mục xử lý video {Directory}", temporaryDirectory); }
            throw;
        }

        var now = Now;
        var publicUploadRequiresModeration = features.ModerationEnabled
            && command.Visibility.Equals("public", StringComparison.OrdinalIgnoreCase);
        var video = new Video { ChannelId = command.ChannelId, UploadedByUserId = actorId, CategoryId = command.CategoryId, Title = command.Title.Trim(), Description = Clean(command.Description),
            VideoUrl = videoUrl!, ThumbnailUrl = thumbnailUrl, Duration = command.Duration, FileSize = command.FileSize, Visibility = command.Visibility.ToLowerInvariant(),
            Status = "processing", LanguageCode = Clean(command.LanguageCode), AgeRestricted = command.AgeRestricted,
            ModerationStatus = publicUploadRequiresModeration ? "pending" : "not_submitted",
            IdempotencyKey = string.IsNullOrWhiteSpace(idempotencyKey) ? null : idempotencyKey,
            Metadata = PersistenceJson.Serialize(new { chapters }), CreatedAt = now, UpdatedAt = now };
        var generated = new List<(TranscodedVideo Rendition, string StoredPath)>();
        Exception? processingError = null;
        var deferredProcessingQueued = false;
        if (command.GenerateLowerRenditions && !command.DeferLowerRenditions)
        {
            try
            {
                foreach (var rendition in await transcoder.CreateLowerRenditionsAsync(sourceFile, command.SourceQuality, temporaryDirectory, ct))
                {
                    await using var renditionStream = File.OpenRead(rendition.FilePath);
                    var storedPath = await storage.SaveVideoAsync($"video-renditions/{video.VideoId:N}", $"{rendition.Quality}.mp4", renditionStream, "video/mp4", ct);
                    generated.Add((rendition, storedPath));
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                processingError = ex;
                logger.LogError(ex, "Không thể tạo đủ rendition cho video {VideoId}", video.VideoId);
            }
        }

        await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        try
        {
            if (quota != null)
            {
                if (!ChannelQuotaRules.CanReserve(quota.StorageUsed, command.FileSize, quota.StorageLimit))
                    throw Error(409, "CHANNEL_QUOTA_EXCEEDED", "Kênh không còn đủ dung lượng lưu trữ.");
                quota.StorageUsed += command.FileSize;
                quota.UpdatedAt = now;
            }
            db.Videos.Add(video);
            await db.SaveChangesAsync(ct);

            if (publicUploadRequiresModeration)
                db.ModerationCases.Add(CreateUploadModerationCase(video, now));

            var sourceHeight = VideoRules.QualityHeight(command.SourceQuality);
            db.VideoRenditions.Add(new VideoRendition { VideoId = video.VideoId, QualityLabel = command.SourceQuality.ToLowerInvariant(), Width = sourceHeight * 16 / 9,
                Height = sourceHeight, FileUrl = videoUrl!, FileSize = command.FileSize, Codec = "source", Status = "ready", CreatedAt = now, UpdatedAt = now });
            if (command.DeferLowerRenditions)
            {
                foreach (var quality in VideoRules.LowerQualities(command.SourceQuality))
                {
                    var height = VideoRules.QualityHeight(quality);
                    db.VideoRenditions.Add(new VideoRendition { VideoId = video.VideoId, QualityLabel = quality, Width = height * 16 / 9,
                        Height = height, FileUrl = videoUrl!, FileSize = command.FileSize, Codec = "h264/aac", Status = "processing", CreatedAt = now, UpdatedAt = now });
                }
            }
            else
            {
                foreach (var item in generated)
                    db.VideoRenditions.Add(new VideoRendition { VideoId = video.VideoId, QualityLabel = item.Rendition.Quality, Width = item.Rendition.Width,
                        Height = item.Rendition.Height, BitrateKbps = item.Rendition.BitrateKbps, FileUrl = item.StoredPath, FileSize = item.Rendition.FileSize,
                        Codec = "h264/aac", Status = "ready", CreatedAt = now, UpdatedAt = now });
                if (processingError != null)
                    foreach (var quality in VideoRules.LowerQualities(command.SourceQuality).Except(generated.Select(x => x.Rendition.Quality)))
                    {
                        var height = VideoRules.QualityHeight(quality);
                        db.VideoRenditions.Add(new VideoRendition { VideoId = video.VideoId, QualityLabel = quality, Width = height * 16 / 9,
                            Height = height, FileUrl = videoUrl!, FileSize = command.FileSize, Codec = "h264/aac", Status = "failed", CreatedAt = now, UpdatedAt = now });
                    }
            }
            await ReplaceTagsAsync(video.VideoId, tags, ct); await db.SaveChangesAsync(ct); await transaction.CommitAsync(ct);
            if (command.DeferLowerRenditions)
            {
                renditionQueue.Enqueue(new DeferredVideoRenditionJob(
                    video.VideoId, sourceFile, command.SourceQuality, temporaryDirectory));
                deferredProcessingQueued = true;
            }
        }
        catch
        {
            await transaction.RollbackAsync(CancellationToken.None);
            await storage.DeleteFileAsync(videoUrl!, CancellationToken.None);
            foreach (var item in generated) await storage.DeleteFileAsync(item.StoredPath, CancellationToken.None);
            if (thumbnailUrl != null) await storage.DeleteFileAsync(thumbnailUrl, CancellationToken.None);
            throw;
        }
        finally
        {
            if (!deferredProcessingQueued)
            {
                try { Directory.Delete(temporaryDirectory, true); }
                catch (IOException ex) { logger.LogWarning(ex, "Không thể xóa thư mục xử lý video {Directory}", temporaryDirectory); }
            }
        }
        return await ToResponseAsync(video, actorId, ct);
    }

    public async Task<UploadPreflightResponse> PreflightAsync(Guid actorId, UploadPreflightRequest request, CancellationToken ct = default)
    {
        var channel = await RequireChannelPermissionAsync(request.ChannelId, actorId, ChannelPermissions.VideoUpload, ct);
        var activeStrikes = await db.ChannelStrikes.AsNoTracking()
            .Where(s => s.ChannelId == channel.ChannelId && s.Status == "active" && s.ExpiresAt > Now)
            .OrderByDescending(s => s.CreatedAt)
            .Select(s => new { s.CreatedAt, s.StrikeNumber, s.UploadRestrictedUntil, s.Reason })
            .ToListAsync(ct);
        var activeRestrictions = activeStrikes.Select(s => new
            {
                Until = s.UploadRestrictedUntil ?? s.CreatedAt.AddDays(s.StrikeNumber >= 2 ? 14 : 7),
                s.Reason
            })
            .Where(x => x.Until > Now).ToList();
        var restrictionEnd = activeRestrictions.Select(x => x.Until).DefaultIfEmpty().Max();
        if (restrictionEnd > Now)
        {
            var reason = activeRestrictions.OrderByDescending(x => x.Until).FirstOrDefault()?.Reason;
            var details = string.IsNullOrWhiteSpace(reason) ? "vi phạm chính sách" : $"lý do: {reason}";
            throw Error(403, "UPLOAD_RESTRICTED", $"Kênh đang bị tạm ngưng quyền đăng tải video đến {restrictionEnd:dd/MM/yyyy HH:mm}; {details}.");
        }

        var maxUpload = long.MaxValue;
        var maxDuration = int.MaxValue;
        var maxQuality = "2160p";
        Plan? plan = null;
        if (features.PlanEnforcementEnabled)
        {
            plan = await GetEffectivePlanForUserAsync(channel.OwnerUserId, ct);
            maxUpload = plan?.MaxUploadSize ?? 2L * 1024 * 1024 * 1024;
            maxDuration = plan?.MaxVideoDuration ?? 12 * 60 * 60;
            maxQuality = plan?.MaxVideoQuality ?? "720p";
        }
        try { VideoRules.ValidateUpload(request.ContentType, request.FileSize, maxUpload); }
        catch (VideoValidationException ex) { throw Error(400, ex.Code, ex.Message); }
        if (request.Duration <= 0 || request.Duration > maxDuration) throw Error(400, "VIDEO_TOO_LONG", "Video vượt quá thời lượng gói cho phép.");
        var sourceHeight = VideoRules.QualityHeight(request.SourceQuality);
        if (sourceHeight == 0) throw Error(400, "INVALID_VIDEO_QUALITY", "Chất lượng video không hợp lệ.");
        if (sourceHeight > VideoRules.QualityHeight(maxQuality)) throw Error(403, "UPLOAD_QUALITY_DENIED", "Chất lượng video vượt quá giới hạn gói.");
        var quota = await db.ChannelQuotas.AsNoTracking().SingleOrDefaultAsync(x => x.ChannelId == request.ChannelId, ct);
        var limit = quota?.StorageLimit ?? (features.PlanEnforcementEnabled
            ? plan?.StorageLimit ?? ChannelQuotaRules.DefaultStorageLimit
            : maxUpload);
        var used = quota?.StorageUsed ?? 0;
        if (!ChannelQuotaRules.CanReserve(used, request.FileSize, limit)) throw Error(409, "CHANNEL_QUOTA_EXCEEDED", "Kênh không còn đủ dung lượng lưu trữ.");
        return new(true, maxUpload, maxDuration, maxQuality, limit, used, ChannelQuotaRules.Remaining(limit, used));
    }

    public async Task<PageResult<VideoResponse>> GetManagedVideosAsync(Guid actorId, Guid channelId, string? status, string? visibility, string? search, Guid? categoryId, string? tag, int page, int pageSize, CancellationToken ct = default)
    {
        await RequireChannelPermissionAsync(channelId, actorId, ChannelPermissions.VideoView, ct);
        (page, pageSize) = Page(page, pageSize);
        var query = db.Videos.AsNoTracking().Where(x => x.ChannelId == channelId && x.Status != "deleted");
        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(x => x.Status == status);
        if (!string.IsNullOrWhiteSpace(visibility)) query = query.Where(x => x.Visibility == visibility);
        if (!string.IsNullOrWhiteSpace(search)) { var term = search.Trim(); query = query.Where(x => EF.Functions.ILike(x.Title, $"%{term}%")); }
        if (categoryId.HasValue) query = query.Where(x => x.CategoryId == categoryId);
        if (!string.IsNullOrWhiteSpace(tag))
        {
            var normalizedTag = tag.Trim().TrimStart('#');
            query = query.Where(x => db.VideoTags.Any(vt => vt.VideoId == x.VideoId && db.Tags.Any(t => t.TagId == vt.TagId && EF.Functions.ILike(t.Name, normalizedTag))));
        }
        var total = await query.CountAsync(ct);
        var videos = await query.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        var items = await ToResponsesAsync(videos, actorId, ct);
        return new(items, page, pageSize, total);
    }

    public async Task<VideoResponse> UpdateVideoAsync(Guid actorId, Guid videoId, UpdateVideoRequest request, CancellationToken ct = default)
    {
        var video = await RequireVideoAsync(videoId, ct);
        await RequireChannelPermissionAsync(video.ChannelId, actorId, ChannelPermissions.VideoEdit, ct);
        if (request.Title != null)
        {
            var title = request.Title.Trim();
            if (title.Length is < 1 or > 100) throw Error(400, "INVALID_TITLE", "Tiêu đề cần từ 1 đến 100 ký tự.");
            video.Title = title;
        }
        if (request.Description != null) video.Description = Clean(request.Description);
        if (request.Visibility != null)
        {
            var oldVisibility = video.Visibility;
            var newVisibility = request.Visibility.ToLowerInvariant();
            VideoRules.ValidateVisibility(newVisibility);
            EnsureVisibilityAvailable(newVisibility);
            video.Visibility = newVisibility;

            if (features.ModerationEnabled && newVisibility == "public" && oldVisibility != "public")
            {
                if (video.ModerationStatus != "approved")
                {
                    video.ModerationStatus = "pending";
                    var riskLevel = ModerationRiskLevel(video.Title, video.Description);

                    var hasPendingCase = await db.ModerationCases.AnyAsync(c => c.VideoId == video.VideoId && (c.Status == "pending" || c.Status == "reviewing"), ct);
                    if (!hasPendingCase)
                    {
                        db.ModerationCases.Add(new ModerationCase
                        {
                            VideoId = video.VideoId,
                            Status = "pending",
                            CaseType = "upload_review",
                            RiskLevel = riskLevel,
                            SubmittedAt = Now,
                            UpdatedAt = Now
                        });
                    }
                }
            }
        }
        if (request.ClearCategory) video.CategoryId = null;
        else if (request.CategoryId.HasValue)
        {
            if (!await db.Categories.AnyAsync(x => x.CategoryId == request.CategoryId && x.Status == "active", ct)) throw Error(400, "INVALID_CATEGORY", "Danh mục không hợp lệ.");
            video.CategoryId = request.CategoryId;
        }
        if (request.LanguageCode != null) video.LanguageCode = Clean(request.LanguageCode);
        if (request.AgeRestricted.HasValue) video.AgeRestricted = request.AgeRestricted.Value;
        if (request.ThumbnailUrl != null) video.ThumbnailUrl = Clean(request.ThumbnailUrl);
        if (request.Chapters != null)
        {
            try { video.Metadata = PersistenceJson.Serialize(new { chapters = VideoRules.ValidateChapters(request.Chapters.Select(x => new VideoChapter(x.StartSeconds, x.Title)), video.Duration) }); }
            catch (VideoValidationException ex) { throw Error(400, ex.Code, ex.Message); }
        }
        if (request.Tags != null) await ReplaceTagsAsync(video.VideoId, NormalizeTags(request.Tags), ct);
        video.UpdatedAt = Now;
        await db.SaveChangesAsync(ct);
        return await ToResponseAsync(video, actorId, ct);
    }

    public async Task<VideoResponse> UpdateThumbnailAsync(Guid actorId, Guid videoId, UpdateThumbnailRequest request, CancellationToken ct = default)
    {
        var video = await RequireVideoAsync(videoId, ct);
        await RequireChannelPermissionAsync(video.ChannelId, actorId, ChannelPermissions.VideoEdit, ct);

        string? newThumbnailPath = null;
        var temporaryDirectory = Path.Combine(Path.GetTempPath(), "hutube-thumbnail-processing", Guid.NewGuid().ToString("N"));
        var persisted = false;
        try
        {
            if (request.Content != null && !string.IsNullOrWhiteSpace(request.FileName) && !string.IsNullOrWhiteSpace(request.ContentType))
            {
                newThumbnailPath = await storage.SaveFileAsync("video-thumbnails", request.FileName, request.Content, request.ContentType, ct);
            }
            else if (request.Generate)
            {
                if (string.IsNullOrWhiteSpace(video.VideoUrl))
                    throw Error(409, "VIDEO_SOURCE_NOT_FOUND", "Không tìm thấy file source của video để tạo thumbnail.");

                Directory.CreateDirectory(temporaryDirectory);
                var sourceFile = Path.Combine(temporaryDirectory, "source.mp4");
                var sourceUrl = await storage.GetReadUrlAsync(video.VideoUrl, TimeSpan.FromMinutes(15), ct);
                using var response = await httpClientFactory.CreateClient().GetAsync(sourceUrl, HttpCompletionOption.ResponseHeadersRead, ct);
                if (!response.IsSuccessStatusCode)
                    throw Error(502, "VIDEO_SOURCE_UNAVAILABLE", "Không thể đọc source video để tạo thumbnail.");
                await using (var source = File.Create(sourceFile))
                    await response.Content.CopyToAsync(source, ct);

                var generated = await transcoder.CreateThumbnailAsync(sourceFile, temporaryDirectory, ct);
                if (string.IsNullOrWhiteSpace(generated) || !File.Exists(generated))
                    throw Error(422, "THUMBNAIL_GENERATION_FAILED", "FFmpeg không thể tạo thumbnail từ video này.");

                await using var thumbnail = File.OpenRead(generated);
                newThumbnailPath = await storage.SaveFileAsync(
                    "video-thumbnails", $"{Guid.NewGuid():N}.jpg", thumbnail, "image/jpeg", ct);
            }
            else
            {
                throw Error(400, "THUMBNAIL_REQUIRED", "Vui lòng chọn thumbnail hoặc bật tự động tạo thumbnail.");
            }

            var previousThumbnailPath = video.ThumbnailUrl;
            video.ThumbnailUrl = newThumbnailPath;
            video.UpdatedAt = Now;
            await db.SaveChangesAsync(ct);
            persisted = true;

            if (!string.IsNullOrWhiteSpace(previousThumbnailPath) && !string.Equals(previousThumbnailPath, newThumbnailPath, StringComparison.Ordinal))
            {
                try { await storage.DeleteFileAsync(previousThumbnailPath, CancellationToken.None); }
                catch (Exception ex) { logger.LogWarning(ex, "Không thể xóa thumbnail cũ của video {VideoId}", videoId); }
            }

            return await ToResponseAsync(video, actorId, ct);
        }
        catch
        {
            if (!persisted && !string.IsNullOrWhiteSpace(newThumbnailPath))
            {
                try { await storage.DeleteFileAsync(newThumbnailPath, CancellationToken.None); }
                catch (Exception ex) { logger.LogWarning(ex, "Không thể dọn thumbnail tạm của video {VideoId}", videoId); }
            }
            throw;
        }
        finally
        {
            try
            {
                if (Directory.Exists(temporaryDirectory)) Directory.Delete(temporaryDirectory, true);
            }
            catch (IOException ex) { logger.LogWarning(ex, "Không thể xóa thư mục thumbnail tạm {Directory}", temporaryDirectory); }
        }
    }

    public async Task DeleteVideoAsync(Guid actorId, Guid videoId, CancellationToken ct = default)
    {
        var video = await RequireVideoAsync(videoId, ct);
        await RequireChannelPermissionAsync(video.ChannelId, actorId, ChannelPermissions.VideoDelete, ct);
        video.Status = "deleted"; video.UpdatedAt = Now;
        await db.SaveChangesAsync(ct);
    }

    public async Task<VideoResponse> SubmitModerationAsync(Guid actorId, Guid videoId, CancellationToken ct = default)
    {
        if (!features.ModerationEnabled) throw Error(409, "MODERATION_UNAVAILABLE", "Kiểm duyệt đang tạm khóa; video chưa thể đặt ở chế độ công khai.");
        var video = await RequireVideoAsync(videoId, ct);
        await RequireChannelPermissionAsync(video.ChannelId, actorId, ChannelPermissions.VideoEdit, ct);
        if (video.ModerationStatus == "approved") throw Error(409, "INVALID_MODERATION_STATE", "Video đã được duyệt.");
        if (video.ModerationStatus == "pending"
            && await db.ModerationCases.AnyAsync(c => c.VideoId == video.VideoId && (c.Status == "pending" || c.Status == "reviewing"), ct))
            return await ToResponseAsync(video, actorId, ct);

        video.ModerationStatus = "pending";
        var now = Now;
        video.UpdatedAt = now;
        db.ModerationCases.Add(CreateUploadModerationCase(video, now));
        await db.SaveChangesAsync(ct);
        return await ToResponseAsync(video, actorId, ct);
    }

    public async Task<VideoResponse> PublishAsync(Guid actorId, Guid videoId, CancellationToken ct = default)
    {
        var video = await RequireVideoAsync(videoId, ct);
        await RequireChannelPermissionAsync(video.ChannelId, actorId, ChannelPermissions.VideoEdit, ct);
        if (!features.ModerationEnabled && video.Visibility == "public")
            throw Error(409, "PUBLICATION_LOCKED", "Chế độ công khai đang tạm khóa cho đến khi kiểm duyệt được bật.");
        if (features.ModerationEnabled && video.ModerationStatus != "approved") throw Error(409, "VIDEO_NOT_APPROVED", "Video phải được kiểm duyệt trước khi xuất bản.");
        var wasPublished = video.Status == "published" && video.PublishedAt.HasValue;
        video.Status = "published"; video.PublishedAt ??= Now; video.UpdatedAt = Now;
        await db.SaveChangesAsync(ct);
        if (!wasPublished)
        {
            await notifications.PublishAsync(actorId, "video_published", "Video đã được xuất bản", video.Title, $"/watch/{video.VideoId}", "video", video.VideoId, ct);

            if (video.Visibility == "public")
            {
                var channelName = await db.Channels.AsNoTracking()
                    .Where(channel => channel.ChannelId == video.ChannelId)
                    .Select(channel => channel.Name)
                    .SingleOrDefaultAsync(ct) ?? "Kênh bạn đăng ký";
                var subscriberIds = await db.Subscriptions.AsNoTracking()
                    .Where(subscription => subscription.ChannelId == video.ChannelId
                        && subscription.Status == "active"
                        && subscription.NotificationsEnabled)
                    .Select(subscription => subscription.UserId)
                    .ToListAsync(ct);

                foreach (var subscriberId in subscriberIds)
                {
                    try
                    {
                        await notifications.PublishInAppAsync(
                            subscriberId,
                            "new_video",
                            $"{channelName} vừa đăng video mới",
                            video.Title,
                            $"/watch/{video.VideoId}",
                            "video",
                            video.VideoId,
                            ct);
                    }
                    catch (Exception ex) when (ex is not OperationCanceledException)
                    {
                        logger.LogWarning(ex, "Không thể gửi thông báo video mới tới {UserId} cho video {VideoId}", subscriberId, video.VideoId);
                    }
                }
            }
        }
        return await ToResponseAsync(video, actorId, ct);
    }

    public async Task CancelUploadAsync(Guid actorId, Guid videoId, CancellationToken ct = default)
    {
        var video = await RequireVideoAsync(videoId, ct);
        await RequireChannelPermissionAsync(video.ChannelId, actorId, ChannelPermissions.VideoDelete, ct);
        if (video.Status == "published") throw Error(409, "PUBLISHED_VIDEO_CANNOT_CANCEL", "Video đã xuất bản không thể hủy upload.");
        await storage.DeleteFileAsync(video.VideoUrl, ct);
        video.Status = "deleted"; video.UpdatedAt = Now;
        var quota = await db.ChannelQuotas.SingleOrDefaultAsync(x => x.ChannelId == video.ChannelId, ct);
        if (quota != null) { quota.StorageUsed = Math.Max(0, quota.StorageUsed - video.FileSize); quota.UpdatedAt = Now; }
        await db.SaveChangesAsync(ct);
    }

    public async Task<VideoResponse> RetryProcessingAsync(Guid actorId, Guid videoId, CancellationToken ct = default)
    {
        var video = await RequireVideoAsync(videoId, ct);
        await RequireChannelPermissionAsync(video.ChannelId, actorId, ChannelPermissions.VideoEdit, ct);
        if (video.Status != "failed") throw Error(409, "VIDEO_NOT_RETRYABLE", "Chỉ video xử lý lỗi mới có thể thử lại.");
        if (video.MediaPurgedAt.HasValue) throw Error(409, "VIDEO_MEDIA_PURGED", "Tệp video đã được dọn và không thể xử lý lại.");
        var sourceRendition = await db.VideoRenditions
            .Where(x => x.VideoId == videoId && x.Codec == "source")
            .OrderByDescending(x => x.Height)
            .FirstOrDefaultAsync(ct)
            ?? throw Error(409, "VIDEO_SOURCE_RENDITION_NOT_FOUND", "Không tìm thấy source để encode lại video.");
        // The source file is the input for every retry and must not be retried
        // as a derived rendition. Older failures could have marked all rows as
        // failed, so restore the source row to ready when its file still exists.
        var sourceQuality = sourceRendition.QualityLabel;
        sourceRendition.Status = "ready";
        sourceRendition.UpdatedAt = Now;
        video.Status = "processing"; video.ModerationStatus = "not_submitted"; video.UpdatedAt = Now;
        var renditions = await db.VideoRenditions
            .Where(x => x.VideoId == videoId && x.Status == "failed" && x.Codec != "source")
            .ToListAsync(ct);
        foreach (var rendition in renditions) { rendition.Status = "processing"; rendition.UpdatedAt = Now; }
        await db.SaveChangesAsync(ct);
        renditionQueue.Enqueue(new DeferredVideoRenditionJob(videoId, sourceQuality));
        return await ToResponseAsync(video, actorId, ct);
    }

    public async Task<WatchProgressResponse> SaveProgressAsync(Guid userId, Guid videoId, WatchProgressRequest request, CancellationToken ct = default)
    {
        var video = await RequireVideoAsync(videoId, ct); await EnsureCanViewAsync(video, userId, ct);
        decimal progress;
        try { progress = VideoRules.CalculateProgress(request.WatchedSeconds, video.Duration); }
        catch (VideoValidationException ex) { throw Error(400, ex.Code, ex.Message); }
        if (!request.SaveHistory) return new(Math.Clamp(request.WatchedSeconds, 0, video.Duration), progress, Now);
        var item = await db.ViewingHistories.Where(x => x.UserId == userId && x.VideoId == videoId).OrderByDescending(x => x.ViewedAt).FirstOrDefaultAsync(ct);
        if (item == null || request.NewSession || (Now - item.ViewedAt) > ViewSessionCooldown)
        {
            item = new ViewingHistory { UserId = userId, VideoId = videoId };
            db.ViewingHistories.Add(item);
        }
        item.WatchDuration = Math.Clamp(request.WatchedSeconds, 0, video.Duration); item.Progress = progress; item.ViewedAt = Now;
        await db.SaveChangesAsync(ct);
        return new(item.WatchDuration, item.Progress, item.ViewedAt);
    }

    public async Task<ReactionResponse> SetVideoReactionAsync(Guid userId, Guid videoId, string? reaction, CancellationToken ct = default)
    {
        var video = await RequireVideoAsync(videoId, ct); await EnsureCanViewAsync(video, userId, ct);
        var item = await db.VideoReactions.SingleOrDefaultAsync(x => x.UserId == userId && x.VideoId == videoId, ct);
        var previousReaction = item?.Type;
        var normalizedReaction = reaction?.ToLowerInvariant();
        if (reaction == null) { if (item != null) db.VideoReactions.Remove(item); }
        else
        {
            try { VideoRules.ValidateReaction(reaction); } catch (VideoValidationException ex) { throw Error(400, ex.Code, ex.Message); }
            if (item == null) { item = new VideoReaction { UserId = userId, VideoId = videoId, CreatedAt = Now }; db.VideoReactions.Add(item); }
            item.Type = normalizedReaction!; item.UpdatedAt = Now;
        }
        await db.SaveChangesAsync(ct);
        if (normalizedReaction == "like" && previousReaction != "like")
        {
            var ownerId = await db.Channels.AsNoTracking().Where(x => x.ChannelId == video.ChannelId).Select(x => x.OwnerUserId).SingleAsync(ct);
            await PublishInteractionNotificationAsync(ownerId, userId, "video_like", "Video của bạn vừa được thích",
                video.Title, $"/watch/{videoId}", "video", videoId, ct);
        }
        else if (normalizedReaction == "dislike" && previousReaction != "dislike")
        {
            var ownerId = await db.Channels.AsNoTracking().Where(x => x.ChannelId == video.ChannelId).Select(x => x.OwnerUserId).SingleAsync(ct);
            await PublishInteractionNotificationAsync(ownerId, userId, "video_dislike", "Video của bạn có lượt không thích mới",
                video.Title, $"/watch/{videoId}", "video", videoId, ct);
        }
        var reactionCounts = await db.VideoReactions.AsNoTracking().Where(x => x.VideoId == videoId)
            .GroupBy(x => x.Type).Select(group => new { group.Key, Count = group.LongCount() })
            .ToDictionaryAsync(row => row.Key, row => row.Count, ct);
        return new(normalizedReaction, reactionCounts.GetValueOrDefault("like"), reactionCounts.GetValueOrDefault("dislike"));
    }

    public async Task<RatingResponse> SetRatingAsync(Guid userId, Guid videoId, int? score, CancellationToken ct = default)
    {
        var video = await RequireVideoAsync(videoId, ct); await EnsureCanViewAsync(video, userId, ct);
        var item = await db.VideoRatings.SingleOrDefaultAsync(x => x.UserId == userId && x.VideoId == videoId, ct);
        if (!score.HasValue) { if (item != null) db.VideoRatings.Remove(item); }
        else
        {
            try { VideoRules.ValidateRating(score.Value); } catch (VideoValidationException ex) { throw Error(400, ex.Code, ex.Message); }
            if (item == null) { item = new VideoRating { UserId = userId, VideoId = videoId, EvaluatedAt = Now }; db.VideoRatings.Add(item); }
            item.Score = (short)score.Value; item.UpdatedAt = Now;
        }
        await db.SaveChangesAsync(ct);
        var aggregate = await db.VideoRatings.AsNoTracking().Where(x => x.VideoId == videoId)
            .GroupBy(_ => 1)
            .Select(group => new { Count = group.Count(), Average = group.Average(row => (double)row.Score) })
            .SingleOrDefaultAsync(ct);
        return new(score, aggregate == null ? null : Math.Round((decimal)aggregate.Average, 2), aggregate?.Count ?? 0);
    }

    public async Task<ShareResponse> ShareAsync(Guid userId, Guid videoId, string? method, CancellationToken ct = default)
    {
        var video = await RequireVideoAsync(videoId, ct); await EnsureCanViewAsync(video, userId, ct);
        db.ShareHistories.Add(new ShareHistory { UserId = userId, VideoId = videoId, ShareMethod = Clean(method) ?? "copy_link", SharedAt = Now });
        await db.SaveChangesAsync(ct);
        return new($"/watch/{videoId}", await db.ShareHistories.LongCountAsync(x => x.VideoId == videoId, ct));
    }

    public async Task<PageResult<CommentResponse>> GetCommentsAsync(Guid videoId, Guid? viewerId, string sort, int page, int pageSize, CancellationToken ct = default)
    {
        var video = await RequireVideoAsync(videoId, ct); await EnsureCanViewAsync(video, viewerId, ct); (page, pageSize) = Page(page, pageSize);
        var query = db.Comments.AsNoTracking().Where(x => x.VideoId == videoId && x.ParentCommentId == null && x.Status == "visible");
        var total = await query.CountAsync(ct);
        List<Comment> comments;
        if (sort.Equals("top", StringComparison.OrdinalIgnoreCase))
        {
            var likeCounts = db.CommentReactions.AsNoTracking().Where(reaction => reaction.Type == "like")
                .GroupBy(reaction => reaction.CommentId)
                .Select(group => new { CommentId = group.Key, Count = group.LongCount() });
            comments = await (from comment in query
                              join likes in likeCounts on comment.CommentId equals likes.CommentId into likeRows
                              from likes in likeRows.DefaultIfEmpty()
                              let likeCount = (long?)likes.Count
                              orderby (likeCount ?? 0L) descending, comment.CreatedAt descending
                              select comment)
                .Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        }
        else
        {
            comments = await query.OrderByDescending(x => x.CreatedAt)
                .Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        }
        var items = await ToCommentsAsync(comments, viewerId, ct);
        return new(items, page, pageSize, total);
    }

    public async Task<PageResult<CommentResponse>> GetRepliesAsync(Guid commentId, Guid? viewerId, int page, int pageSize, CancellationToken ct = default)
    {
        var parent = await RequireCommentAsync(commentId, ct); var video = await RequireVideoAsync(parent.VideoId, ct);
        await EnsureCanViewAsync(video, viewerId, ct); (page, pageSize) = Page(page, pageSize);
        var query = db.Comments.AsNoTracking().Where(x => x.ParentCommentId == commentId && x.Status == "visible");
        var total = await query.CountAsync(ct); var replies = await query.OrderBy(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        var items = await ToCommentsAsync(replies, viewerId, ct);
        return new(items, page, pageSize, total);
    }

    public async Task<PageResult<CommentResponse>> GetManagedCommentsAsync(Guid actorId, Guid channelId, string? status, int page, int pageSize, CancellationToken ct = default)
    {
        await RequireChannelPermissionAsync(channelId, actorId, ChannelPermissions.CommentManage, ct);
        (page, pageSize) = Page(page, pageSize);
        var query = db.Comments.AsNoTracking().Where(x => db.Videos.Any(v => v.VideoId == x.VideoId && v.ChannelId == channelId) && x.Status != "deleted");
        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(x => x.Status == status.ToLowerInvariant());
        var total = await query.CountAsync(ct);
        var rows = await query.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        var items = await ToCommentsAsync(rows, actorId, ct);
        return new(items, page, pageSize, total);
    }

    public async Task<IReadOnlyList<ViolationTypeResponse>> GetViolationTypesAsync(CancellationToken ct = default)
    {
        var list = await db.ViolationTypes.AsNoTracking().Where(x => x.Status == "active").OrderBy(x => x.Name)
            .Select(x => new ViolationTypeResponse(x.ViolationTypeId, x.Code, x.Name, x.Description)).ToListAsync(ct);
        if (list.Count > 0) return list;

        var defaults = new List<ViolationType>
        {
            new() { ViolationTypeId = Guid.Parse("00000000-0000-0002-0000-000000000001"), Code = "sexual", Name = "Nội dung khiêu dâm", Description = "Hình ảnh, video hoặc nội dung khiêu dâm, không phù hợp thuần phong mỹ tục.", Status = "active", CreatedAt = Now, UpdatedAt = Now },
            new() { ViolationTypeId = Guid.Parse("00000000-0000-0002-0000-000000000002"), Code = "violent", Name = "Nội dung bạo lực hoặc phản cảm", Description = "Bạo lực, đẫm máu, gây sốc hoặc phản cảm.", Status = "active", CreatedAt = Now, UpdatedAt = Now },
            new() { ViolationTypeId = Guid.Parse("00000000-0000-0002-0000-000000000003"), Code = "hate", Name = "Nội dung lăng mạ hoặc kích động thù hận", Description = "Xúc phạm danh dự, kỳ thị hoặc kích động thù địch.", Status = "active", CreatedAt = Now, UpdatedAt = Now },
            new() { ViolationTypeId = Guid.Parse("00000000-0000-0002-0000-000000000004"), Code = "harassment", Name = "Nội dung quấy rối hoặc bắt nạt", Description = "Đe dọa, quấy rối, bắt nạt trực tuyến.", Status = "active", CreatedAt = Now, UpdatedAt = Now },
            new() { ViolationTypeId = Guid.Parse("00000000-0000-0002-0000-000000000005"), Code = "harmful", Name = "Hành động gây hại hoặc nguy hiểm", Description = "Hành vi khuyến khích nguy hiểm hoặc tự gây hại.", Status = "active", CreatedAt = Now, UpdatedAt = Now },
            new() { ViolationTypeId = Guid.Parse("00000000-0000-0002-0000-000000000006"), Code = "spam", Name = "Spam hoặc thông tin sai lệch", Description = "Lừa đảo, tin giả, quảng cáo rác hoặc thao túng người xem.", Status = "active", CreatedAt = Now, UpdatedAt = Now },
            new() { ViolationTypeId = Guid.Parse("00000000-0000-0002-0000-000000000007"), Code = "copyright", Name = "Vi phạm bản quyền", Description = "Sử dụng tác phẩm không có bản quyền hoặc quyền sở hữu hợp pháp.", Status = "active", CreatedAt = Now, UpdatedAt = Now },
            new() { ViolationTypeId = Guid.Parse("00000000-0000-0002-0000-000000000008"), Code = "other", Name = "Vi phạm khác", Description = "Các hành vi vi phạm điều khoản dịch vụ hoặc tiêu chuẩn cộng đồng khác.", Status = "active", CreatedAt = Now, UpdatedAt = Now }
        };
        try
        {
            db.ViolationTypes.AddRange(defaults);
            await db.SaveChangesAsync(ct);
        }
        catch { /* ignore duplicate key if race condition */ }
        return defaults.Select(x => new ViolationTypeResponse(x.ViolationTypeId, x.Code, x.Name, x.Description)).ToList();
    }

    public async Task<CommentResponse> CreateCommentAsync(Guid userId, Guid videoId, CreateCommentRequest request, CancellationToken ct = default)
    {
        var video = await RequireVideoAsync(videoId, ct); await EnsureCanViewAsync(video, userId, ct);
        string content; try { content = VideoRules.ValidateComment(request.Content); } catch (VideoValidationException ex) { throw Error(400, ex.Code, ex.Message); }
        Comment? parent = null;
        if (request.ParentCommentId.HasValue)
        {
            parent = await db.Comments.SingleOrDefaultAsync(x => x.CommentId == request.ParentCommentId && x.VideoId == videoId && x.Status != "deleted", ct)
                ?? throw Error(404, "PARENT_COMMENT_NOT_FOUND", "Không tìm thấy bình luận cha.");
            if (parent.ParentCommentId.HasValue) throw Error(400, "REPLY_DEPTH_EXCEEDED", "Chỉ hỗ trợ một cấp trả lời.");
        }
        var comment = new Comment { UserId = userId, VideoId = videoId, ParentCommentId = parent?.CommentId, Content = content, Status = "visible", CreatedAt = Now, UpdatedAt = Now };
        if (await db.Comments.AnyAsync(x => x.UserId == userId && x.VideoId == videoId && x.Content == content && x.CreatedAt > Now.AddSeconds(-10), ct))
            throw Error(429, "COMMENT_SPAM_DETECTED", "Bạn đang gửi cùng một bình luận quá nhanh.");
        db.Comments.Add(comment); await db.SaveChangesAsync(ct);
        if (parent != null && parent.UserId != userId)
        {
            await PublishInteractionNotificationAsync(parent.UserId, userId, "comment_reply", "Có người trả lời bình luận", content,
                $"/watch/{videoId}?comment={comment.CommentId}", "comment", parent.CommentId, ct);
        }
        var ownerId = await db.Channels.AsNoTracking().Where(x => x.ChannelId == video.ChannelId).Select(x => x.OwnerUserId).SingleOrDefaultAsync(ct);
        if (ownerId != Guid.Empty && ownerId != userId && (parent == null || parent.UserId != ownerId))
        {
            var commentTitle = parent == null
                ? "Bình luận mới về video của bạn"
                : "Phản hồi mới trong video của bạn";
            await PublishInteractionNotificationAsync(ownerId, userId, "video_comment", commentTitle,
                $"\"{content}\" trên video '{video.Title}'", $"/watch/{videoId}?comment={comment.CommentId}", "video", videoId, ct);
        }
        return await ToCommentAsync(comment, userId, ct);
    }

    public async Task<CommentResponse> UpdateCommentAsync(Guid userId, Guid commentId, UpdateCommentRequest request, CancellationToken ct = default)
    {
        var comment = await RequireCommentAsync(commentId, ct);
        if (comment.UserId != userId) throw Error(403, "COMMENT_EDIT_DENIED", "Bạn chỉ có thể sửa bình luận của mình.");
        try { comment.Content = VideoRules.ValidateComment(request.Content); } catch (VideoValidationException ex) { throw Error(400, ex.Code, ex.Message); }
        comment.UpdatedAt = Now; await db.SaveChangesAsync(ct); return await ToCommentAsync(comment, userId, ct);
    }

    public async Task DeleteCommentAsync(Guid userId, Guid commentId, CancellationToken ct = default)
    {
        var comment = await RequireCommentAsync(commentId, ct);
        var video = await RequireVideoAsync(comment.VideoId, ct);
        if (comment.UserId != userId && !await HasChannelPermissionAsync(video.ChannelId, userId, ChannelPermissions.CommentManage, ct))
            throw Error(403, "COMMENT_DELETE_DENIED", "Bạn không có quyền xóa bình luận này.");
        comment.Status = "deleted"; comment.Content = "[đã xóa]"; comment.UpdatedAt = Now; await db.SaveChangesAsync(ct);
    }

    public async Task<ReactionResponse> SetCommentReactionAsync(Guid userId, Guid commentId, string? reaction, CancellationToken ct = default)
    {
        var comment = await RequireCommentAsync(commentId, ct);
        var video = await RequireVideoAsync(comment.VideoId, ct); await EnsureCanViewAsync(video, userId, ct);
        var item = await db.CommentReactions.SingleOrDefaultAsync(x => x.UserId == userId && x.CommentId == commentId, ct);
        var previousReaction = item?.Type;
        var normalizedReaction = reaction?.ToLowerInvariant();
        if (reaction == null) { if (item != null) db.CommentReactions.Remove(item); }
        else
        {
            try { VideoRules.ValidateReaction(reaction); } catch (VideoValidationException ex) { throw Error(400, ex.Code, ex.Message); }
            if (item == null) { item = new CommentReaction { UserId = userId, CommentId = commentId, CreatedAt = Now }; db.CommentReactions.Add(item); }
            item.Type = normalizedReaction!; item.UpdatedAt = Now;
        }
        await db.SaveChangesAsync(ct);
        if (normalizedReaction == "like" && previousReaction != "like")
        {
            await PublishInteractionNotificationAsync(comment.UserId, userId, "comment_like", "Bình luận của bạn vừa được thích",
                video.Title, $"/watch/{video.VideoId}?comment={comment.CommentId}", "comment", comment.CommentId, ct);
        }
        return new(normalizedReaction, await db.CommentReactions.LongCountAsync(x => x.CommentId == commentId && x.Type == "like", ct), await db.CommentReactions.LongCountAsync(x => x.CommentId == commentId && x.Type == "dislike", ct));
    }

    public async Task<ReportResponse> ReportCommentAsync(Guid userId, Guid commentId, ReportCommentRequest request, CancellationToken ct = default)
    {
        await RequireCommentAsync(commentId, ct);
        var violationTypeId = request.ViolationTypeId;
        if (!await db.ViolationTypes.AnyAsync(x => x.ViolationTypeId == violationTypeId && x.Status == "active", ct))
        {
            var fallback = await db.ViolationTypes.FirstOrDefaultAsync(x => x.Status == "active", ct);
            if (fallback != null) violationTypeId = fallback.ViolationTypeId;
            else
            {
                var defaults = await GetViolationTypesAsync(ct);
                violationTypeId = defaults[0].ViolationTypeId;
            }
        }
        var description = Clean(request.Description); if (description == null) throw Error(400, "DESCRIPTION_REQUIRED", "Vui lòng mô tả vi phạm.");
        var report = new Report { UserId = userId, CommentId = commentId, ViolationTypeId = violationTypeId, Description = description, CreatedAt = Now, UpdatedAt = Now };
        db.Reports.Add(report); await db.SaveChangesAsync(ct);
        db.ModerationCases.Add(new ModerationCase { ReportId = report.ReportId, CaseType = "report_review", Status = "pending", SubmittedAt = Now, UpdatedAt = Now });
        await db.SaveChangesAsync(ct); return new(report.ReportId, report.Status, report.CreatedAt);
    }

    public async Task<CommentResponse> SetCommentHiddenAsync(Guid actorId, Guid commentId, bool hidden, string? reason, CancellationToken ct = default)
    {
        var comment = await RequireCommentAsync(commentId, ct); var video = await RequireVideoAsync(comment.VideoId, ct);
        await RequireChannelPermissionAsync(video.ChannelId, actorId, ChannelPermissions.CommentManage, ct);
        comment.Status = hidden ? "hidden" : "visible"; comment.UpdatedAt = Now;
        db.CommentModerationActions.Add(new CommentModerationAction { CommentId = commentId, ModeratorUserId = actorId, ActionType = hidden ? "hide" : "unhide", Reason = Clean(reason), CreatedAt = Now });
        await db.SaveChangesAsync(ct); return await ToCommentAsync(comment, actorId, ct);
    }

    public async Task<IReadOnlyList<RenditionResponse>> GetDownloadOptionsAsync(Guid userId, Guid videoId, CancellationToken ct = default)
    {
        var video = await RequireVideoAsync(videoId, ct); await EnsureCanViewAsync(video, userId, ct);
        await EnsureDownloadAllowedAsync(userId, ct);
        var maxHeight = await MaxDownloadHeightAsync(userId, ct);
        var rows = await db.VideoRenditions.AsNoTracking().Where(x => x.VideoId == videoId && x.Status == "ready" && x.Height <= maxHeight).OrderBy(x => x.Height).ToListAsync(ct);
        var result = new List<RenditionResponse>();
        foreach (var row in rows) result.Add(new(row.QualityLabel, row.Width, row.Height, row.FileSize, await ReadUrlAsync(row.FileUrl, ct)));
        return result;
    }

    public async Task<DownloadResponse> CreateDownloadAsync(Guid userId, Guid videoId, string quality, CancellationToken ct = default)
    {
        var video = await RequireVideoAsync(videoId, ct); await EnsureCanViewAsync(video, userId, ct);
        await EnsureDownloadAllowedAsync(userId, ct);
        if (string.IsNullOrWhiteSpace(quality)) throw Error(400, "INVALID_DOWNLOAD_QUALITY", "Vui lòng chọn chất lượng tải xuống.");
        var normalizedQuality = quality.Trim().ToLowerInvariant();
        var maxHeight = await MaxDownloadHeightAsync(userId, ct);
        var selected = await db.VideoRenditions.AsNoTracking().SingleOrDefaultAsync(x => x.VideoId == videoId && x.Status == "ready"
            && x.QualityLabel == normalizedQuality && x.Height <= maxHeight, ct)
            ?? throw Error(403, "DOWNLOAD_QUALITY_DENIED", "Gói hiện tại không hỗ trợ chất lượng tải xuống này.");
        var item = await db.VideoDownloads.SingleOrDefaultAsync(x => x.UserId == userId && x.VideoId == videoId && x.QualityLabel == selected.QualityLabel, ct);
        if (item == null)
        {
            item = new VideoDownload { UserId = userId, VideoId = videoId, QualityLabel = selected.QualityLabel, FileUrl = selected.FileUrl, FileSize = selected.FileSize, Status = "ready", CreatedAt = Now, UpdatedAt = Now };
            db.VideoDownloads.Add(item); await db.SaveChangesAsync(ct);
        }
        return new(item.VideoDownloadId, videoId, video.Title, item.QualityLabel, await ReadUrlAsync(item.FileUrl, ct), item.FileSize, item.Status, item.CreatedAt);
    }

    public async Task<IReadOnlyList<DownloadResponse>> GetDownloadsAsync(Guid userId, CancellationToken ct = default)
    {
        var rows = await (from item in db.VideoDownloads.AsNoTracking() join video in db.Videos.AsNoTracking() on item.VideoId equals video.VideoId
                          where item.UserId == userId orderby item.CreatedAt descending select new { item, video.Title })
            .Take(200).ToListAsync(ct);
        var result = new List<DownloadResponse>();
        foreach (var row in rows) result.Add(new(row.item.VideoDownloadId, row.item.VideoId, row.Title, row.item.QualityLabel,
            await ReadUrlAsync(row.item.FileUrl, ct), row.item.FileSize, row.item.Status, row.item.CreatedAt));
        return result;
    }

    public async Task DeleteDownloadAsync(Guid userId, Guid downloadId, CancellationToken ct = default)
    {
        var item = await db.VideoDownloads.SingleOrDefaultAsync(x => x.VideoDownloadId == downloadId && x.UserId == userId, ct)
            ?? throw Error(404, "DOWNLOAD_NOT_FOUND", "Không tìm thấy bản tải xuống.");
        db.VideoDownloads.Remove(item); await db.SaveChangesAsync(ct);
    }

    public async Task<DownloadResponse> SetDownloadStateAsync(Guid userId, Guid downloadId, string action, CancellationToken ct = default)
    {
        var item = await db.VideoDownloads.SingleOrDefaultAsync(x => x.VideoDownloadId == downloadId && x.UserId == userId, ct) ?? throw Error(404, "DOWNLOAD_NOT_FOUND", "Không tìm thấy bản tải xuống.");
        item.Status = action.ToLowerInvariant() switch
        {
            "pause" when item.Status is "pending" or "processing" => "cancelled",
            "cancel" when item.Status is not "cancelled" => "cancelled",
            "resume" when item.Status == "cancelled" => "processing",
            "retry" when item.Status is "failed" or "cancelled" => "processing",
            _ => throw Error(409, "INVALID_DOWNLOAD_STATE", "Không thể chuyển trạng thái tải xuống theo yêu cầu.")
        };
        item.UpdatedAt = Now; await db.SaveChangesAsync(ct);
        var title = await db.Videos.Where(x => x.VideoId == item.VideoId).Select(x => x.Title).SingleAsync(ct);
        return new(item.VideoDownloadId, item.VideoId, title, item.QualityLabel, await ReadUrlAsync(item.FileUrl, ct), item.FileSize, item.Status, item.CreatedAt);
    }

    public async Task DeleteDownloadsAsync(Guid userId, IReadOnlyList<Guid> downloadIds, CancellationToken ct = default)
    {
        if (downloadIds.Count == 0) throw Error(400, "DOWNLOAD_IDS_REQUIRED", "Vui lòng chọn ít nhất một bản tải xuống.");
        var rows = await db.VideoDownloads.Where(x => x.UserId == userId && downloadIds.Contains(x.VideoDownloadId)).ToListAsync(ct);
        db.VideoDownloads.RemoveRange(rows); await db.SaveChangesAsync(ct);
    }

    private async Task<VideoResponse> ToResponseAsync(Video video, Guid? viewerId, CancellationToken ct)
    {
        var channel = await db.Channels.AsNoTracking().SingleAsync(x => x.ChannelId == video.ChannelId, ct);
        var tags = await (from vt in db.VideoTags.AsNoTracking() join tag in db.Tags.AsNoTracking() on vt.TagId equals tag.TagId where vt.VideoId == video.VideoId orderby tag.Name select tag.Name).ToListAsync(ct);
        var chapters = ReadChapters(video.Metadata);
        var likes = await db.VideoReactions.LongCountAsync(x => x.VideoId == video.VideoId && x.Type == "like", ct);
        var dislikes = await db.VideoReactions.LongCountAsync(x => x.VideoId == video.VideoId && x.Type == "dislike", ct);
        var views = await db.ViewingHistories.LongCountAsync(x => x.VideoId == video.VideoId, ct);
        var comments = await db.Comments.CountAsync(x => x.VideoId == video.VideoId && x.Status == "visible", ct);
        var ratingAggregate = await db.VideoRatings.AsNoTracking().Where(x => x.VideoId == video.VideoId)
            .GroupBy(_ => 1)
            .Select(group => new { Count = group.Count(), Average = group.Average(row => (double)row.Score) })
            .SingleOrDefaultAsync(ct);
        var shares = await db.ShareHistories.LongCountAsync(x => x.VideoId == video.VideoId, ct);
        VideoViewerStateResponse? state = null;
        if (viewerId.HasValue)
        {
            var reaction = await db.VideoReactions.AsNoTracking().SingleOrDefaultAsync(x => x.VideoId == video.VideoId && x.UserId == viewerId, ct);
            var rating = await db.VideoRatings.AsNoTracking().SingleOrDefaultAsync(x => x.VideoId == video.VideoId && x.UserId == viewerId, ct);
            var history = await db.ViewingHistories.AsNoTracking().Where(x => x.VideoId == video.VideoId && x.UserId == viewerId).OrderByDescending(x => x.ViewedAt).FirstOrDefaultAsync(ct);
            state = new(reaction?.Type, rating?.Score, history?.WatchDuration ?? 0, history?.Progress ?? 0);
        }
        return new(video.VideoId, video.ChannelId, channel.Name, channel.Handle, video.CategoryId, video.Title, video.Description,
            await ReadUrlAsync(video.VideoUrl, ct), video.ThumbnailUrl == null ? null : await ReadUrlAsync(video.ThumbnailUrl, ct), video.Duration, video.FileSize, video.Visibility, video.Status, video.ModerationStatus,
            video.LanguageCode, video.AgeRestricted, video.PublishedAt, video.CreatedAt, tags, chapters,
            new(views, likes, dislikes, comments, ratingAggregate == null ? null : Math.Round((decimal)ratingAggregate.Average, 2),
                ratingAggregate?.Count ?? 0, shares), state,
             viewerId == channel.OwnerUserId ? video.ModerationReason : null, channel.WatermarkUrl);
    }

    private async Task<IReadOnlyList<VideoResponse>> ToResponsesAsync(IReadOnlyList<Video> videos, Guid? viewerId, CancellationToken ct)
    {
        if (videos.Count == 0) return [];
        var videoIds = videos.Select(video => video.VideoId).Distinct().ToArray();
        var channelIds = videos.Select(video => video.ChannelId).Distinct().ToArray();
        var channels = await db.Channels.AsNoTracking()
            .Where(channel => channelIds.Contains(channel.ChannelId))
            .ToDictionaryAsync(channel => channel.ChannelId, ct);
        var tagRows = await (from videoTag in db.VideoTags.AsNoTracking()
                             join tag in db.Tags.AsNoTracking() on videoTag.TagId equals tag.TagId
                             where videoIds.Contains(videoTag.VideoId)
                             select new { videoTag.VideoId, TagName = tag.Name }).ToListAsync(ct);
        var tagsByVideo = tagRows.GroupBy(row => row.VideoId)
            .ToDictionary(group => group.Key, group => (IReadOnlyList<string>)group.Select(row => row.TagName).OrderBy(name => name).ToList());

        var reactionRows = await db.VideoReactions.AsNoTracking().Where(row => videoIds.Contains(row.VideoId))
            .GroupBy(row => new { row.VideoId, row.Type })
            .Select(group => new { group.Key.VideoId, group.Key.Type, Count = group.LongCount() }).ToListAsync(ct);
        var reactionStats = reactionRows.GroupBy(row => row.VideoId)
            .ToDictionary(group => group.Key, group => (
                Likes: group.Where(row => row.Type == "like").Select(row => row.Count).FirstOrDefault(),
                Dislikes: group.Where(row => row.Type == "dislike").Select(row => row.Count).FirstOrDefault()));
        var viewStats = await db.ViewingHistories.AsNoTracking().Where(row => videoIds.Contains(row.VideoId))
            .GroupBy(row => row.VideoId).Select(group => new { VideoId = group.Key, Count = group.LongCount() })
            .ToDictionaryAsync(row => row.VideoId, row => row.Count, ct);
        var commentStats = await db.Comments.AsNoTracking().Where(row => videoIds.Contains(row.VideoId) && row.Status == "visible")
            .GroupBy(row => row.VideoId).Select(group => new { VideoId = group.Key, Count = group.Count() })
            .ToDictionaryAsync(row => row.VideoId, row => row.Count, ct);
        var ratingRows = await db.VideoRatings.AsNoTracking().Where(row => videoIds.Contains(row.VideoId))
            .GroupBy(row => row.VideoId)
            .Select(group => new { VideoId = group.Key, Count = group.Count(), Average = group.Average(row => (double)row.Score) })
            .ToDictionaryAsync(row => row.VideoId, row => (row.Count, Average: (decimal?)row.Average), ct);
        var shareStats = await db.ShareHistories.AsNoTracking().Where(row => videoIds.Contains(row.VideoId))
            .GroupBy(row => row.VideoId).Select(group => new { VideoId = group.Key, Count = group.LongCount() })
            .ToDictionaryAsync(row => row.VideoId, row => row.Count, ct);

        var viewerReactions = viewerId.HasValue
            ? await db.VideoReactions.AsNoTracking().Where(row => row.UserId == viewerId && videoIds.Contains(row.VideoId))
                .ToDictionaryAsync(row => row.VideoId, row => row.Type, ct)
            : new Dictionary<Guid, string>();
        var viewerRatings = viewerId.HasValue
            ? await db.VideoRatings.AsNoTracking().Where(row => row.UserId == viewerId && videoIds.Contains(row.VideoId))
                .ToDictionaryAsync(row => row.VideoId, row => (int?)row.Score, ct)
            : new Dictionary<Guid, int?>();
        Dictionary<Guid, ViewerHistoryRow> viewerHistory;
        if (viewerId.HasValue)
        {
            var historyRows = await db.ViewingHistories.AsNoTracking()
                .Where(row => row.UserId == viewerId && videoIds.Contains(row.VideoId))
                .OrderByDescending(row => row.ViewedAt).ThenByDescending(row => row.ViewingHistoryId)
                .Select(row => new { row.VideoId, row.WatchDuration, row.Progress })
                .ToListAsync(ct);
            viewerHistory = historyRows.GroupBy(row => row.VideoId)
                .ToDictionary(group => group.Key, group => new ViewerHistoryRow(group.First().WatchDuration, group.First().Progress));
        }
        else
        {
            viewerHistory = [];
        }

        var urlPaths = videos.SelectMany(video => new[] { video.VideoUrl, video.ThumbnailUrl,
            channels.GetValueOrDefault(video.ChannelId)?.WatermarkUrl });
        var urls = await ResolveReadUrlsAsync(urlPaths, ct);
        return videos.Select(video =>
        {
            var channel = channels[video.ChannelId];
            reactionStats.TryGetValue(video.VideoId, out var reactions);
            ratingRows.TryGetValue(video.VideoId, out var rating);
            viewerHistory.TryGetValue(video.VideoId, out var history);
            viewerReactions.TryGetValue(video.VideoId, out var myReaction);
            viewerRatings.TryGetValue(video.VideoId, out var myRating);
            var stats = new VideoStatsResponse(viewStats.GetValueOrDefault(video.VideoId), reactions.Likes,
                reactions.Dislikes, commentStats.GetValueOrDefault(video.VideoId), rating.Average,
                rating.Count, shareStats.GetValueOrDefault(video.VideoId));
            var state = viewerId.HasValue
                ? new VideoViewerStateResponse(myReaction, myRating, history?.WatchDuration ?? 0, history?.Progress ?? 0)
                : null;
            return new VideoResponse(video.VideoId, video.ChannelId, channel.Name, channel.Handle, video.CategoryId,
                video.Title, video.Description, urls[video.VideoUrl], video.ThumbnailUrl == null ? null : urls.GetValueOrDefault(video.ThumbnailUrl),
                video.Duration, video.FileSize, video.Visibility, video.Status, video.ModerationStatus, video.LanguageCode,
                video.AgeRestricted, video.PublishedAt, video.CreatedAt, tagsByVideo.GetValueOrDefault(video.VideoId, []),
                ReadChapters(video.Metadata), stats, state, viewerId == channel.OwnerUserId ? video.ModerationReason : null,
                channel.WatermarkUrl == null ? null : urls.GetValueOrDefault(channel.WatermarkUrl));
        }).ToList();
    }

    private async Task<Dictionary<string, string>> ResolveReadUrlsAsync(IEnumerable<string?> paths, CancellationToken ct)
    {
        var unique = paths.Where(path => !string.IsNullOrWhiteSpace(path))
            .Select(path => path!)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        var resolved = await Task.WhenAll(unique.Select(async path =>
            (Path: path, Url: await ReadUrlAsync(path, ct))));
        return resolved.ToDictionary(item => item.Path, item => item.Url, StringComparer.Ordinal);
    }

    private async Task PublishInteractionNotificationAsync(Guid recipientId, Guid actorId, string type, string title,
        string content, string? actionUrl, string? resourceType, Guid? resourceId, CancellationToken ct)
    {
        if (recipientId == actorId) return;
        try
        {
            await notifications.PublishInAppAsync(recipientId, type, title, content, actionUrl, resourceType, resourceId, ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // Reactions and comments are already persisted. A disconnected SignalR
            // client or a notification storage issue must not make the user retry
            // the interaction and accidentally create duplicates.
            logger.LogWarning(ex, "Could not publish {NotificationType} notification to {UserId}", type, recipientId);
        }
    }

    private static LibraryVideoResponse ToLibraryResponse(VideoResponse video, int watchedSeconds, decimal progress, DateTimeOffset activityAt) =>
        new(video.VideoId, video.ChannelId, video.ChannelName, video.ChannelHandle, video.Title, video.ThumbnailUrl,
            video.Duration, video.Visibility, video.PublishedAt, video.Stats.Views, video.Stats.Likes, video.Stats.Dislikes,
            video.Stats.AverageRating, video.Stats.RatingCount, video.ViewerState?.Rating, watchedSeconds, progress, activityAt);

    private async Task<CommentResponse> ToCommentAsync(Comment comment, Guid? viewerId, CancellationToken ct)
    {
        var user = await db.Users.IgnoreQueryFilters().AsNoTracking().SingleAsync(x => x.UserId == comment.UserId, ct);
        var likes = await db.CommentReactions.LongCountAsync(x => x.CommentId == comment.CommentId && x.Type == "like", ct);
        var dislikes = await db.CommentReactions.LongCountAsync(x => x.CommentId == comment.CommentId && x.Type == "dislike", ct);
        var mine = viewerId.HasValue ? await db.CommentReactions.AsNoTracking().SingleOrDefaultAsync(x => x.CommentId == comment.CommentId && x.UserId == viewerId, ct) : null;
        var replies = await db.Comments.CountAsync(x => x.ParentCommentId == comment.CommentId && x.Status == "visible", ct);
        return new(comment.CommentId, comment.VideoId, comment.UserId, user.DisplayName, comment.ParentCommentId, comment.Content, comment.Status, comment.CreatedAt, comment.UpdatedAt, likes, dislikes, mine?.Type, replies);
    }

    private async Task<IReadOnlyList<CommentResponse>> ToCommentsAsync(IReadOnlyList<Comment> comments, Guid? viewerId, CancellationToken ct)
    {
        if (comments.Count == 0) return [];
        var commentIds = comments.Select(comment => comment.CommentId).ToArray();
        var userIds = comments.Select(comment => comment.UserId).Distinct().ToArray();
        var users = await db.Users.IgnoreQueryFilters().AsNoTracking()
            .Where(user => userIds.Contains(user.UserId))
            .ToDictionaryAsync(user => user.UserId, user => user.DisplayName, ct);
        var reactionRows = await db.CommentReactions.AsNoTracking().Where(reaction => commentIds.Contains(reaction.CommentId))
            .GroupBy(reaction => new { reaction.CommentId, reaction.Type })
            .Select(group => new { group.Key.CommentId, group.Key.Type, Count = group.LongCount() }).ToListAsync(ct);
        var reactionStats = reactionRows.GroupBy(row => row.CommentId).ToDictionary(group => group.Key, group => (
            Likes: group.Where(row => row.Type == "like").Select(row => row.Count).FirstOrDefault(),
            Dislikes: group.Where(row => row.Type == "dislike").Select(row => row.Count).FirstOrDefault()));
        var replies = await db.Comments.AsNoTracking().Where(row => row.ParentCommentId.HasValue
                && commentIds.Contains(row.ParentCommentId.Value) && row.Status == "visible")
            .GroupBy(row => row.ParentCommentId!.Value)
            .Select(group => new { CommentId = group.Key, Count = group.Count() })
            .ToDictionaryAsync(row => row.CommentId, row => row.Count, ct);
        var mine = viewerId.HasValue
            ? await db.CommentReactions.AsNoTracking().Where(reaction => reaction.UserId == viewerId && commentIds.Contains(reaction.CommentId))
                .ToDictionaryAsync(reaction => reaction.CommentId, reaction => reaction.Type, ct)
            : new Dictionary<Guid, string>();
        return comments.Select(comment =>
        {
            reactionStats.TryGetValue(comment.CommentId, out var stats);
            mine.TryGetValue(comment.CommentId, out var myReaction);
            return new CommentResponse(comment.CommentId, comment.VideoId, comment.UserId,
                users.GetValueOrDefault(comment.UserId, "Người dùng"), comment.ParentCommentId, comment.Content,
                comment.Status, comment.CreatedAt, comment.UpdatedAt, stats.Likes, stats.Dislikes, myReaction,
                replies.GetValueOrDefault(comment.CommentId));
        }).ToList();
    }

    private async Task<Video> RequireVideoAsync(Guid id, CancellationToken ct) => await db.Videos.SingleOrDefaultAsync(x => x.VideoId == id && x.Status != "deleted", ct) ?? throw Error(404, "VIDEO_NOT_FOUND", "Không tìm thấy video.");
    private async Task<Comment> RequireCommentAsync(Guid id, CancellationToken ct) => await db.Comments.SingleOrDefaultAsync(x => x.CommentId == id && x.Status != "deleted", ct) ?? throw Error(404, "COMMENT_NOT_FOUND", "Không tìm thấy bình luận.");

    private async Task EnsureCanViewAsync(Video video, Guid? viewerId, CancellationToken ct)
    {
        // Local development can publish unlisted videos while moderation is disabled.
        // They must remain reachable by anyone holding the link, while public-feed
        // queries continue to require an approved public video.
        var canViewByLink = video.Status == "published" && video.Visibility == "unlisted"
            && (!features.ModerationEnabled || video.ModerationStatus == "approved");
        var canViewPublicly = video.Status == "published" && video.Visibility == "public"
            && video.ModerationStatus == "approved";
        if (canViewByLink || canViewPublicly) return;
        if (viewerId.HasValue && await HasChannelPermissionAsync(video.ChannelId, viewerId.Value, ChannelPermissions.VideoView, ct)) return;
        throw Error(viewerId.HasValue ? 403 : 404, "VIDEO_NOT_AVAILABLE", "Video không khả dụng.");
    }

    private IQueryable<Video> LibraryVisibleVideos(Guid userId) =>
        db.Videos.AsNoTracking().Where(video =>
            video.Status != "deleted" &&
            ((video.Status == "published" &&
              ((video.Visibility == "public" && video.ModerationStatus == "approved") ||
               (video.Visibility == "unlisted" && (!features.ModerationEnabled || video.ModerationStatus == "approved"))))
             || db.Channels.Any(channel => channel.ChannelId == video.ChannelId && channel.OwnerUserId == userId)
             || db.ChannelMembers.Any(member => member.ChannelId == video.ChannelId && member.UserId == userId && member.Status == "active" &&
                 (member.RoleCode == ChannelRoles.Manager || member.RoleCode == ChannelRoles.Editor || member.RoleCode == ChannelRoles.Viewer))));

    private async Task<Channel> RequireChannelPermissionAsync(Guid channelId, Guid actorId, string permission, CancellationToken ct)
    {
        var channel = await db.Channels.SingleOrDefaultAsync(x => x.ChannelId == channelId, ct) ?? throw Error(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");
        if (channel.Status == "suspended") throw Error(403, "CHANNEL_SUSPENDED", "Kênh đã bị khóa do vi phạm chính sách cộng đồng.");
        if (channel.Status != "active") throw Error(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");
        if (!await HasChannelPermissionAsync(channelId, actorId, permission, ct)) throw Error(403, "CHANNEL_PERMISSION_DENIED", "Bạn không có quyền thực hiện thao tác này trên kênh.");
        return channel;
    }

    private async Task<bool> HasChannelPermissionAsync(Guid channelId, Guid actorId, string permission, CancellationToken ct)
    {
        var channel = await db.Channels.AsNoTracking().SingleOrDefaultAsync(x => x.ChannelId == channelId, ct);
        if (channel?.OwnerUserId == actorId) return true;
        var role = await db.ChannelMembers.AsNoTracking().Where(x => x.ChannelId == channelId && x.UserId == actorId && x.Status == "active").Select(x => x.RoleCode).SingleOrDefaultAsync(ct);
        return ChannelPermissions.RoleHas(role, permission);
    }

    private async Task ReplaceTagsAsync(Guid videoId, IReadOnlyList<string> names, CancellationToken ct)
    {
        var old = await db.VideoTags.Where(x => x.VideoId == videoId).ToListAsync(ct);
        db.VideoTags.RemoveRange(old);
        if (names.Count == 0) return;
        var existing = await db.Tags.AsNoTracking().Where(tag => names.Contains(tag.Name)).ToListAsync(ct);
        var tagsByName = existing.ToDictionary(tag => tag.Name, StringComparer.OrdinalIgnoreCase);
        var now = Now;
        foreach (var name in names)
        {
            if (!tagsByName.TryGetValue(name, out var tag))
            {
                tag = new Tag { Name = name, CreatedAt = now };
                db.Tags.Add(tag);
                tagsByName[name] = tag;
            }
            db.VideoTags.Add(new VideoTag { VideoId = videoId, TagId = tag.TagId, CreatedAt = now });
        }
    }

    private async Task<int> MaxDownloadHeightAsync(Guid userId, CancellationToken ct)
    {
        if (!features.PlanEnforcementEnabled) return int.MaxValue;
        var plan = await GetEffectivePlanForUserAsync(userId, ct);
        var quality = plan?.MaxDownloadQuality ?? plan?.MaxVideoQuality ?? "720p";
        return VideoRules.QualityHeight(quality) is > 0 and var value ? value : 720;
    }

    private async Task EnsureDownloadAllowedAsync(Guid userId, CancellationToken ct)
    {
        if (!features.PlanEnforcementEnabled) return;
        var plan = await GetEffectivePlanForUserAsync(userId, ct);
        if (plan == null || !PlanEntitlementRules.IsEnabled(plan.Features, PlanEntitlementRules.Download))
            throw Error(403, "DOWNLOAD_NOT_INCLUDED", "Gói hiện tại không bao gồm quyền tải video xuống.");
    }

    private async Task<Plan?> GetEffectivePlanForUserAsync(Guid userId, CancellationToken ct)
    {
        var user = await db.Users.AsNoTracking().SingleAsync(x => x.UserId == userId, ct);
        if (user.PlanId.HasValue)
        {
            var selected = await GetEffectivePlanAsync(userId, user.PlanId.Value, ct);
            if (selected != null) return selected;
        }

        var sharedPlan = await (from member in db.PlanMembers.AsNoTracking()
                                join history in db.PlanHistories.AsNoTracking() on member.PlanHistoryId equals history.PlanHistoryId
                                join plan in db.Plans.AsNoTracking() on history.PlanId equals plan.PlanId
                                where member.MemberUserId == userId && member.Status == "accepted"
                                      && history.Status == "active" && (!history.EndedAt.HasValue || history.EndedAt > Now) && plan.Status == "active"
                                orderby history.EndedAt descending
                                select plan).FirstOrDefaultAsync(ct);
        if (sharedPlan != null) return sharedPlan;

        // Users without an active subscription still use the configured Free plan.
        // This keeps admin changes to the Free plan effective for legacy accounts
        // that predate plan histories.
        return await db.Plans.AsNoTracking()
            .Where(x => x.Code == "free" && x.Status == "active")
            .FirstOrDefaultAsync(ct);
    }

    private async Task<Plan?> GetEffectivePlanAsync(Guid userId, Guid planId, CancellationToken ct)
    {
        var plan = await db.Plans.AsNoTracking().SingleOrDefaultAsync(x => x.PlanId == planId && x.Status == "active", ct);
        if (plan == null) return null;
        var now = Now;
        var hasSubscription = await db.PlanHistories.AsNoTracking().AnyAsync(x =>
            x.UserId == userId && x.PlanId == planId && x.Status == "active" && (!x.EndedAt.HasValue || x.EndedAt > now), ct)
            || await (from member in db.PlanMembers.AsNoTracking()
                      join history in db.PlanHistories.AsNoTracking() on member.PlanHistoryId equals history.PlanHistoryId
                      where member.MemberUserId == userId && member.Status == "accepted" && history.PlanId == planId
                            && history.Status == "active" && (!history.EndedAt.HasValue || history.EndedAt > now)
                      select member.PlanMemberId).AnyAsync(ct);
        return hasSubscription ? plan : null;
    }

    private static IReadOnlyList<VideoChapter> ReadChapters(string metadata)
    {
        try { return JsonSerializer.Deserialize<Metadata>(metadata, new JsonSerializerOptions(JsonSerializerDefaults.Web))?.Chapters ?? []; }
        catch (JsonException) { return []; }
    }
    private sealed record Metadata(IReadOnlyList<VideoChapter> Chapters);
    private static IReadOnlyList<string> NormalizeTags(IEnumerable<string>? tags) => (tags ?? []).Select(x => x.Trim().TrimStart('#').ToLowerInvariant()).Where(x => x.Length is > 0 and <= 80).Distinct().Take(20).ToArray();
    private static string? Clean(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    private void EnsureVisibilityAvailable(string visibility)
    {
        if (!features.ModerationEnabled && visibility.Equals("public", StringComparison.OrdinalIgnoreCase))
            throw Error(409, "PUBLICATION_LOCKED", "Chế độ công khai đang tạm khóa cho đến khi kiểm duyệt được bật.");
    }
    private static ModerationCase CreateUploadModerationCase(Video video, DateTimeOffset now) => new()
    {
        VideoId = video.VideoId,
        Status = "pending",
        CaseType = "upload_review",
        RiskLevel = ModerationRiskLevel(video.Title, video.Description),
        SubmittedAt = now,
        UpdatedAt = now
    };
    private static string ModerationRiskLevel(string title, string? description)
    {
        var combinedText = $"{title} {description}".ToLowerInvariant();
        var highRiskKeywords = new[] { "sex", "khiêu dâm", "đồi trụy", "18+", "giết người", "tự tử", "chém", "bom", "hack", "lừa đảo" };
        return highRiskKeywords.Any(k => combinedText.Contains(k)) ? "high" : "low";
    }
    private static (int Page, int PageSize) Page(int page, int size) => (Math.Max(1, page), Math.Clamp(size, 1, 50));
    private static ContentException Error(int status, string code, string message) => new(status, code, message);
    private Task<string> ReadUrlAsync(string path, CancellationToken ct) => storage.GetReadUrlAsync(path, TimeSpan.FromMinutes(60), ct);
}
