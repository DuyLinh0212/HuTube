using HuTube.Application.Videos;
using HuTube.Domain.Channels;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using HuTube.Infrastructure.Videos;
using Microsoft.EntityFrameworkCore;

namespace HuTube.UnitTests;

public sealed class ViewSessionBoundaryTests
{
    [Theory]
    [InlineData(-1, 1)]
    [InlineData(0, 1)]
    [InlineData(1, 2)]
    public async Task ThirtyMinuteBoundary_ReusesSessionThroughExactDeadline(long ticksAfterBoundary, int expectedRows)
    {
        using var db = Database();
        var now = DateTimeOffset.Parse("2026-10-16T15:00:00Z");
        var viewer = Guid.NewGuid(); var video = Seed(db);
        db.ViewingHistories.Add(new ViewingHistory { UserId = viewer, VideoId = video.VideoId, WatchDuration = 10, ViewedAt = now.AddMinutes(-30).AddTicks(-ticksAfterBoundary) });
        await db.SaveChangesAsync();

        await Service(db, now).SaveProgressAsync(viewer, video.VideoId, new WatchProgressRequest(11));

        Assert.Equal(expectedRows, await db.ViewingHistories.CountAsync());
        Assert.Equal(11, (await db.ViewingHistories.OrderByDescending(row => row.ViewedAt).FirstAsync()).WatchDuration);
    }

    [Fact]
    public async Task DuplicateProgress_ReplacesCheckpointWithoutInflatingSessionOrWatchSeconds()
    {
        using var db = Database(); var video = Seed(db); var viewer = Guid.NewGuid();
        var service = Service(db, DateTimeOffset.UtcNow);
        await service.SaveProgressAsync(viewer, video.VideoId, new WatchProgressRequest(10));
        await service.SaveProgressAsync(viewer, video.VideoId, new WatchProgressRequest(10));
        await service.SaveProgressAsync(viewer, video.VideoId, new WatchProgressRequest(11));
        var row = Assert.Single(db.ViewingHistories);
        Assert.Equal(11, row.WatchDuration);
    }

    [Fact]
    public async Task HistoryOptOut_DoesNotCreateCountedViewEvenForExplicitNewSession()
    {
        using var db = Database(); var video = Seed(db);
        await Service(db, DateTimeOffset.UtcNow).SaveProgressAsync(Guid.NewGuid(), video.VideoId, new WatchProgressRequest(10, SaveHistory: false, NewSession: true));
        Assert.Empty(db.ViewingHistories);
    }

    private static HuTubeDbContext Database() => new(new DbContextOptionsBuilder<HuTubeDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
    private static Video Seed(HuTubeDbContext db)
    {
        var channel = new Channel { OwnerUserId = Guid.NewGuid(), Status = "active" };
        var video = new Video { ChannelId = channel.ChannelId, Duration = 60, Status = "published", Visibility = "public", ModerationStatus = "approved" };
        db.Channels.Add(channel); db.Videos.Add(video); db.SaveChanges();
        return video;
    }
    // SaveProgress touches only persistence, access policy and server time.
    private static ContentService Service(HuTubeDbContext db, DateTimeOffset now) =>
        new(db, null!, null!, null!, new FeatureOptions(), new Clock(now), null!, null!, null!, null!, null!);
    private sealed class Clock(DateTimeOffset now) : TimeProvider { public override DateTimeOffset GetUtcNow() => now; }
}
