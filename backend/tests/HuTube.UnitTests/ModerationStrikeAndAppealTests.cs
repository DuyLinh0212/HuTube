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
using System.Text.Json;

namespace HuTube.UnitTests;

public sealed class ModerationStrikeAndAppealTests : IDisposable
{
    private readonly HuTubeDbContext _db;
    private readonly StrikeService _strikeService;
    private readonly ModerationService _moderationService;
    private readonly ReportService _reportService;
    private readonly AppealService _appealService;
    private readonly FakeNotificationService _notifications = new();
    private IEnumerable<NotificationMessage> QueuedModerationNotifications => _db.ModerationOutboxEvents.AsEnumerable()
        .SelectMany(row => JsonSerializer.Deserialize<VideoModerationEvent>(row.Payload)!.OwnerNotifications);

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

    private sealed class FakeEmailSender : IAuthEmailSender
    {
        public Task SendAsync(string email, string subject, string body, CancellationToken cancellationToken) => Task.CompletedTask;
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
        _reportService = new ReportService(_db, rbacService, _notifications, _strikeService, new FakeEmailSender(), Microsoft.Extensions.Logging.Abstractions.NullLogger<ReportService>.Instance);
        _appealService = new AppealService(_db, rbacService, _notifications, new FakeObjectStorage(), new Microsoft.AspNetCore.Http.HttpContextAccessor());
        _moderationService = new ModerationService(_db, rbacService, new FakeObjectStorage());
    }

    public void Dispose()
    {
        _db.Dispose();
    }

    [Fact]
    public async Task Decision_PinsPublishedPolicyVersion_AfterNewPublication()
    {
        var channel = new Channel { OwnerUserId = Guid.NewGuid(), Name = "Policy evidence" };
        var video = new Video { ChannelId = channel.ChannelId, Title = "Policy target", Visibility = "public", Status = "pending", ModerationStatus = "pending" };
        var item = new ModerationCase { VideoId = video.VideoId, CaseType = "upload_review" };
        var policy = new Policy { Code = "DELTA.PINNED", Name = "Original", Content = "Original rule", Version = "1.0", Status = "published", EffectiveAt = DateTimeOffset.UtcNow.AddMinutes(-1) };
        _db.Channels.Add(channel); _db.Videos.Add(video); _db.ModerationCases.Add(item); _db.Policies.Add(policy);
        await _db.SaveChangesAsync();
        var reviewer = Guid.NewGuid();
        var lease = await _moderationService.ClaimCaseAsync(reviewer, item.ModerationCaseId);
        await _moderationService.ResolveCaseAsync(reviewer, item.ModerationCaseId,
            new ResolveModerationRequest("reject", policy.Code, "Original policy decision", null, lease.ClaimId));
        Assert.Equal("1.0", item.PolicyVersion);
        var policies = new HuTube.Infrastructure.Policies.PolicyService(_db);
        await policies.PublishPolicyVersionAsync(reviewer, policy.PolicyId,
            new HuTube.Application.Policies.UpdatePolicyRequest("Next", "content", "New rule", "high", "published", "2.0"));
        _db.ChangeTracker.Clear();
        var saved = await _db.ModerationCases.SingleAsync(c => c.ModerationCaseId == item.ModerationCaseId);
        Assert.Equal("1.0", saved.PolicyVersion);
        Assert.Equal(policy.Code, saved.PolicyCode);
        Assert.Equal("Original rule", (await _db.Policies.SingleAsync(p => p.PolicyId == policy.PolicyId)).Content);
        Assert.Equal("2.0", Assert.Single(await policies.GetPublicPoliciesAsync()).Version);
    }

    [Theory]
    [InlineData("suspended", 409)]
    [InlineData("deleted", 404)]
    public async Task Decision_RejectsChannelUnavailableAfterClaim_WithoutMutatingTarget(string status, int expectedStatus)
    {
        var channel = new Channel { OwnerUserId = Guid.NewGuid(), Name = "Unavailable target" };
        var video = new Video { ChannelId = channel.ChannelId, Title = "Pending target", Visibility = "public", Status = "pending", ModerationStatus = "pending" };
        var item = new ModerationCase { VideoId = video.VideoId, CaseType = "upload_review" };
        _db.Channels.Add(channel); _db.Videos.Add(video); _db.ModerationCases.Add(item);
        await _db.SaveChangesAsync();
        var reviewer = Guid.NewGuid();
        var lease = await _moderationService.ClaimCaseAsync(reviewer, item.ModerationCaseId);
        channel.Status = status;
        await _db.SaveChangesAsync();
        var error = await Assert.ThrowsAsync<AuthException>(() => _moderationService.ResolveCaseAsync(reviewer, item.ModerationCaseId,
            new ResolveModerationRequest("approve", null, "Do not publish unavailable channel", null, lease.ClaimId)));
        Assert.Equal(expectedStatus, error.Status);
        Assert.Null(item.Decision);
        Assert.Null(item.ResolvedAt);
        Assert.Equal("pending", video.Status);
        Assert.Equal("pending", video.ModerationStatus);
        Assert.Null(video.PublishedAt);
        Assert.Empty(_notifications.Notifications);
    }

