using HuTube.Application.Payments;
using HuTube.Application.Plans;
using HuTube.Infrastructure.Payments;
using HuTube.Infrastructure.Persistence;
using HuTube.Infrastructure.Videos;
using Microsoft.Extensions.DependencyInjection;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using HuTube.Application.Playlists;
using HuTube.Application.Account;
using HuTube.Application.Auth;
using HuTube.Application.Channels;
using HuTube.Application.Videos;
using HuTube.Application.Notifications;
using HuTube.Domain.Videos;
using Microsoft.EntityFrameworkCore;

namespace HuTube.IntegrationTests;

public sealed class ContentApiIntegrationTests(AuthApiFactory factory) : IClassFixture<AuthApiFactory>
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    [Fact]
    public async Task NotificationPreferencesAndPaging_ControlReplyDelivery()
    {
        // Arrange
        var (owner, ownerId, channelId) = await CreateUserAndChannelAsync("notify_owner");
        var (viewer, _, _) = await CreateUserAndChannelAsync("notify_viewer");
        var video = await CreatePublishedVideoAsync(owner, channelId, "Video notifications");
        var parentResponse = await owner.PostAsJsonAsync($"/api/v1/videos/{video.VideoId}/comments", new { content = "Hỏi đáp", parentCommentId = (Guid?)null });
        var parent = await parentResponse.Content.ReadFromJsonAsync<CommentResponse>(JsonOptions);
        await owner.PutAsJsonAsync("/api/v1/account/notifications", new
        {
            inAppEnabled = true, emailEnabled = false, newVideoEnabled = true, commentReplyEnabled = false,
            reportResultEnabled = true, moderationEnabled = true, planEnabled = true, recommendationEnabled = true,
            mentionEnabled = true, channelActivityEnabled = true, paymentEnabled = true
        });

        // Act
        await viewer.PostAsJsonAsync($"/api/v1/videos/{video.VideoId}/comments", new { content = "Reply bị tắt", parentCommentId = parent!.CommentId });
        var disabled = await owner.GetFromJsonAsync<NotificationPage>("/api/v1/notifications", JsonOptions);
        await owner.PutAsJsonAsync("/api/v1/account/notifications", new
        {
            inAppEnabled = true, emailEnabled = false, newVideoEnabled = true, commentReplyEnabled = true,
            reportResultEnabled = true, moderationEnabled = true, planEnabled = true, recommendationEnabled = true,
            mentionEnabled = true, channelActivityEnabled = true, paymentEnabled = true
        });
        await viewer.PostAsJsonAsync($"/api/v1/videos/{video.VideoId}/comments", new { content = "Reply được bật", parentCommentId = parent.CommentId });
        await using (var db = factory.CreateDb())
        {
            for (var i = 0; i < 6; i++) db.Notifications.Add(new Notification { UserId = ownerId, Type = "test", Title = $"Test {i}", Content = "Paging", CreatedAt = DateTimeOffset.UtcNow.AddSeconds(i) });
            await db.SaveChangesAsync();
        }
        var firstPage = await owner.GetFromJsonAsync<NotificationPage>("/api/v1/notifications", JsonOptions);
        var missing = await owner.PatchAsJsonAsync($"/api/v1/notifications/{Guid.NewGuid()}/read", new { });

        // Assert
        Assert.DoesNotContain(disabled!.Items, x => x.Type == "comment_reply");
        Assert.Equal(5, firstPage!.Items.Count);
        Assert.True(firstPage.HasMore);
        Assert.Equal(HttpStatusCode.NotFound, missing.StatusCode);
        Assert.Contains(await factory.CreateDb().Notifications.AsNoTracking().ToListAsync(), x => x.UserId == ownerId && x.Type == "comment_reply");
    }

    [Fact]
    public async Task UploadModeratePublish_ExposesVideoInPublicFeedsAndPlayback()
    {
        // Arrange
        var (owner, ownerId, channelId) = await CreateUserAndChannelAsync("publisher");
        using var watermarkForm = new MultipartFormDataContent();
        var watermarkFile = new ByteArrayContent(Convert.FromBase64String(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j8ioAAAAASUVORK5CYII="));
        watermarkFile.Headers.ContentType = new MediaTypeHeaderValue("image/png");
        watermarkForm.Add(watermarkFile, "file", "publisher.png");
        var watermarkUpload = await owner.PostAsync($"/api/v1/channels/{channelId}/watermark", watermarkForm);
        var channelWithWatermark = await watermarkUpload.Content.ReadFromJsonAsync<ChannelResponse>(JsonOptions);
        var watermarkReadUrl = channelWithWatermark!.WatermarkUrl;
        Assert.Equal(HttpStatusCode.OK, watermarkUpload.StatusCode);
        Assert.StartsWith("https://storage.test/channel-watermarks/", watermarkReadUrl);

        // Act
        var upload = await UploadAsync(owner, channelId, "Video công khai");
        await using (var db = factory.CreateDb())
        {
            var persisted = await db.Videos.AsNoTracking().SingleAsync(x => x.VideoId == upload.VideoId);
            Assert.Equal(ownerId, persisted.UploadedByUserId);
            Assert.Equal("pending", persisted.ModerationStatus);
            Assert.True(await db.ModerationCases.AnyAsync(x => x.VideoId == upload.VideoId && x.CaseType == "upload_review" && x.Status == "pending"));
        }
        var privateResponse = await factory.CreateClient().GetAsync($"/api/v1/videos/{upload.VideoId}");
        var submit = await owner.PostAsync($"/api/v1/videos/{upload.VideoId}/submit-moderation", null);
        await ApproveAsync(upload.VideoId);
        var publish = await owner.PostAsync($"/api/v1/videos/{upload.VideoId}/publish", null);
        var anonymous = factory.CreateClient();
        var home = await anonymous.GetFromJsonAsync<PageResult<VideoCardResponse>>("/api/v1/feed/home", JsonOptions);
        var explore = await anonymous.GetFromJsonAsync<PageResult<VideoCardResponse>>("/api/v1/feed/explore?sort=newest", JsonOptions);
        var playback = await anonymous.GetFromJsonAsync<PlaybackResponse>($"/api/v1/videos/{upload.VideoId}/playback", JsonOptions);
        var videoDetail = await anonymous.GetFromJsonAsync<VideoResponse>($"/api/v1/videos/{upload.VideoId}", JsonOptions);

        // Assert
        Assert.Equal(HttpStatusCode.NotFound, privateResponse.StatusCode);
        Assert.Equal(HttpStatusCode.OK, submit.StatusCode);
        Assert.Equal(HttpStatusCode.OK, publish.StatusCode);
        Assert.Contains(home!.Items, x => x.VideoId == upload.VideoId);
        Assert.Contains(explore!.Items, x => x.VideoId == upload.VideoId);
        Assert.Contains(playback!.Renditions, x => x.Quality == "720p" && x.Url.StartsWith("https://storage.test/"));
        Assert.Contains(playback.Renditions, x => x.Quality == "480p" && x.Url.StartsWith("https://storage.test/"));
        Assert.Contains(playback.Renditions, x => x.Quality == "360p" && x.Url.StartsWith("https://storage.test/"));
        Assert.Equal(watermarkReadUrl, videoDetail!.ChannelWatermarkUrl);
        Assert.NotEmpty(factory.Storage.Objects);
    }

    [Fact]
    public async Task VideoInteractions_AreMutuallyExclusiveAndPersistWatchProgressRatingShare()
    {
        // Arrange
        var (owner, _, channelId) = await CreateUserAndChannelAsync("interact");
        var video = await CreatePublishedVideoAsync(owner, channelId, "Video tương tác");

        // Act
        var like = await owner.PutAsJsonAsync($"/api/v1/videos/{video.VideoId}/reaction", new { type = "like" });
        var dislike = await owner.PutAsJsonAsync($"/api/v1/videos/{video.VideoId}/reaction", new { type = "dislike" });
        var progress = await owner.PutAsJsonAsync($"/api/v1/videos/{video.VideoId}/watch-progress", new { watchedSeconds = 60, saveHistory = true });
        var rating = await owner.PutAsJsonAsync($"/api/v1/videos/{video.VideoId}/rating", new { score = 5 });
        var share = await owner.PostAsJsonAsync($"/api/v1/videos/{video.VideoId}/share", new { method = "copy_link" });
        var detail = await owner.GetFromJsonAsync<VideoResponse>($"/api/v1/videos/{video.VideoId}", JsonOptions);
        var removeReaction = await owner.DeleteAsync($"/api/v1/videos/{video.VideoId}/reaction");
        var removeRating = await owner.DeleteAsync($"/api/v1/videos/{video.VideoId}/rating");

        // Assert
        Assert.Equal(HttpStatusCode.OK, like.StatusCode);
        var reaction = await dislike.Content.ReadFromJsonAsync<ReactionResponse>(JsonOptions);
        Assert.Equal("dislike", reaction!.MyReaction); Assert.Equal(0, reaction.Likes); Assert.Equal(1, reaction.Dislikes);
        Assert.Equal(50m, (await progress.Content.ReadFromJsonAsync<WatchProgressResponse>(JsonOptions))!.Progress);
        Assert.Equal(5, (await rating.Content.ReadFromJsonAsync<RatingResponse>(JsonOptions))!.MyRating);
        Assert.Equal(1, (await share.Content.ReadFromJsonAsync<ShareResponse>(JsonOptions))!.ShareCount);
        Assert.Equal(60, detail!.ViewerState!.ResumeAtSeconds);
        Assert.Equal("dislike", detail.ViewerState.Reaction);
        Assert.Equal(5, detail.ViewerState.Rating);
        Assert.Null((await removeReaction.Content.ReadFromJsonAsync<ReactionResponse>(JsonOptions))!.MyReaction);
        Assert.Null((await removeRating.Content.ReadFromJsonAsync<RatingResponse>(JsonOptions))!.MyRating);
    }

    [Fact]
    public async Task VideoLikeCommentLikeAndReply_CreateRealtimeNotificationRows()
    {
        var (owner, ownerId, channelId) = await CreateUserAndChannelAsync("interaction_owner");
        var (viewer, _, _) = await CreateUserAndChannelAsync("interaction_viewer");
        var video = await CreatePublishedVideoAsync(owner, channelId, "Video realtime");

        var like = await viewer.PutAsJsonAsync($"/api/v1/videos/{video.VideoId}/reaction", new { type = "like" });
        var parentResponse = await owner.PostAsJsonAsync($"/api/v1/videos/{video.VideoId}/comments", new { content = "Bình luận gốc", parentCommentId = (Guid?)null });
        var parent = await parentResponse.Content.ReadFromJsonAsync<CommentResponse>(JsonOptions);
        var reply = await viewer.PostAsJsonAsync($"/api/v1/videos/{video.VideoId}/comments", new { content = "Câu trả lời", parentCommentId = parent!.CommentId });
        var commentLike = await viewer.PutAsJsonAsync($"/api/v1/comments/{parent.CommentId}/reaction", new { type = "like" });

        Assert.Equal(HttpStatusCode.OK, like.StatusCode);
        Assert.Equal(HttpStatusCode.Created, reply.StatusCode);
        Assert.Equal(HttpStatusCode.OK, commentLike.StatusCode);

        await using var db = factory.CreateDb();
        var notifications = await db.Notifications.AsNoTracking().Where(x => x.UserId == ownerId).ToListAsync();
        Assert.Contains(notifications, x => x.Type == "video_like" && x.ResourceId == video.VideoId);
        Assert.Contains(notifications, x => x.Type == "comment_reply" && x.ResourceId == parent.CommentId);
        Assert.Contains(notifications, x => x.Type == "comment_like" && x.ResourceId == parent.CommentId);
    }

    [Fact]
    public async Task Comments_ReplyReactionReportAndOwnerModeration_WorkEndToEnd()
    {
        // Arrange
        var (owner, ownerId, channelId) = await CreateUserAndChannelAsync("comment_owner");
        var (viewer, viewerId, _) = await CreateUserAndChannelAsync("comment_viewer");
        var video = await CreatePublishedVideoAsync(owner, channelId, "Video bình luận");
        Guid violationId;
        await using (var db = factory.CreateDb())
        {
            var violation = new ViolationType { ViolationTypeId = Guid.NewGuid(), Code = "spam", Name = "Spam", Status = "active", CreatedAt = DateTimeOffset.UtcNow, UpdatedAt = DateTimeOffset.UtcNow };
            db.ViolationTypes.Add(violation); await db.SaveChangesAsync(); violationId = violation.ViolationTypeId;
        }

        // Act
        var parentResponse = await owner.PostAsJsonAsync($"/api/v1/videos/{video.VideoId}/comments", new { content = "Bình luận gốc", parentCommentId = (Guid?)null });
        var parent = await parentResponse.Content.ReadFromJsonAsync<CommentResponse>(JsonOptions);
        var replyResponse = await viewer.PostAsJsonAsync($"/api/v1/videos/{video.VideoId}/comments", new { content = "Nội dung trả lời", parentCommentId = parent!.CommentId });
        var replies = await factory.CreateClient().GetFromJsonAsync<PageResult<CommentResponse>>($"/api/v1/comments/{parent.CommentId}/replies", JsonOptions);
        var reaction = await viewer.PutAsJsonAsync($"/api/v1/comments/{parent.CommentId}/reaction", new { type = "like" });
        var report = await viewer.PostAsJsonAsync($"/api/v1/comments/{parent.CommentId}/report", new { violationTypeId = violationId, description = "Nội dung spam" });
        var hide = await owner.PatchAsJsonAsync($"/api/v1/comments/{parent.CommentId}/visibility", new { hidden = true, reason = "Kiểm duyệt kênh" });
        var managed = await owner.GetFromJsonAsync<PageResult<CommentResponse>>($"/api/v1/channels/{channelId}/comments/manage?status=hidden", JsonOptions);
        var reply = await replyResponse.Content.ReadFromJsonAsync<CommentResponse>(JsonOptions);
        await using (var ordering = factory.CreateDb())
        {
            var oldest = await ordering.Comments.SingleAsync(x => x.CommentId == parent!.CommentId);
            var newest = await ordering.Comments.SingleAsync(x => x.CommentId == reply!.CommentId);
            oldest.CreatedAt = DateTimeOffset.UtcNow.AddMinutes(-2);
            newest.CreatedAt = DateTimeOffset.UtcNow.AddMinutes(-1);
            await ordering.SaveChangesAsync();
        }
        var newestComments = await owner.GetFromJsonAsync<PageResult<CommentResponse>>($"/api/v1/channels/{channelId}/comments/manage?sort=newest&page=1&pageSize=1", JsonOptions);
        var oldestComments = await owner.GetFromJsonAsync<PageResult<CommentResponse>>($"/api/v1/channels/{channelId}/comments/manage?sort=oldest&page=1&pageSize=1", JsonOptions);
        var mostLikedComments = await owner.GetFromJsonAsync<PageResult<CommentResponse>>($"/api/v1/channels/{channelId}/comments/manage?sort=mostLiked&page=1&pageSize=1", JsonOptions);
        var ownerDeletesViewerComment = await owner.DeleteAsync($"/api/v1/comments/{reply!.CommentId}");
        var violationTypes = await factory.CreateClient().GetFromJsonAsync<List<ViolationTypeResponse>>("/api/v1/violation-types", JsonOptions);

        // Assert
        Assert.Equal(HttpStatusCode.Created, parentResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Created, replyResponse.StatusCode);
        Assert.Contains(replies!.Items, x => x.ParentCommentId == parent.CommentId);
        Assert.Equal(1, (await reaction.Content.ReadFromJsonAsync<ReactionResponse>(JsonOptions))!.Likes);
        Assert.Equal(HttpStatusCode.Created, report.StatusCode);
        Assert.Equal("hidden", (await hide.Content.ReadFromJsonAsync<CommentResponse>(JsonOptions))!.Status);
        Assert.Contains(managed!.Items, x => x.CommentId == parent.CommentId && x.Status == "hidden" && x.VideoTitle == video.Title);
        Assert.Equal(reply.CommentId, Assert.Single(newestComments!.Items).CommentId);
        Assert.Equal(parent.CommentId, Assert.Single(oldestComments!.Items).CommentId);
        Assert.Equal(parent.CommentId, Assert.Single(mostLikedComments!.Items).CommentId);
        Assert.All(newestComments.Items.Concat(oldestComments.Items).Concat(mostLikedComments.Items), item => Assert.Equal(video.Title, item.VideoTitle));
        Assert.Equal(HttpStatusCode.NoContent, ownerDeletesViewerComment.StatusCode);
        Assert.Contains(violationTypes!, x => x.ViolationTypeId == violationId);
        await using var verify = factory.CreateDb();
        Assert.True(await verify.Notifications.AnyAsync(x => x.UserId == ownerId && x.Type == "comment_reply"));
        var storedReport = await verify.Reports.SingleAsync(x => x.UserId == viewerId && x.CommentId == parent.CommentId);
        Assert.NotNull(storedReport.ModerationCaseId);
        Assert.True(await verify.ModerationCases.AnyAsync(x => x.ModerationCaseId == storedReport.ModerationCaseId && x.CaseType == "report_case"));
    }

    [Fact]
    public async Task SettingsDownloadsAndCreatorManagement_PersistAndEnforceOwnership()
    {
        // Arrange
        var (owner, ownerId, channelId) = await CreateUserAndChannelAsync("manage_owner");
        var (other, _, _) = await CreateUserAndChannelAsync("manage_other");
        var video = await CreatePublishedVideoAsync(owner, channelId, "Video quản lý");
        var subscribe = await owner.PostAsJsonAsync("/api/v1/plans/00000000-0000-0000-0000-000000000101/subscribe", new { autoRenew = false });
        Assert.Equal(HttpStatusCode.PaymentRequired, subscribe.StatusCode);
        await using (var setup = factory.CreateDb())
        {
            var paidPlanId = Guid.Parse("00000000-0000-0000-0000-000000000101");
            (await setup.Users.SingleAsync(x => x.UserId == ownerId)).PlanId = paidPlanId;
            setup.PlanHistories.Add(new HuTube.Domain.Plans.PlanHistory { UserId = ownerId, OwnerUserId = ownerId, PlanId = paidPlanId, EndedAt = DateTimeOffset.UtcNow.AddDays(30), PaymentReference = "test-paid-fixture" });
            await setup.SaveChangesAsync();
        }

        // Act
        var settings = await owner.PutAsJsonAsync("/api/v1/account/settings", new { language = "en", theme = "dark", keepSubscriptionsPrivate = false });
        var options = await owner.GetFromJsonAsync<List<RenditionResponse>>($"/api/v1/videos/{video.VideoId}/download-options", JsonOptions);
        var createDownload = await owner.PostAsJsonAsync($"/api/v1/videos/{video.VideoId}/downloads", new { quality = "720p" });
        var deniedDownloadOptions = await other.GetAsync($"/api/v1/videos/{video.VideoId}/download-options");
        var download = await createDownload.Content.ReadFromJsonAsync<DownloadResponse>(JsonOptions);
        var downloads = await owner.GetFromJsonAsync<List<DownloadResponse>>("/api/v1/downloads", JsonOptions);
        var forbidden = await other.PatchAsJsonAsync($"/api/v1/videos/{video.VideoId}", new { title = "Không được sửa" });
        var manage = await owner.GetFromJsonAsync<PageResult<VideoResponse>>($"/api/v1/videos/manage?channelId={channelId}", JsonOptions);
        var cancelDownload = await owner.PostAsync($"/api/v1/downloads/{download!.VideoDownloadId}/cancel", null);
        var retryDownload = await owner.PostAsync($"/api/v1/downloads/{download.VideoDownloadId}/retry", null);
        using var deleteRequest = new HttpRequestMessage(HttpMethod.Delete, "/api/v1/downloads") { Content = JsonContent.Create(new { ids = new[] { download.VideoDownloadId } }) };
        var deleteDownload = await owner.SendAsync(deleteRequest);

        // Assert
        Assert.Equal(HttpStatusCode.OK, settings.StatusCode);
        await using var db = factory.CreateDb(); var persisted = await db.Users.AsNoTracking().SingleAsync(x => x.UserId == ownerId);
        Assert.Equal("en", persisted.PreferredLanguage); Assert.Equal("dark", persisted.Theme);
        Assert.Contains(options!, x => x.Quality == "720p");
        Assert.Equal(HttpStatusCode.Forbidden, deniedDownloadOptions.StatusCode);
        Assert.Equal(HttpStatusCode.Created, createDownload.StatusCode); Assert.Contains(downloads!, x => x.VideoDownloadId == download.VideoDownloadId);
        Assert.Equal("cancelled", (await cancelDownload.Content.ReadFromJsonAsync<DownloadResponse>(JsonOptions))!.Status);
        Assert.Equal("processing", (await retryDownload.Content.ReadFromJsonAsync<DownloadResponse>(JsonOptions))!.Status);
        Assert.Equal(HttpStatusCode.Forbidden, forbidden.StatusCode);
        Assert.Contains(manage!.Items, x => x.VideoId == video.VideoId);
        Assert.Equal(HttpStatusCode.NoContent, deleteDownload.StatusCode);
    }

    [Fact]
    public async Task UploadPreflightRetryAndCancel_EnforcePlanAndRetainMediaUntilPurge()
    {
        // Arrange
        var (owner, _, channelId) = await CreateUserAndChannelAsync("upload_state");

        // Act
        var allowed = await owner.PostAsJsonAsync("/api/v1/videos/upload-preflight", new { channelId, fileSize = 1024, duration = 60, contentType = "video/mp4", sourceQuality = "720p" });
        var denied = await owner.PostAsJsonAsync("/api/v1/videos/upload-preflight", new { channelId, fileSize = 1024, duration = 60, contentType = "video/mp4", sourceQuality = "1080p" });
        var video = await UploadAsync(owner, channelId, "Video retry");
        string storedPath;
        await using (var db = factory.CreateDb())
        {
            storedPath = await db.Videos.Where(x => x.VideoId == video.VideoId).Select(x => x.VideoUrl).SingleAsync();
            await db.Videos.Where(x => x.VideoId == video.VideoId).ExecuteUpdateAsync(x => x.SetProperty(v => v.Status, "failed"));
            await db.VideoRenditions.Where(x => x.VideoId == video.VideoId).ExecuteUpdateAsync(x => x.SetProperty(v => v.Status, "failed"));
        }
        var retry = await owner.PostAsync($"/api/v1/videos/{video.VideoId}/retry-processing", null);
        var cancel = await owner.PostAsync($"/api/v1/videos/{video.VideoId}/cancel-upload", null);

        // Assert
        Assert.Equal(HttpStatusCode.OK, allowed.StatusCode); Assert.True((await allowed.Content.ReadFromJsonAsync<UploadPreflightResponse>(JsonOptions))!.Allowed);
        Assert.Equal(HttpStatusCode.Forbidden, denied.StatusCode);
        Assert.Equal("processing", (await retry.Content.ReadFromJsonAsync<VideoResponse>(JsonOptions))!.Status);
        Assert.Equal(HttpStatusCode.NoContent, cancel.StatusCode); Assert.True(factory.Storage.Objects.ContainsKey(storedPath));
        await using var verify = factory.CreateDb();
        var cancelled = await verify.Videos.SingleAsync(x => x.VideoId == video.VideoId);
        Assert.Equal("deleted", cancelled.Status);
        Assert.NotNull(cancelled.MediaRetentionUntil);
    }

    [Fact]
    public async Task CategoriesCreatorEditFilterAndSoftDelete_WorkEndToEnd()
    {
        // Arrange
        var (owner, _, channelId) = await CreateUserAndChannelAsync("metadata");
        var suffix = Guid.NewGuid().ToString("N")[..8];
        var category = new Category { CategoryId = Guid.NewGuid(), Name = $"Giáo dục {suffix}", Slug = $"giao-duc-{suffix}", Status = "active", CreatedAt = DateTimeOffset.UtcNow, UpdatedAt = DateTimeOffset.UtcNow };
        await using (var db = factory.CreateDb()) { db.Categories.Add(category); await db.SaveChangesAsync(); }
        var video = await UploadAsync(owner, channelId, "Tiêu đề cũ");

        // Act
        var categories = await factory.CreateClient().GetFromJsonAsync<List<CategoryResponse>>("/api/v1/categories", JsonOptions);
        var update = await owner.PatchAsJsonAsync($"/api/v1/videos/{video.VideoId}", new
        {
            title = "Tiêu đề mới", categoryId = category.CategoryId, visibility = "unlisted",
            tags = new[] { "dotnet", "api" }, chapters = new[] { new { startSeconds = 0, title = "Bắt đầu" } }
        });
        var updated = await update.Content.ReadFromJsonAsync<VideoResponse>(JsonOptions);
        var managed = await owner.GetFromJsonAsync<PageResult<VideoResponse>>($"/api/v1/videos/manage?channelId={channelId}&visibility=unlisted", JsonOptions);
        var delete = await owner.DeleteAsync($"/api/v1/videos/{video.VideoId}");
        var missing = await owner.GetAsync($"/api/v1/videos/{video.VideoId}");

        // Assert
        Assert.Contains(categories!, x => x.CategoryId == category.CategoryId);
        Assert.Equal(HttpStatusCode.OK, update.StatusCode); Assert.Equal("Tiêu đề mới", updated!.Title);
        Assert.Equal(category.CategoryId, updated.CategoryId); Assert.Equal(new[] { "api", "dotnet" }, updated.Tags);
        Assert.Contains(managed!.Items, x => x.VideoId == video.VideoId);
        Assert.Equal(HttpStatusCode.NoContent, delete.StatusCode); Assert.Equal(HttpStatusCode.NotFound, missing.StatusCode);
    }

    [Fact]
    public async Task CommentCrudSortAndGuestAuthorization_WorkEndToEnd()
    {
        // Arrange
        var (owner, _, channelId) = await CreateUserAndChannelAsync("comment_crud");
        var video = await CreatePublishedVideoAsync(owner, channelId, "Video CRUD comment");
        var create = await owner.PostAsJsonAsync($"/api/v1/videos/{video.VideoId}/comments", new { content = "Nội dung ban đầu", parentCommentId = (Guid?)null });
        var comment = await create.Content.ReadFromJsonAsync<CommentResponse>(JsonOptions);

        // Act
        var update = await owner.PatchAsJsonAsync($"/api/v1/comments/{comment!.CommentId}", new { content = "Nội dung đã sửa" });
        await owner.PutAsJsonAsync($"/api/v1/comments/{comment.CommentId}/reaction", new { type = "like" });
        var top = await factory.CreateClient().GetFromJsonAsync<PageResult<CommentResponse>>($"/api/v1/videos/{video.VideoId}/comments?sort=top", JsonOptions);
        var removeReaction = await owner.DeleteAsync($"/api/v1/comments/{comment.CommentId}/reaction");
        var delete = await owner.DeleteAsync($"/api/v1/comments/{comment.CommentId}");
        var guest = factory.CreateClient();
        var guestComment = await guest.PostAsJsonAsync($"/api/v1/videos/{video.VideoId}/comments", new { content = "Không đăng nhập", parentCommentId = (Guid?)null });
        var guestReaction = await guest.PutAsJsonAsync($"/api/v1/videos/{video.VideoId}/reaction", new { type = "like" });

        // Assert
        Assert.Equal("Nội dung đã sửa", (await update.Content.ReadFromJsonAsync<CommentResponse>(JsonOptions))!.Content);
        Assert.Contains(top!.Items, x => x.CommentId == comment.CommentId && x.Likes == 1);
        Assert.Equal(HttpStatusCode.OK, removeReaction.StatusCode); Assert.Equal(HttpStatusCode.NoContent, delete.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, guestComment.StatusCode); Assert.Equal(HttpStatusCode.Unauthorized, guestReaction.StatusCode);
    }

    [Fact]
    public async Task PrivatePlaylistItems_AreTombstonesForOtherViewers()
    {
        var (owner, _, channelId) = await CreateUserAndChannelAsync("playlist_security");
        var video = await CreatePublishedVideoAsync(owner, channelId, "Confidential title");
        var created = await owner.PostAsJsonAsync("/api/v1/playlists", new CreatePlaylistRequest("Public collection", Visibility: "public"));
        created.EnsureSuccessStatusCode();
        var playlist = (await created.Content.ReadFromJsonAsync<PlaylistResponse>(JsonOptions))!;
        (await owner.PostAsJsonAsync($"/api/v1/playlists/{playlist.PlaylistId}/videos", new AddPlaylistVideoRequest(video.VideoId))).EnsureSuccessStatusCode();
        (await owner.PatchAsJsonAsync($"/api/v1/videos/{video.VideoId}", new { visibility = "private" })).EnsureSuccessStatusCode();
        var publicView = (await factory.CreateClient().GetFromJsonAsync<PlaylistResponse>($"/api/v1/playlists/{playlist.PlaylistId}", JsonOptions))!;
        var item = Assert.Single(publicView.Items);
        Assert.False(item.Available); Assert.Null(item.Title); Assert.Null(item.ThumbnailUrl);
        Assert.Null(item.Visibility); Assert.Null(item.Status); Assert.Null(item.ModerationStatus); Assert.Equal(0, item.Duration);
        var ownerView = (await owner.GetFromJsonAsync<PlaylistResponse>($"/api/v1/playlists/{playlist.PlaylistId}", JsonOptions))!;
        Assert.Equal(video.Title, Assert.Single(ownerView.Items).Title);
    }

    [Fact]
    public async Task MetadataDoesNotIssueSourceUrls_AndSuspendedChannelsCannotPlay()
    {
        var (owner, _, channelId) = await CreateUserAndChannelAsync("media_security");
        var video = await CreatePublishedVideoAsync(owner, channelId, "Access policy video");
        var anonymous = factory.CreateClient();
        var detail = (await anonymous.GetFromJsonAsync<VideoResponse>($"/api/v1/videos/{video.VideoId}", JsonOptions))!;
        Assert.Equal("", detail.VideoUrl);
        Assert.NotEmpty((await anonymous.GetFromJsonAsync<PlaybackResponse>($"/api/v1/videos/{video.VideoId}/playback", JsonOptions))!.Renditions);
        await using (var db = factory.CreateDb())
            await db.Channels.Where(x => x.ChannelId == channelId).ExecuteUpdateAsync(update => update.SetProperty(x => x.Status, "suspended"));
        Assert.False((await anonymous.GetAsync($"/api/v1/videos/{video.VideoId}")).IsSuccessStatusCode);
        Assert.False((await anonymous.GetAsync($"/api/v1/videos/{video.VideoId}/playback")).IsSuccessStatusCode);
        var search = (await anonymous.GetFromJsonAsync<PageResult<VideoCardResponse>>($"/api/v1/videos/search?channelId={channelId}", JsonOptions))!;
        Assert.DoesNotContain(search.Items, item => item.VideoId == video.VideoId);
    }

    [Fact]
    public async Task ProfileBioPersists_AndModeratorRestrictionsSurviveCreatorEdits()
    {
        var (owner, _, channelId) = await CreateUserAndChannelAsync("moderation_security");
        (await owner.PatchAsJsonAsync("/api/v1/account/profile", new { bio = "Persistent biography" })).EnsureSuccessStatusCode();
        var profile = (await owner.GetFromJsonAsync<UserProfileDto>("/api/v1/account/profile", JsonOptions))!;
        Assert.Equal("Persistent biography", profile.Bio);
        var video = await CreatePublishedVideoAsync(owner, channelId, "Restricted video");
        await using (var db = factory.CreateDb())
        {
            var stored = await db.Videos.SingleAsync(x => x.VideoId == video.VideoId);
            stored.ModerationAgeRestricted = true; stored.AgeRestricted = true;
            stored.RecommendationRestricted = true;
            stored.Metadata = "{\"chapters\":[],\"recommendation_restricted\":true}";
            await db.SaveChangesAsync();
        }
        (await owner.PatchAsJsonAsync($"/api/v1/videos/{video.VideoId}", new { ageRestricted = false, chapters = new[] { new { startSeconds = 0, title = "Intro" } } })).EnsureSuccessStatusCode();
        await using var verify = factory.CreateDb();
        var persisted = await verify.Videos.AsNoTracking().SingleAsync(x => x.VideoId == video.VideoId);
        Assert.True(persisted.AgeRestricted); Assert.True(persisted.RecommendationRestricted);
        using var metadata = JsonDocument.Parse(persisted.Metadata);
        Assert.True(metadata.RootElement.GetProperty("recommendation_restricted").GetBoolean());
        var search = (await factory.CreateClient().GetFromJsonAsync<PageResult<VideoCardResponse>>($"/api/v1/videos/search?channelId={channelId}", JsonOptions))!;
        Assert.DoesNotContain(search.Items, item => item.VideoId == video.VideoId);
        await verify.Videos.Where(x => x.VideoId == video.VideoId).ExecuteUpdateAsync(update => update.SetProperty(x => x.ModerationHidden, true).SetProperty(x => x.Visibility, "private"));
        Assert.Equal(HttpStatusCode.Forbidden, (await owner.PatchAsJsonAsync($"/api/v1/videos/{video.VideoId}", new { visibility = "public" })).StatusCode);
    }

    [Fact]
    public async Task DisabledComments_RejectNewComments()
    {
        var (owner, _, channelId) = await CreateUserAndChannelAsync("comments_disabled");
        var video = await CreatePublishedVideoAsync(owner, channelId, "No comments");
        await using (var db = factory.CreateDb())
            await db.Videos.Where(x => x.VideoId == video.VideoId).ExecuteUpdateAsync(update => update.SetProperty(x => x.AllowComments, false));
        var response = await owner.PostAsJsonAsync($"/api/v1/videos/{video.VideoId}/comments", new { content = "Should be refused" });
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    private static SepayOptions PaymentOptions() => new() { SecretKey = "local-test", AccountNumber = "local-test-account", BankCode = "test-bank" };

    [Fact]
    public async Task PaymentIdempotency_IsScopedToUserAndSurvivesCompletionAndConcurrency()
    {
        var (_, firstUser, _) = await CreateUserAndChannelAsync("payment_a");
        var (_, secondUser, _) = await CreateUserAndChannelAsync("payment_b");
        var planId = Guid.Parse("00000000-0000-0000-0000-000000000101");
        async Task<CreatePaymentResponse> Create(Guid userId, bool autoRenew = false)
        {
            await using var scope = factory.Services.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<HuTubeDbContext>();
            var service = new PaymentService(db, scope.ServiceProvider.GetRequiredService<IPlanService>(), PaymentOptions(), TimeProvider.System);
            return await service.InitiateAsync(userId, new CreatePaymentRequest(planId, autoRenew, "shared-key"));
        }
        var simultaneous = await Task.WhenAll(Create(firstUser), Create(firstUser));
        Assert.Equal(simultaneous[0].PaymentId, simultaneous[1].PaymentId);
        Assert.NotEqual(simultaneous[0].PaymentId, (await Create(secondUser)).PaymentId);
        await using (var db = factory.CreateDb())
            await db.Payments.Where(x => x.PaymentId == simultaneous[0].PaymentId).ExecuteUpdateAsync(x => x.SetProperty(p => p.Status, "cancelled"));
        Assert.Equal(simultaneous[0].PaymentId, (await Create(firstUser)).PaymentId);
        var conflict = await Assert.ThrowsAsync<PaymentException>(() => Create(firstUser, true));
        Assert.Equal(409, conflict.Status);
        await using var verify = factory.CreateDb();
        Assert.Equal(1, await verify.Payments.CountAsync(x => x.UserId == firstUser && x.IdempotencyKey == "shared-key"));
    }

    [Fact]
    public async Task PaymentFinalSaveFailure_RollsBackActivatedPlanAndHistory()
    {
        var (_, userId, _) = await CreateUserAndChannelAsync("payment_atomic");
        await using var scope = factory.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<HuTubeDbContext>();
        var service = new PaymentService(db, scope.ServiceProvider.GetRequiredService<IPlanService>(), PaymentOptions(), TimeProvider.System);
        var planId = Guid.Parse("00000000-0000-0000-0000-000000000101");
        var payment = await service.InitiateAsync(userId, new CreatePaymentRequest(planId));
        var previousPlan = await db.Users.Where(x => x.UserId == userId).Select(x => x.PlanId).SingleAsync();
        await db.Database.ExecuteSqlRawAsync("CREATE FUNCTION bugfix_reject_paid() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.status = 'paid' THEN RAISE EXCEPTION 'injected final-save failure'; END IF; RETURN NEW; END $$; CREATE TRIGGER bugfix_reject_paid BEFORE UPDATE ON payments FOR EACH ROW EXECUTE FUNCTION bugfix_reject_paid();");
        try
        {
            var payload = new SepayWebhookPayload(987654321, "test-bank", "2026-10-02", "local-test-account", null,
                payment.TransactionCode, payment.TransactionCode, "in", 99000, 99000, "local-test-reference");
            await Assert.ThrowsAsync<DbUpdateException>(() => service.HandleSepayWebhookAsync(payload));
            await using var verify = factory.CreateDb();
            Assert.Equal(previousPlan, await verify.Users.Where(x => x.UserId == userId).Select(x => x.PlanId).SingleAsync());
            Assert.Equal("pending", await verify.Payments.Where(x => x.PaymentId == payment.PaymentId).Select(x => x.Status).SingleAsync());
            Assert.False(await verify.PlanHistories.AnyAsync(x => x.UserId == userId && x.PlanId == planId));
        }
        finally { await db.Database.ExecuteSqlRawAsync("DROP TRIGGER bugfix_reject_paid ON payments; DROP FUNCTION bugfix_reject_paid();"); }
    }

    [Fact]
    public async Task DeletedVideoPurge_PreservesDatabaseConstraintsAndReleasesQuotaOnce()
    {
        var (owner, _, channelId) = await CreateUserAndChannelAsync("purge_regression");
        var video = await CreatePublishedVideoAsync(owner, channelId, "Purge regression");
        (await owner.DeleteAsync($"/api/v1/videos/{video.VideoId}")).EnsureSuccessStatusCode();
        long storageBefore;
        await using (var db = factory.CreateDb())
        {
            storageBefore = await db.ChannelQuotas.Where(x => x.ChannelId == channelId).Select(x => x.StorageUsed).SingleAsync();
            await db.Videos.Where(x => x.VideoId == video.VideoId).ExecuteUpdateAsync(x => x.SetProperty(v => v.MediaRetentionUntil, DateTimeOffset.UtcNow.AddMinutes(-1)));
        }
        async Task Clean()
        {
            using var worker = new VideoMediaRetentionCleanupService(factory.Services.GetRequiredService<IServiceScopeFactory>(), TimeProvider.System,
                factory.Services.GetRequiredService<Microsoft.Extensions.Logging.ILogger<VideoMediaRetentionCleanupService>>());
            await worker.StartAsync(CancellationToken.None);
            for (var i = 0; i < 100; i++)
            {
                await using var check = factory.CreateDb();
                if (await check.Videos.AnyAsync(x => x.VideoId == video.VideoId && x.MediaPurgedAt != null)) break;
                await Task.Delay(50);
            }
            await worker.StopAsync(CancellationToken.None);
        }
        await Clean();
        await Clean();
        await using var verify = factory.CreateDb();
        var persisted = await verify.Videos.SingleAsync(x => x.VideoId == video.VideoId);
        Assert.NotNull(persisted.MediaPurgedAt);
        Assert.NotEmpty(persisted.VideoUrl);
        Assert.Equal(Math.Max(0, storageBefore - video.FileSize), await verify.ChannelQuotas.Where(x => x.ChannelId == channelId).Select(x => x.StorageUsed).SingleAsync());
        Assert.All(await verify.VideoRenditions.Where(x => x.VideoId == video.VideoId).ToListAsync(), x => Assert.Equal("deleted", x.Status));
    }

    [Fact]
    public async Task ConcurrentUploads_ReserveQuotaUsingFreshValues_AndCleanRejectedObjects()
    {
        var (owner, _, channelId) = await CreateUserAndChannelAsync("quota_race");
        var bytes = Encoding.UTF8.GetBytes("fake-video-content");
        await using (var db = factory.CreateDb())
            await db.ChannelQuotas.Where(x => x.ChannelId == channelId).ExecuteUpdateAsync(x => x.SetProperty(q => q.StorageLimit, bytes.Length + 1L));
        var entered = 0;
        var barrier = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var storageBefore = factory.Storage.Objects.Keys.ToHashSet();
        factory.Storage.BeforeSave = async (folder, fileName) => {
            if (folder != "videos" || !fileName.StartsWith("quota-")) return;
            if (Interlocked.Increment(ref entered) == 2) barrier.TrySetResult();
            await barrier.Task.WaitAsync(TimeSpan.FromSeconds(15));
        };
        async Task<HttpResponseMessage> Upload(string name)
        {
            using var form = new MultipartFormDataContent();
            form.Add(new StringContent(channelId.ToString()), "ChannelId");
            form.Add(new StringContent(name), "Title");
            form.Add(new StringContent("120"), "Duration");
            form.Add(new StringContent("720p"), "SourceQuality");
            var content = new ByteArrayContent(bytes); content.Headers.ContentType = new MediaTypeHeaderValue("video/mp4");
            form.Add(content, "Video", name + ".mp4");
            return await owner.PostAsync("/api/v1/videos", form);
        }
        try
        {
            var responses = await Task.WhenAll(Upload("quota-first"), Upload("quota-second"));
            Assert.Single(responses, x => x.IsSuccessStatusCode);
            Assert.Single(responses, x => x.StatusCode == HttpStatusCode.Conflict);
            await using var verify = factory.CreateDb();
            Assert.Equal(bytes.Length, await verify.ChannelQuotas.Where(x => x.ChannelId == channelId).Select(x => x.StorageUsed).SingleAsync());
            Assert.Equal(1, await verify.Videos.CountAsync(x => x.ChannelId == channelId));
            Assert.Single(factory.Storage.Objects.Keys, x => !storageBefore.Contains(x) && x.StartsWith("test://videos/"));
            foreach (var response in responses) response.Dispose();
        }
        finally { factory.Storage.BeforeSave = null; }
    }

    [Fact]
    public async Task UploadProbeOverridesClientClaims_AndRevalidatesActualDuration()
    {
        var (owner, _, channelId) = await CreateUserAndChannelAsync("media_probe");
        async Task<HttpResponseMessage> Upload(int actualDuration)
        {
            using var form = new MultipartFormDataContent();
            form.Add(new StringContent(channelId.ToString()), "ChannelId");
            form.Add(new StringContent("Probed metadata"), "Title");
            form.Add(new StringContent("1"), "Duration");
            form.Add(new StringContent("360p"), "SourceQuality");
            var bytes = new ByteArrayContent(Encoding.UTF8.GetBytes($"fake-video-duration:{actualDuration}"));
            bytes.Headers.ContentType = new MediaTypeHeaderValue("video/mp4");
            form.Add(bytes, "Video", "probe.mp4");
            return await owner.PostAsync("/api/v1/videos", form);
        }
        var response = await Upload(120); response.EnsureSuccessStatusCode();
        var video = (await response.Content.ReadFromJsonAsync<VideoResponse>(JsonOptions))!;
        Assert.Equal(120, video.Duration);
        await using var verify = factory.CreateDb();
        Assert.Equal(720, await verify.VideoRenditions.Where(x => x.VideoId == video.VideoId).OrderByDescending(x => x.Height).Select(x => x.Height).FirstAsync());
        var denied = await Upload(int.MaxValue);
        Assert.Equal(HttpStatusCode.BadRequest, denied.StatusCode);
        Assert.Contains("VIDEO_TOO_LONG", await denied.Content.ReadAsStringAsync());
    }

    private async Task<(HttpClient Client, Guid UserId, Guid ChannelId)> CreateUserAndChannelAsync(string prefix)
    {
        var client = factory.CreateClient(); client.DefaultRequestHeaders.Add("X-HuTube-Client", "web");
        var suffix = Guid.NewGuid().ToString("N"); var email = $"{prefix}_{suffix}@example.com"; var username = $"{prefix}_{suffix}"[..Math.Min(40, prefix.Length + 1 + suffix.Length)];
        (await client.PostAsJsonAsync("/api/v1/auth/register", new RegisterRequest(username, email, "Test User", "Password123!"))).EnsureSuccessStatusCode();
        (await client.PostAsJsonAsync("/api/v1/auth/verify-email", new TokenRequest(factory.Emails.Token(email)))).EnsureSuccessStatusCode();
        var login = await client.PostAsJsonAsync("/api/v1/auth/login", new LoginRequest(email, "Password123!", "web", "Test")); login.EnsureSuccessStatusCode();
        var auth = await login.Content.ReadFromJsonAsync<LoginResponse>(JsonOptions); client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", auth!.AccessToken);
        Guid userId; await using (var db = factory.CreateDb()) userId = await db.Users.Where(x => x.Email == email).Select(x => x.UserId).SingleAsync();
        var channelResponse = await client.PostAsJsonAsync("/api/v1/channels", new CreateChannelRequest($"Kênh {prefix}", $"{prefix}-{suffix}"[..Math.Min(48, prefix.Length + 1 + suffix.Length)], "Kênh kiểm thử"));
        channelResponse.EnsureSuccessStatusCode(); var channel = await channelResponse.Content.ReadFromJsonAsync<ChannelResponse>(JsonOptions);
        return (client, userId, channel!.ChannelId);
    }

    private async Task<VideoResponse> UploadAsync(HttpClient client, Guid channelId, string title)
    {
        using var form = new MultipartFormDataContent();
        form.Add(new StringContent(channelId.ToString()), "ChannelId"); form.Add(new StringContent(title), "Title");
        form.Add(new StringContent("Mô tả video"), "Description"); form.Add(new StringContent("public"), "Visibility");
        form.Add(new StringContent("120"), "Duration"); form.Add(new StringContent("hu-tube"), "Tags");
        form.Add(new StringContent("[{\"startSeconds\":0,\"title\":\"Mở đầu\"},{\"startSeconds\":60,\"title\":\"Phần hai\"}]", Encoding.UTF8), "ChaptersJson");
        var bytes = new ByteArrayContent(Encoding.UTF8.GetBytes("fake-video-content")); bytes.Headers.ContentType = new MediaTypeHeaderValue("video/mp4"); form.Add(bytes, "Video", "sample.mp4");
        var response = await client.PostAsync("/api/v1/videos", form); response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<VideoResponse>(JsonOptions))!;
    }

    private async Task<VideoResponse> CreatePublishedVideoAsync(HttpClient client, Guid channelId, string title)
    {
        var video = await UploadAsync(client, channelId, title); await client.PostAsync($"/api/v1/videos/{video.VideoId}/submit-moderation", null);
        await ApproveAsync(video.VideoId); var response = await client.PostAsync($"/api/v1/videos/{video.VideoId}/publish", null); response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<VideoResponse>(JsonOptions))!;
    }

    private async Task ApproveAsync(Guid videoId)
    {
        await using var db = factory.CreateDb();
        await db.Videos.Where(x => x.VideoId == videoId).ExecuteUpdateAsync(x => x.SetProperty(v => v.ModerationStatus, "approved"));
        await db.ModerationCases.Where(x => x.VideoId == videoId).ExecuteUpdateAsync(x => x.SetProperty(v => v.Status, "approved").SetProperty(v => v.ResolvedAt, DateTimeOffset.UtcNow));
    }
}
