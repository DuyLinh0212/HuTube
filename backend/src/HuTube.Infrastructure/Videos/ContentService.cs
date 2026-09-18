using System.Data;
using System.Text.Json;
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
    ILogger<ContentService> logger) : IContentService
{
    private DateTimeOffset Now => clock.GetUtcNow();

    public async Task<IReadOnlyList<CategoryResponse>> GetCategoriesAsync(CancellationToken ct = default) =>
        await db.Categories.AsNoTracking().Where(x => x.Status == "active").OrderBy(x => x.Name)
            .Select(x => new CategoryResponse(x.CategoryId, x.Name, x.Slug, x.Description)).ToListAsync(ct);

    public async Task<PageResult<VideoCardResponse>> GetFeedAsync(string feed, string? sort, Guid? categoryId, string? tag, int page, int pageSize, CancellationToken ct = default)
    {
        (page, pageSize) = Page(page, pageSize);
        var query = db.Videos.AsNoTracking().Where(x => x.Status == "published" && x.ModerationStatus == "approved" && x.Visibility == "public");
        if (categoryId.HasValue) query = query.Where(x => x.CategoryId == categoryId);
        if (!string.IsNullOrWhiteSpace(tag))
        {
            var normalizedTag = tag.Trim().ToLowerInvariant();
            query = query.Where(x => db.VideoTags.Any(videoTag => videoTag.VideoId == x.VideoId &&
                db.Tags.Any(tagRow => tagRow.TagId == videoTag.TagId && tagRow.Name.ToLower() == normalizedTag)));
        }
        var filteredTotal = await query.CountAsync(ct);
        var hasColdStartFilter = categoryId.HasValue || !string.IsNullOrWhiteSpace(tag);
        var fallbackToDefault = hasColdStartFilter && filteredTotal == 0;
        var total = filteredTotal;
        if (fallbackToDefault)
        {
            // Guest cold-start falls back from Category/Tag to the public newest/popular catalogue.
            query = db.Videos.AsNoTracking().Where(x => x.Status == "published" && x.ModerationStatus == "approved" && x.Visibility == "public");
            total = await query.CountAsync(ct);
        }
        var rows = from video in query
                   join channel in db.Channels.AsNoTracking() on video.ChannelId equals channel.ChannelId
                   select new { video.VideoId, video.ChannelId, ChannelName = channel.Name, ChannelHandle = channel.Handle,
                       video.Title, video.ThumbnailUrl, video.Duration, video.Visibility, video.PublishedAt,
                       Views = db.ViewingHistories.LongCount(history => history.VideoId == video.VideoId) };
        rows = (feed.ToLowerInvariant(), sort?.ToLowerInvariant()) switch
        {
            ("home", _) => rows.OrderByDescending(x => x.Views).ThenByDescending(x => x.PublishedAt),
            (_, "popular") => rows.OrderByDescending(x => x.Views).ThenByDescending(x => x.PublishedAt),
            (_, "trending") => rows.OrderByDescending(x => x.Views).ThenByDescending(x => x.PublishedAt),
            _ => rows.OrderByDescending(x => x.PublishedAt)
        };
        var pageRows = await rows.Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        var cards = new List<VideoCardResponse>();
        foreach (var row in pageRows) cards.Add(new(row.VideoId, row.ChannelId, row.ChannelName, row.ChannelHandle,
            row.Title, row.ThumbnailUrl == null ? null : await ReadUrlAsync(row.ThumbnailUrl, ct), row.Duration, row.Visibility, row.PublishedAt, row.Views));
        return new(cards, page, pageSize, total);
    }

    public async Task<PageResult<LibraryVideoResponse>> GetWatchHistoryAsync(Guid userId, int page, int pageSize, CancellationToken ct = default)
    {
        (page, pageSize) = Page(page, pageSize);
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
        var query = from history in latest
                    join video in LibraryVisibleVideos(userId) on history.VideoId equals video.VideoId
                    orderby history.ViewedAt descending
                    select new { Video = video, history.WatchDuration, history.Progress, history.ViewedAt };

        var total = await query.CountAsync(ct);
        var rows = await query.Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        var items = new List<LibraryVideoResponse>(rows.Count);
        foreach (var row in rows)
        {
            var detail = await ToResponseAsync(row.Video, userId, ct);
            items.Add(ToLibraryResponse(detail, row.WatchDuration, row.Progress, row.ViewedAt));
        }

        return new(items, page, pageSize, total);
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
        var items = new List<LibraryVideoResponse>(rows.Count);
        foreach (var row in rows)
        {
            var detail = await ToResponseAsync(row.Video, userId, ct);
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
        var effectivePlan = features.PlanEnforcementEnabled ? await GetEffectivePlanForUserAsync(channel.OwnerUserId, ct) : null;
        if (quota != null)
        {
            if (features.PlanEnforcementEnabled)
                quota.StorageLimit = effectivePlan?.StorageLimit ?? ChannelQuotaRules.DefaultStorageLimit;
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
            Metadata = JsonSerializer.Serialize(new { chapters }), CreatedAt = now, UpdatedAt = now };
        var generated = new List<(TranscodedVideo Rendition, string StoredPath)>();
        Exception? processingError = null;
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

        await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        try
        {
            if (quota != null)
            {
                if (features.PlanEnforcementEnabled)
                    quota.StorageLimit = effectivePlan?.StorageLimit ?? ChannelQuotaRules.DefaultStorageLimit;
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
            await ReplaceTagsAsync(video.VideoId, tags, ct); await db.SaveChangesAsync(ct); await transaction.CommitAsync(ct);
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
            try { Directory.Delete(temporaryDirectory, true); }
            catch (IOException ex) { logger.LogWarning(ex, "Không thể xóa thư mục xử lý video {Directory}", temporaryDirectory); }
        }
        return await ToResponseAsync(video, actorId, ct);
    }

    public async Task<UploadPreflightResponse> PreflightAsync(Guid actorId, UploadPreflightRequest request, CancellationToken ct = default)
    {
        var channel = await RequireChannelPermissionAsync(request.ChannelId, actorId, ChannelPermissions.VideoUpload, ct);
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
        var limit = features.PlanEnforcementEnabled
            ? plan?.StorageLimit ?? ChannelQuotaRules.DefaultStorageLimit
            : quota?.StorageLimit ?? maxUpload;
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
        if (!string.IsNullOrWhiteSpace(search)) { var term = search.Trim().ToLower(); query = query.Where(x => x.Title.ToLower().Contains(term)); }
        if (categoryId.HasValue) query = query.Where(x => x.CategoryId == categoryId);
        if (!string.IsNullOrWhiteSpace(tag))
        {
            var normalizedTag = tag.Trim().TrimStart('#').ToLower();
            query = query.Where(x => db.VideoTags.Any(vt => vt.VideoId == x.VideoId && db.Tags.Any(t => t.TagId == vt.TagId && t.Name.ToLower() == normalizedTag)));
        }
        var total = await query.CountAsync(ct);
        var videos = await query.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        var items = new List<VideoResponse>();
        foreach (var video in videos) items.Add(await ToResponseAsync(video, actorId, ct));
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
            try { video.Metadata = JsonSerializer.Serialize(new { chapters = VideoRules.ValidateChapters(request.Chapters.Select(x => new VideoChapter(x.StartSeconds, x.Title)), video.Duration) }); }
            catch (VideoValidationException ex) { throw Error(400, ex.Code, ex.Message); }
        }
        if (request.Tags != null) await ReplaceTagsAsync(video.VideoId, NormalizeTags(request.Tags), ct);
        video.UpdatedAt = Now;
        await db.SaveChangesAsync(ct);
        return await ToResponseAsync(video, actorId, ct);
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
        video.Status = "published"; video.PublishedAt ??= Now; video.UpdatedAt = Now;
        await db.SaveChangesAsync(ct);
        await notifications.PublishAsync(actorId, "video_published", "Video đã được xuất bản", video.Title, $"/watch/{video.VideoId}", "video", video.VideoId, ct);
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
        video.Status = "processing"; video.ModerationStatus = "not_submitted"; video.UpdatedAt = Now;
        var renditions = await db.VideoRenditions.Where(x => x.VideoId == videoId && x.Status == "failed").ToListAsync(ct);
        foreach (var rendition in renditions) { rendition.Status = "processing"; rendition.UpdatedAt = Now; }
        await db.SaveChangesAsync(ct); return await ToResponseAsync(video, actorId, ct);
    }

    public async Task<WatchProgressResponse> SaveProgressAsync(Guid userId, Guid videoId, WatchProgressRequest request, CancellationToken ct = default)
    {
        var video = await RequireVideoAsync(videoId, ct); await EnsureCanViewAsync(video, userId, ct);
        decimal progress;
        try { progress = VideoRules.CalculateProgress(request.WatchedSeconds, video.Duration); }
        catch (VideoValidationException ex) { throw Error(400, ex.Code, ex.Message); }
        if (!request.SaveHistory) return new(Math.Clamp(request.WatchedSeconds, 0, video.Duration), progress, Now);
        var item = await db.ViewingHistories.Where(x => x.UserId == userId && x.VideoId == videoId).OrderByDescending(x => x.ViewedAt).FirstOrDefaultAsync(ct);
        if (item == null) { item = new ViewingHistory { UserId = userId, VideoId = videoId }; db.ViewingHistories.Add(item); }
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
        return new(normalizedReaction, await db.VideoReactions.LongCountAsync(x => x.VideoId == videoId && x.Type == "like", ct), await db.VideoReactions.LongCountAsync(x => x.VideoId == videoId && x.Type == "dislike", ct));
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
        var values = await db.VideoRatings.AsNoTracking().Where(x => x.VideoId == videoId).Select(x => (int)x.Score).ToListAsync(ct);
        return new(score, values.Count == 0 ? null : Math.Round((decimal)values.Average(), 2), values.Count);
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
        var comments = await (sort.Equals("top", StringComparison.OrdinalIgnoreCase)
            ? query.OrderByDescending(x => db.CommentReactions.Count(r => r.CommentId == x.CommentId && r.Type == "like")).ThenByDescending(x => x.CreatedAt)
            : query.OrderByDescending(x => x.CreatedAt)).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        var items = new List<CommentResponse>(); foreach (var comment in comments) items.Add(await ToCommentAsync(comment, viewerId, ct));
        return new(items, page, pageSize, total);
    }

    public async Task<PageResult<CommentResponse>> GetRepliesAsync(Guid commentId, Guid? viewerId, int page, int pageSize, CancellationToken ct = default)
    {
        var parent = await RequireCommentAsync(commentId, ct); var video = await RequireVideoAsync(parent.VideoId, ct);
        await EnsureCanViewAsync(video, viewerId, ct); (page, pageSize) = Page(page, pageSize);
        var query = db.Comments.AsNoTracking().Where(x => x.ParentCommentId == commentId && x.Status == "visible");
        var total = await query.CountAsync(ct); var replies = await query.OrderBy(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        var items = new List<CommentResponse>(); foreach (var reply in replies) items.Add(await ToCommentAsync(reply, viewerId, ct));
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
        var items = new List<CommentResponse>(); foreach (var row in rows) items.Add(await ToCommentAsync(row, actorId, ct));
        return new(items, page, pageSize, total);
    }

    public async Task<IReadOnlyList<ViolationTypeResponse>> GetViolationTypesAsync(CancellationToken ct = default) =>
        await db.ViolationTypes.AsNoTracking().Where(x => x.Status == "active").OrderBy(x => x.Name)
            .Select(x => new ViolationTypeResponse(x.ViolationTypeId, x.Code, x.Name, x.Description)).ToListAsync(ct);

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
        if (!await db.ViolationTypes.AnyAsync(x => x.ViolationTypeId == request.ViolationTypeId && x.Status == "active", ct)) throw Error(400, "INVALID_VIOLATION_TYPE", "Loại vi phạm không hợp lệ.");
        var description = Clean(request.Description); if (description == null) throw Error(400, "DESCRIPTION_REQUIRED", "Vui lòng mô tả vi phạm.");
        var report = new Report { UserId = userId, CommentId = commentId, ViolationTypeId = request.ViolationTypeId, Description = description, CreatedAt = Now, UpdatedAt = Now };
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
        var maxHeight = await MaxDownloadHeightAsync(userId, ct);
        var selected = await db.VideoRenditions.AsNoTracking().SingleOrDefaultAsync(x => x.VideoId == videoId && x.Status == "ready"
            && x.QualityLabel.ToLower() == quality.ToLower() && x.Height <= maxHeight, ct)
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
                          where item.UserId == userId orderby item.CreatedAt descending select new { item, video.Title }).ToListAsync(ct);
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
        var ratings = await db.VideoRatings.AsNoTracking().Where(x => x.VideoId == video.VideoId).Select(x => (int)x.Score).ToListAsync(ct);
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
            new(views, likes, dislikes, comments, ratings.Count == 0 ? null : Math.Round((decimal)ratings.Average(), 2), ratings.Count, shares), state);
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
        var channel = await db.Channels.SingleOrDefaultAsync(x => x.ChannelId == channelId && x.Status == "active", ct) ?? throw Error(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");
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
        var old = await db.VideoTags.Where(x => x.VideoId == videoId).ToListAsync(ct); db.VideoTags.RemoveRange(old); await db.SaveChangesAsync(ct);
        foreach (var name in names)
        {
            var lower = name.ToLowerInvariant();
            var tag = await db.Tags.FirstOrDefaultAsync(x => x.Name.ToLower() == lower, ct);
            if (tag == null) { tag = new Tag { Name = name, CreatedAt = Now }; db.Tags.Add(tag); await db.SaveChangesAsync(ct); }
            db.VideoTags.Add(new VideoTag { VideoId = videoId, TagId = tag.TagId, CreatedAt = Now });
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

        return await (from member in db.PlanMembers.AsNoTracking()
                      join history in db.PlanHistories.AsNoTracking() on member.PlanHistoryId equals history.PlanHistoryId
                      join plan in db.Plans.AsNoTracking() on history.PlanId equals plan.PlanId
                      where member.MemberUserId == userId && member.Status == "accepted"
                            && history.Status == "active" && (!history.EndedAt.HasValue || history.EndedAt > Now) && plan.Status == "active"
                      orderby history.EndedAt descending
                      select plan).FirstOrDefaultAsync(ct);
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
