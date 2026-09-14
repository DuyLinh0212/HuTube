using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
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

        // Assert
        Assert.Equal(HttpStatusCode.NotFound, privateResponse.StatusCode);
        Assert.Equal(HttpStatusCode.OK, submit.StatusCode);
        Assert.Equal(HttpStatusCode.OK, publish.StatusCode);
        Assert.Contains(home!.Items, x => x.VideoId == upload.VideoId);
        Assert.Contains(explore!.Items, x => x.VideoId == upload.VideoId);
        Assert.Contains(playback!.Renditions, x => x.Quality == "720p" && x.Url.StartsWith("https://storage.test/"));
        Assert.Contains(playback.Renditions, x => x.Quality == "480p" && x.Url.StartsWith("https://storage.test/"));
        Assert.Contains(playback.Renditions, x => x.Quality == "360p" && x.Url.StartsWith("https://storage.test/"));
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
        var ownerDeletesViewerComment = await owner.DeleteAsync($"/api/v1/comments/{reply!.CommentId}");
        var violationTypes = await factory.CreateClient().GetFromJsonAsync<List<ViolationTypeResponse>>("/api/v1/violation-types", JsonOptions);

        // Assert
        Assert.Equal(HttpStatusCode.Created, parentResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Created, replyResponse.StatusCode);
        Assert.Contains(replies!.Items, x => x.ParentCommentId == parent.CommentId);
        Assert.Equal(1, (await reaction.Content.ReadFromJsonAsync<ReactionResponse>(JsonOptions))!.Likes);
        Assert.Equal(HttpStatusCode.Created, report.StatusCode);
        Assert.Equal("hidden", (await hide.Content.ReadFromJsonAsync<CommentResponse>(JsonOptions))!.Status);
        Assert.Contains(managed!.Items, x => x.CommentId == parent.CommentId && x.Status == "hidden");
        Assert.Equal(HttpStatusCode.NoContent, ownerDeletesViewerComment.StatusCode);
        Assert.Contains(violationTypes!, x => x.ViolationTypeId == violationId);
        await using var verify = factory.CreateDb();
        Assert.True(await verify.Notifications.AnyAsync(x => x.UserId == ownerId && x.Type == "comment_reply"));
        Assert.True(await verify.Reports.AnyAsync(x => x.UserId == viewerId && x.CommentId == parent.CommentId));
    }

    [Fact]
    public async Task SettingsDownloadsAndCreatorManagement_PersistAndEnforceOwnership()
    {
        // Arrange
        var (owner, ownerId, channelId) = await CreateUserAndChannelAsync("manage_owner");
        var (other, _, _) = await CreateUserAndChannelAsync("manage_other");
        var video = await CreatePublishedVideoAsync(owner, channelId, "Video quản lý");
        var subscribe = await owner.PostAsJsonAsync("/api/v1/plans/00000000-0000-0000-0000-000000000101/subscribe", new { autoRenew = false });
        subscribe.EnsureSuccessStatusCode();

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
    public async Task UploadPreflightRetryAndCancel_EnforcePlanAndCleanStoredObject()
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
        Assert.Equal(HttpStatusCode.NoContent, cancel.StatusCode); Assert.False(factory.Storage.Objects.ContainsKey(storedPath));
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