    [Fact]
    public async Task ApprovedCase_RejectsReplayAndReclaim_WithoutDuplicateNotification()
    {
        var ownerId = Guid.NewGuid();
        var channel = new Channel { ChannelId = Guid.NewGuid(), OwnerUserId = ownerId, Name = "Replay test", Handle = "replay-test" };
        var video = new Video { VideoId = Guid.NewGuid(), ChannelId = channel.ChannelId, Title = "Replay video", Visibility = "public", Status = "pending", ModerationStatus = "pending" };
        var item = new ModerationCase { ModerationCaseId = Guid.NewGuid(), VideoId = video.VideoId, CaseType = "video_upload", Status = "reviewing" };
        _db.Channels.Add(channel); _db.Videos.Add(video); _db.ModerationCases.Add(item);
        await _db.SaveChangesAsync();
        var reviewerId = Guid.NewGuid();
        var lease = await _moderationService.ClaimCaseAsync(reviewerId, item.ModerationCaseId);
        var request = new ResolveModerationRequest("approve", "Safe", null, null, lease.ClaimId);
        await _moderationService.ResolveCaseAsync(reviewerId, item.ModerationCaseId, request);
        var resolvedAt = item.ResolvedAt;
        Assert.Empty(_notifications.Notifications);
        var noticeCount = _db.ModerationOutboxEvents.Count();
        Assert.Equal(1, noticeCount);
        Assert.Equal(1, noticeCount);

        var error = await Assert.ThrowsAsync<AuthException>(() => _moderationService.ResolveCaseAsync(Guid.NewGuid(), item.ModerationCaseId, request));
        Assert.Equal(409, error.Status);
        Assert.Equal("CASE_ALREADY_PROCESSED", error.Code);
        var claimError = await Assert.ThrowsAsync<AuthException>(() => _moderationService.ClaimCaseAsync(Guid.NewGuid(), item.ModerationCaseId));
        Assert.Equal(409, claimError.Status);
        Assert.Equal("approved", item.Status);
        Assert.Equal(reviewerId, item.ReviewerId);
        Assert.Equal(resolvedAt, item.ResolvedAt);
        Assert.Equal(noticeCount, _db.ModerationOutboxEvents.Count());
    }

    [Fact]
    public async Task ClaimedCase_CannotBeResolvedByAnotherReviewer_WithoutSideEffects()
    {
        var claimant = Guid.NewGuid();
        var channel = new Channel { ChannelId = Guid.NewGuid(), OwnerUserId = Guid.NewGuid(), Name = "Claimed" };
        var video = new Video { VideoId = Guid.NewGuid(), ChannelId = channel.ChannelId, Status = "pending", ModerationStatus = "pending" };
        var item = new ModerationCase { VideoId = video.VideoId, Status = "reviewing", ReviewerId = claimant };
        _db.Channels.Add(channel); _db.Videos.Add(video); _db.ModerationCases.Add(item);
        await _db.SaveChangesAsync();
        var error = await Assert.ThrowsAsync<AuthException>(() => _moderationService.ResolveCaseAsync(Guid.NewGuid(), item.ModerationCaseId,
            new ResolveModerationRequest("approve", "Wrong reviewer", null, null)));
        Assert.Equal(409, error.Status);
        Assert.Equal(claimant, item.ReviewerId);
        Assert.Null(item.ResolvedAt);
        Assert.Equal("pending", video.Status);
        Assert.Null(video.PublishedAt);
        Assert.Empty(_notifications.Notifications);
        var lease = await _moderationService.ClaimCaseAsync(claimant, item.ModerationCaseId);
        await _moderationService.ResolveCaseAsync(claimant, item.ModerationCaseId, new ResolveModerationRequest("approve", "Claim owner", null, null, lease.ClaimId));
        Assert.Equal("published", video.Status);
        Assert.Single(QueuedModerationNotifications);
        Assert.Empty(_notifications.Notifications);
    }

    [Theory]
    [InlineData("approved")]
    [InlineData("rejected")]
    [InlineData("resolved")]
    public async Task TerminalCase_RejectsAnotherDecisionBeforeTargetOrNotificationChanges(string status)
    {
        var item = new ModerationCase { ModerationCaseId = Guid.NewGuid(), Status = status };
        _db.ModerationCases.Add(item); await _db.SaveChangesAsync();
        var error = await Assert.ThrowsAsync<AuthException>(() => _moderationService.ResolveCaseAsync(Guid.NewGuid(), item.ModerationCaseId, new ResolveModerationRequest("approve", "Retry", null, null)));
        Assert.Equal(409, error.Status);
        Assert.Equal(status, item.Status);
        Assert.Empty(_notifications.Notifications);
    }

