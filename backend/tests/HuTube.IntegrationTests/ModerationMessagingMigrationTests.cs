using HuTube.Domain.Videos;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql;

namespace HuTube.IntegrationTests;

public sealed class ModerationMessagingMigrationTests(AuthApiFactory factory) : IClassFixture<AuthApiFactory>
{
    [Fact]
    public async Task MigrationCanRollBackAndReapply_ButRefusesToDiscardPendingWork()
    {
        await using var db = factory.CreateDb();
        var id = Guid.NewGuid(); var now = DateTimeOffset.UtcNow;
        db.ModerationOutboxEvents.Add(new ModerationOutboxEvent { EventId = id, EventType = "test", Payload = "{}", OccurredAt = now, AvailableAt = now });
        await db.SaveChangesAsync();
        var migrator = db.GetService<IMigrator>();
        var error = await Assert.ThrowsAsync<PostgresException>(() => migrator.MigrateAsync("20261025090000_AllowUsersWithoutRole"));
        Assert.Contains("Drain moderation messages", error.MessageText);
        Assert.NotNull(await db.ModerationOutboxEvents.AsNoTracking().SingleAsync(row => row.EventId == id));
        await db.ModerationOutboxEvents.Where(row => row.EventId == id).ExecuteUpdateAsync(set => set.SetProperty(row => row.PublishedAt, now));
        await migrator.MigrateAsync("20261025090000_AllowUsersWithoutRole");
        Assert.DoesNotContain("20261025100000_AddModerationNotificationOutbox", await db.Database.GetAppliedMigrationsAsync());
        await migrator.MigrateAsync();
        Assert.Contains("20261025100000_AddModerationNotificationOutbox", await db.Database.GetAppliedMigrationsAsync());
        Assert.Empty(await db.ModerationOutboxEvents.AsNoTracking().ToListAsync());
        Assert.Empty(await db.PushDevices.AsNoTracking().ToListAsync());
    }
}
