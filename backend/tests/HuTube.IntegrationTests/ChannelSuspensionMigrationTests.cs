using HuTube.Domain.Users;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.IntegrationTests;

public sealed class ChannelSuspensionMigrationTests
{
    [Fact]
    public async Task UpgradeAndRollbackPreserveLegacySuspensionAndChannelData()
    {
        var factory = new AuthApiFactory();
        try
        {
            await factory.InitializeAsync();
            await using var db = factory.CreateDb();
            var migrator = db.GetService<IMigrator>();
            const string previous = "20261024080000_ReadCacheRevisions";
            await migrator.MigrateAsync(previous);
            var now = DateTimeOffset.UtcNow;
            var owner = new User { Username = "legacy_timer", Email = "legacy_timer@example.test", DisplayName = "Legacy owner",
                PasswordHash = "unused", RoleId = UserRoles.User, Status = "active", CreatedAt = now, UpdatedAt = now };
            db.Users.Add(owner);
            await db.SaveChangesAsync();
            var id = Guid.NewGuid();
            await db.Database.ExecuteSqlInterpolatedAsync($"""
                INSERT INTO public.channels (channel_id, owner_user_id, name, handle, settings, status, status_reason, created_at, updated_at)
                VALUES ({id}, {owner.UserId}, 'Legacy suspended channel', 'legacy_timer', {"{}"}::jsonb, 'suspended', 'Keep existing restriction', {now}, {now})
                """);
            await migrator.MigrateAsync();
            var channel = await db.Channels.AsNoTracking().SingleAsync(c => c.ChannelId == id);
            Assert.Equal("suspended", channel.Status);
            Assert.Equal("Keep existing restriction", channel.StatusReason);
            Assert.Null(channel.SuspendedUntil);

            await db.Channels.Where(c => c.ChannelId == id).ExecuteUpdateAsync(update => update.SetProperty(c => c.SuspendedUntil, now.AddDays(7)));
            await migrator.MigrateAsync(previous);
            await migrator.MigrateAsync();
            channel = await db.Channels.AsNoTracking().SingleAsync(c => c.ChannelId == id);
            Assert.Equal("suspended", channel.Status);
            Assert.Null(channel.SuspendedUntil);
            Assert.Equal("Legacy suspended channel", channel.Name);
            Assert.Equal("Keep existing restriction", channel.StatusReason);
            Assert.Equal(owner.UserId, channel.OwnerUserId);
        }
        finally { await ((Xunit.IAsyncLifetime)factory).DisposeAsync(); }
    }
}
