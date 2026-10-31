using HuTube.Domain.Users;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql;

namespace HuTube.IntegrationTests;

public sealed class RoleRemovalMigrationTests
{
    [Fact]
    public async Task NullableRoleMigration_PreservesUsers_AndRequiresExplicitReassignmentBeforeRollback()
    {
        var factory = new AuthApiFactory();
        try
        {
            await factory.InitializeAsync();
            await using var db = factory.CreateDb();
            var migrator = db.GetService<IMigrator>();
            const string previous = "20261025080000_AddChannelSuspensionExpiry";
            await migrator.MigrateAsync(previous);
            var owner = new User { Username = "migration_role", Email = "migration_role@example.test", DisplayName = "Kept user",
                PasswordHash = "unused", RoleId = UserRoles.User, Status = "active", CreatedAt = DateTimeOffset.UtcNow, UpdatedAt = DateTimeOffset.UtcNow };
            await db.Database.ExecuteSqlInterpolatedAsync($"""
                INSERT INTO public.users (user_id, username, email, password_hash, display_name, status, role_id, created_at, updated_at)
                VALUES ({owner.UserId}, {owner.Username}, {owner.Email}, {owner.PasswordHash}, {owner.DisplayName}, {owner.Status}, {UserRoles.User}, {owner.CreatedAt}, {owner.UpdatedAt})
                """);
            await migrator.MigrateAsync();
            Assert.Equal(UserRoles.User, (await db.Users.AsNoTracking().SingleAsync(u => u.UserId == owner.UserId)).RoleId);
            await db.Users.Where(u => u.UserId == owner.UserId).ExecuteUpdateAsync(update => update.SetProperty(u => u.RoleId, (Guid?)null));
            var error = await Assert.ThrowsAsync<PostgresException>(() => migrator.MigrateAsync(previous));
            Assert.Contains("Reassign users without a role", error.MessageText);
            // A failed downgrade can leave earlier migrations in the batch reverted.
            // Reapply them before querying through the current EF model.
            await migrator.MigrateAsync();
            var user = await db.Users.AsNoTracking().SingleAsync(u => u.UserId == owner.UserId);
            Assert.Null(user.RoleId);
            Assert.Equal("Kept user", user.DisplayName);
            await db.Users.Where(u => u.UserId == owner.UserId).ExecuteUpdateAsync(update => update.SetProperty(u => u.RoleId, (Guid?)UserRoles.User));
            await migrator.MigrateAsync(previous);
            await migrator.MigrateAsync();
            user = await db.Users.AsNoTracking().SingleAsync(u => u.UserId == owner.UserId);
            Assert.Equal(UserRoles.User, user.RoleId);
            Assert.Equal(owner.Email, user.Email);
        }
        finally { await ((Xunit.IAsyncLifetime)factory).DisposeAsync(); }
    }
}
