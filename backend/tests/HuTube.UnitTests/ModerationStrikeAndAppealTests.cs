using HuTube.Application.Auth;
using HuTube.Application.Notifications;
using HuTube.Application.Rbac;
using HuTube.Application.Storage;
using HuTube.Application.Videos;
using HuTube.Domain.Channels;
using HuTube.Domain.Rbac;
using HuTube.Domain.Users;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using HuTube.Infrastructure.Videos;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace HuTube.UnitTests;

public sealed class ModerationStrikeAndAppealTests : IDisposable
{
    private readonly HuTubeDbContext _db;
    private readonly StrikeService _strikeService;
    private readonly ModerationService _moderationService;
    private readonly ReportService _reportService;
    private readonly AppealService _appealService;
    private readonly FakeNotificationService _notifications = new();

    private sealed class FakeObjectStorage : IObjectStorage
    {
        public Task<string> SaveFileAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct = default) => Task.FromResult("https://storage.fake/" + fileName);
        public Task<string> SaveVideoAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct = default) => Task.FromResult("https://storage.fake/" + fileName);
        public Task<string> GetReadUrlAsync(string storedPath, TimeSpan lifetime, CancellationToken ct = default) => Task.FromResult("https://storage.fake/" + storedPath);
        public Task DeleteFileAsync(string relativePath, CancellationToken ct = default) => Task.CompletedTask;
    }

    private sealed class FakeNotificationService : INotificationService
    {
        public List<(Guid RecipientId, string Type, string Title, string Content)> Notifications { get; } = [];

        public Task PublishAsync(Guid recipientId, string type, string title, string content, string? actionUrl = null, string? resourceType = null, Guid? resourceId = null, CancellationToken ct = default)
        {
            Notifications.Add((recipientId, type, title, content));
            return Task.CompletedTask;
        }

        public Task PublishInAppAsync(Guid recipientId, string type, string title, string content, string? actionUrl = null, string? resourceType = null, Guid? resourceId = null, CancellationToken ct = default)
        {
            Notifications.Add((recipientId, type, title, content));
            return Task.CompletedTask;
        }

        public Task<NotificationPage> GetAsync(Guid userId, int page = 1, int pageSize = 5, CancellationToken ct = default) =>
            Task.FromResult(new NotificationPage([], page, pageSize, 0, 0, false));

        public Task MarkReadAsync(Guid userId, Guid notificationId, CancellationToken ct = default) => Task.CompletedTask;
        public Task MarkAllReadAsync(Guid userId, CancellationToken ct = default) => Task.CompletedTask;
        public Task PublishInvitationAsync(Guid userId, InvitationSignal invitation, CancellationToken ct = default) => Task.CompletedTask;
    }

    public ModerationStrikeAndAppealTests()
    {
        var options = new DbContextOptionsBuilder<HuTubeDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;
        _db = new HuTubeDbContext(options);

        var rbacStore = new RbacStore(_db);
        var authStore = new AuthStore(_db);
        var rbacService = new RbacService(rbacStore, authStore);

        _strikeService = new StrikeService(_db, rbacService, _notifications);
        _reportService = new ReportService(_db, rbacService, _notifications, _strikeService);
        _appealService = new AppealService(_db, rbacService, _notifications);
        _moderationService = new ModerationService(_db, rbacService, _notifications, new FakeObjectStorage());
    }

    public void Dispose()
    {
        _db.Dispose();
    }

    [Fact]
    public async Task AutoLockRule_FifthVideoRejection_LocksChannelAndCreatesStrike()
    {
        // Arrange
        var ownerId = Guid.NewGuid();
        var reviewerId = Guid.NewGuid();
        var channel = new Channel
        {
            ChannelId = Guid.NewGuid(),
            OwnerUserId = ownerId,
            Name = "Test Channel",
            Handle = "testchannel",
            Status = "active",
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        _db.Channels.Add(channel);

        // Add 4 existing rejected videos
        for (int i = 1; i <= 4; i++)
        {
            _db.Videos.Add(new Video
            {
                VideoId = Guid.NewGuid(),
                ChannelId = channel.ChannelId,
                Title = $"Rejected Video {i}",
                Description = "Desc",
                Status = "published",
                ModerationStatus = "rejected",
                CreatedAt = DateTimeOffset.UtcNow,
                UpdatedAt = DateTimeOffset.UtcNow
            });
        }

        // Add 5th video currently pending review
        var fifthVideo = new Video
        {
            VideoId = Guid.NewGuid(),
            ChannelId = channel.ChannelId,
            Title = "Fifth Video",
            Description = "Desc",
            Status = "published",
            ModerationStatus = "pending",
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        _db.Videos.Add(fifthVideo);

        var mc = new ModerationCase
        {
            ModerationCaseId = Guid.NewGuid(),
            VideoId = fifthVideo.VideoId,
            CaseType = "video_upload",
            Status = "in_review",
            ReviewerId = reviewerId,
            SubmittedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        _db.ModerationCases.Add(mc);
        await _db.SaveChangesAsync();

        // Act - Reviewer rejects the 5th video
        var resolution = await _moderationService.ResolveCaseAsync(reviewerId, mc.ModerationCaseId, new ResolveModerationRequest(
            "reject",
            "Vi phạm bản quyền nghiêm trọng",
            "Auto lock check",
            "COPYRIGHT"
        ));

        // Assert
        Assert.Equal("rejected", resolution.Status);
        Assert.Equal("reject", resolution.Decision);

        var updatedChannel = await _db.Channels.SingleAsync(c => c.ChannelId == channel.ChannelId);
        Assert.Equal("suspended", updatedChannel.Status);

        var strike = await _db.ChannelStrikes.FirstOrDefaultAsync(s => s.ChannelId == channel.ChannelId);
        Assert.NotNull(strike);
        Assert.Equal(StrikeSeverities.High, strike.Severity);
        Assert.Contains("5 nội dung vi phạm bị từ chối", strike.Reason);

        Assert.Contains(_notifications.Notifications, n => n.Type == "channel_suspended" && n.RecipientId == ownerId);
    }

    [Fact]
    public async Task StrikeTier_Progression_And_Revocation_RestoresActiveStatus()
    {
        // Arrange
        var ownerId = Guid.NewGuid();
        var adminId = Guid.NewGuid();
        var channel = new Channel
        {
            ChannelId = Guid.NewGuid(),
            OwnerUserId = ownerId,
            Name = "Strike Channel",
            Handle = "strikechannel",
            Status = "active",
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        _db.Channels.Add(channel);
        await _db.SaveChangesAsync();

        // Strike 1
        var strike1 = await _strikeService.CreateManualStrikeAsync(adminId, new CreateStrikeRequest(
            channel.ChannelId,
            "SPAM",
            StrikeSeverities.High,
            "Spam nội dung",
            null
        ));
        Assert.Equal(1, strike1.StrikeNumber);
        var status1 = await _strikeService.GetChannelStrikeStatusAsync(channel.ChannelId);
        Assert.Equal(1, status1.ActiveStrikesCount);
        Assert.False(status1.IsSuspended);
        Assert.NotNull(status1.UploadRestrictedUntil);

        // Strike 2
        var strike2 = await _strikeService.CreateManualStrikeAsync(adminId, new CreateStrikeRequest(
            channel.ChannelId,
            "HATE_SPEECH",
            StrikeSeverities.High,
            "Phát ngôn thù địch",
            null
        ));
        Assert.Equal(2, strike2.StrikeNumber);
        var status2 = await _strikeService.GetChannelStrikeStatusAsync(channel.ChannelId);
        Assert.Equal(2, status2.ActiveStrikesCount);
        Assert.False(status2.IsSuspended);

        // Strike 3 - Triggers auto suspension
        var strike3 = await _strikeService.CreateManualStrikeAsync(adminId, new CreateStrikeRequest(
            channel.ChannelId,
            "VIOLENCE",
            StrikeSeverities.Critical,
            "Bạo lực nghiêm trọng",
            null
        ));
        Assert.Equal(3, strike3.StrikeNumber);
        var status3 = await _strikeService.GetChannelStrikeStatusAsync(channel.ChannelId);
        Assert.Equal(3, status3.ActiveStrikesCount);
        Assert.True(status3.IsSuspended);

        var channelAfter3 = await _db.Channels.SingleAsync(c => c.ChannelId == channel.ChannelId);
        Assert.Equal("suspended", channelAfter3.Status);

        // Revoke Strike 3 - Channel drops below 3 active strikes and should be restored
        await _strikeService.RevokeStrikeAsync(adminId, strike3.StrikeId, new RevokeStrikeRequest("Đính chính nhầm lẫn"));

        var channelAfterRevoke = await _db.Channels.SingleAsync(c => c.ChannelId == channel.ChannelId);
        Assert.Equal("active", channelAfterRevoke.Status);

        var statusAfterRevoke = await _strikeService.GetChannelStrikeStatusAsync(channel.ChannelId);
        Assert.Equal(2, statusAfterRevoke.ActiveStrikesCount);
        Assert.False(statusAfterRevoke.IsSuspended);
    }

    [Fact]
    public async Task Appeal_SeparationOfDuties_PreventsOriginalReviewerFromResolving()
    {
        // Arrange
        var userId = Guid.NewGuid();
        var reviewerA = Guid.NewGuid();
        var reviewerB = Guid.NewGuid();

        var channel = new Channel
        {
            ChannelId = Guid.NewGuid(),
            OwnerUserId = userId,
            Name = "Appeal Channel",
            Handle = "appealchan",
            Status = "suspended",
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        _db.Channels.Add(channel);

        var video = new Video
        {
            VideoId = Guid.NewGuid(),
            ChannelId = channel.ChannelId,
            Title = "Appealed Video",
            Description = "Desc",
            Status = "published",
            ModerationStatus = "rejected",
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        _db.Videos.Add(video);

        var mc = new ModerationCase
        {
            ModerationCaseId = Guid.NewGuid(),
            VideoId = video.VideoId,
            CaseType = "upload_review",
            Status = "resolved",
            Decision = "reject",
            ReviewerId = reviewerA, // Reviewer A made the rejection decision
            SubmittedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        _db.ModerationCases.Add(mc);
        await _db.SaveChangesAsync();

        // User submits appeal
        var appealDto = await _appealService.CreateAppealAsync(userId, new CreateAppealRequest(
            AppealTargetTypes.Video,
            video.VideoId,
            "Video bị từ chối nhầm, xin xem xét lại",
            "https://evidence.example.com",
            "Note",
            mc.ModerationCaseId,
            null
        ));

        // Act & Assert 1: Reviewer A (original reviewer) cannot claim or resolve
        var claimEx = await Assert.ThrowsAsync<AuthException>(() =>
            _appealService.ClaimAppealAsync(reviewerA, appealDto.AppealId));
        Assert.Equal("CANNOT_RESOLVE_OWN_CASE", claimEx.Code);

        var resolveEx = await Assert.ThrowsAsync<AuthException>(() =>
            _appealService.ResolveAppealAsync(reviewerA, appealDto.AppealId, new ResolveAppealRequest("approve", "ok")));
        Assert.Equal("CANNOT_RESOLVE_OWN_CASE", resolveEx.Code);

        // Act & Assert 2: Reviewer B (independent reviewer) can resolve and approve
        var result = await _appealService.ResolveAppealAsync(reviewerB, appealDto.AppealId, new ResolveAppealRequest(
            "approve",
            "Đã kiểm tra lại và chấp thuận kháng cáo."
        ));

        Assert.Equal(AppealStatuses.Approved, result.Status);

        // Verify video is restored to approved
        var restoredVideo = await _db.Videos.SingleAsync(v => v.VideoId == video.VideoId);
        Assert.Equal("approved", restoredVideo.ModerationStatus);
    }

    [Fact]
    public async Task Report_CanReportVideoCommentAndChannel()
    {
        // Arrange
        var reporterId = Guid.NewGuid();
        var authorId = Guid.NewGuid();

        var vt = new ViolationType
        {
            ViolationTypeId = Guid.NewGuid(),
            Code = "HARASSMENT",
            Name = "Quấy rối",
            Status = "active",
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        _db.ViolationTypes.Add(vt);

        var channel = new Channel
        {
            ChannelId = Guid.NewGuid(),
            OwnerUserId = authorId,
            Name = "Target Channel",
            Handle = "targetchan",
            Status = "active",
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        _db.Channels.Add(channel);

        var video = new Video
        {
            VideoId = Guid.NewGuid(),
            ChannelId = channel.ChannelId,
            Title = "Target Video",
            Description = "Desc",
            Status = "published",
            ModerationStatus = "approved",
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        _db.Videos.Add(video);

        var comment = new Comment
        {
            CommentId = Guid.NewGuid(),
            VideoId = video.VideoId,
            UserId = authorId,
            Content = "Target Comment",
            Status = "visible",
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        _db.Comments.Add(comment);
        await _db.SaveChangesAsync();

        // Act - Report video, comment, channel
        var videoReport = await _reportService.CreateReportAsync(reporterId, new CreateContentReportRequest(
            "video", video.VideoId, vt.ViolationTypeId, "Video quấy rối"
        ));
        var commentReport = await _reportService.CreateReportAsync(reporterId, new CreateContentReportRequest(
            "comment", comment.CommentId, vt.ViolationTypeId, "Bình luận xúc phạm"
        ));
        var channelReport = await _reportService.CreateReportAsync(reporterId, new CreateContentReportRequest(
            "channel", channel.ChannelId, vt.ViolationTypeId, "Kênh giả mạo"
        ));

        // Assert
        Assert.Equal("video", videoReport.TargetType);
        Assert.Equal(video.VideoId, videoReport.TargetId);

        Assert.Equal("comment", commentReport.TargetType);
        Assert.Equal(comment.CommentId, commentReport.TargetId);

        Assert.Equal("channel", channelReport.TargetType);
        Assert.Equal(channel.ChannelId, channelReport.TargetId);

        var queue = await _reportService.GetReportsQueueAsync(status: "pending");
        Assert.Equal(3, queue.Count);
    }
}