    [Theory]
    [InlineData(0, 7, false)]
    [InlineData(1, 14, false)]
    [InlineData(2, 14, true)]
    public async Task AutoStrikeRule_FifthVideoRejection_AppliesConfiguredTier(int existingStrikeCount, int restrictionDays, bool suspended)
    {
        // Arrange
        var beforeRejection = DateTimeOffset.UtcNow;
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
        _db.StrikePolicyConfigurations.Add(new StrikePolicyConfiguration
        {
            RejectedVideosEffectiveAt = beforeRejection.AddDays(-1)
        });
        for (var number = 1; number <= existingStrikeCount; number++)
        {
            _db.ChannelStrikes.Add(new ChannelStrike
            {
                ChannelId = channel.ChannelId,
                UserId = ownerId,
                StrikeNumber = number,
                PolicyCode = "COPYRIGHT",
                Reason = "Existing active strike",
                ExpiresAt = beforeRejection.AddDays(90)
            });
        }

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
            Status = "pending",
            ReviewerId = reviewerId,
            SubmittedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        _db.ModerationCases.Add(mc);
        await _db.SaveChangesAsync();

        // Act - Reviewer rejects the 5th video
        var lease = await _moderationService.ClaimCaseAsync(reviewerId, mc.ModerationCaseId);
        var resolution = await _moderationService.ResolveCaseAsync(reviewerId, mc.ModerationCaseId, new ResolveModerationRequest(
            "reject",
            "Vi phạm bản quyền nghiêm trọng",
            "Auto lock check",
            "COPYRIGHT", lease.ClaimId
        ));

        // Assert
        Assert.Equal("rejected", resolution.Status);
        Assert.Equal("reject", resolution.Decision);

        var updatedChannel = await _db.Channels.SingleAsync(c => c.ChannelId == channel.ChannelId);
        Assert.Equal(suspended ? "suspended" : "active", updatedChannel.Status);

        var strike = Assert.Single(await _db.ChannelStrikes.Where(s => s.SourceModerationCaseId == mc.ModerationCaseId).ToListAsync());
        Assert.Equal(existingStrikeCount + 1, strike.StrikeNumber);
        Assert.Equal(StrikeSeverities.High, strike.Severity);
        Assert.Equal("SPAM.REPEATED_VIOLATIONS", strike.PolicyCode);
        Assert.Contains("5 video bị từ chối", strike.Reason);
        Assert.NotNull(strike.UploadRestrictedUntil);
        Assert.InRange(strike.UploadRestrictedUntil.Value, beforeRejection.AddDays(restrictionDays), DateTimeOffset.UtcNow.AddDays(restrictionDays));
        Assert.InRange(strike.ExpiresAt, beforeRejection.AddDays(90), DateTimeOffset.UtcNow.AddDays(90));

        Assert.Contains(QueuedModerationNotifications, n => n.Type == "channel_strike" && n.UserId == ownerId);
        if (suspended)
            Assert.Contains(QueuedModerationNotifications, n => n.Type == "channel_suspended" && n.UserId == ownerId);
        else
            Assert.DoesNotContain(QueuedModerationNotifications, n => n.Type == "channel_suspended");
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
            Status = "blocked",
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
            null,
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
        var lease = await _appealService.ClaimAppealAsync(reviewerB, appealDto.AppealId);
        var result = await _appealService.ResolveAppealAsync(reviewerB, appealDto.AppealId, new ResolveAppealRequest(
            "approve",
            "Đã kiểm tra lại và chấp thuận kháng cáo.", lease.ClaimId
        ));

        Assert.Equal(AppealStatuses.Approved, result.Status);

        // Verify video is restored to approved
        var restoredVideo = await _db.Videos.SingleAsync(v => v.VideoId == video.VideoId);
        Assert.Equal("approved", restoredVideo.ModerationStatus);
        Assert.Equal("published", restoredVideo.Status);
        Assert.NotNull(restoredVideo.PublishedAt);
        var publishedAt = restoredVideo.PublishedAt;
        var noticeCount = _notifications.Notifications.Count;
        var replay = await Assert.ThrowsAsync<AuthException>(() => _appealService.ResolveAppealAsync(reviewerB, appealDto.AppealId,
            new ResolveAppealRequest("approve", "Duplicate decision")));
        Assert.Equal(409, replay.Status);
        var reclaim = await Assert.ThrowsAsync<AuthException>(() => _appealService.ClaimAppealAsync(reviewerB, appealDto.AppealId));
        Assert.Equal(409, reclaim.Status);
        Assert.Equal(publishedAt, restoredVideo.PublishedAt);
        Assert.Equal(noticeCount, _notifications.Notifications.Count);
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
            Visibility = "public",
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
