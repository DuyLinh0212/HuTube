using HuTube.Application.Videos;
using HuTube.Domain.Channels;
using HuTube.Domain.Users;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using HuTube.Infrastructure.Recommendations;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;

namespace HuTube.UnitTests;

public sealed class SimulationActionLimitTests
{
    [Theory]
    [InlineData(119, 100)]
    [InlineData(50, 1000)]
    public async Task QueuesSimulationUpToFiftyThousandActions(int userCount, int actionsPerUser)
    {
        // Arrange: test queue validation/persistence without executing the simulated actions.
        await using var db = Database();
        var users = Enumerable.Range(0, userCount).Select(i => new User {
            Username = $"limitbot{i}", Email = $"limitbot{i}@bot.hutube.invalid", Status = "active"
        }).ToArray();
        var channel = new Channel { OwnerUserId = users[0].UserId, Name = "Limit fixture", Handle = "limit-fixture", Status = "active" };
        var video = new Video { ChannelId = channel.ChannelId, UploadedByUserId = users[0].UserId,
            Title = "Limit video", Duration = 60, Status = "published", ModerationStatus = "approved", Visibility = "public" };
        db.Users.AddRange(users); db.Channels.Add(channel); db.Videos.Add(video);
        await db.SaveChangesAsync();
        var request = Request(users.Select(x => x.UserId).ToArray(), video.VideoId, actionsPerUser);

        // Act.
        var job = await Service(db).QueueSimulatorAsync(users[0].UserId, request, CancellationToken.None);

        // Assert.
        Assert.Equal(userCount * actionsPerUser, job.Total);
        Assert.Equal(job.JobId, (await db.RecommendationJobs.SingleAsync()).JobId);
        Assert.Single(await db.AuditLogs.Where(x => x.Action == "recommendations.simulation_queued").ToListAsync());
    }

    [Fact]
    public async Task RejectsMoreThanFiftyThousandBeforeQueueingAnyJob()
    {
        // Arrange.
        await using var db = Database();
        var request = Request(Enumerable.Range(0, 51).Select(_ => Guid.NewGuid()).ToArray(), Guid.NewGuid(), 1000);

        // Act.
        var error = await Assert.ThrowsAsync<ContentException>(() => Service(db)
            .QueueSimulatorAsync(Guid.NewGuid(), request, CancellationToken.None));

        // Assert.
        Assert.Equal("SIMULATION_ACTION_LIMIT", error.Code);
        Assert.Contains("50.000", error.Message);
        Assert.Empty(await db.RecommendationJobs.ToListAsync());
        Assert.Empty(await db.AuditLogs.ToListAsync());
    }

    private static SimulatorRequest Request(Guid[] users, Guid video, int actions) =>
        new(users, [video], "target", actions, 0, null, 100, 0, 0, 0, 0, 0, [], false);
    private static HuTubeDbContext Database() => new(new DbContextOptionsBuilder<HuTubeDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
    private static RecommendationAdminService Service(HuTubeDbContext db) =>
        new(db, null!, null!, new RecommendationOptions(), null!, null!, null!, NullLogger<RecommendationAdminService>.Instance);
}
