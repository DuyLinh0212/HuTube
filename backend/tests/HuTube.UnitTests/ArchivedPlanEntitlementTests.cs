using HuTube.Application.Auth;
using HuTube.Application.Rbac;
using HuTube.Domain.Plans;
using HuTube.Domain.Users;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using HuTube.Infrastructure.Plans;
using Microsoft.EntityFrameworkCore;

namespace HuTube.UnitTests;

public sealed class ArchivedPlanEntitlementTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task ArchivePlan_UnexpiredSubscription_RetainsOwnerAndSharedEntitlements(bool shared)
    {
        // Arrange
        using var db = CreateDb();
        var clock = new FixedClock();
        var (plan, user, history) = await SeedAsync(db, clock, shared, clock.GetUtcNow().AddDays(1));
        (await db.Plans.SingleAsync(p => p.Code == "free")).IsDefaultForNewUsers = false;
        plan.IsDefaultForNewUsers = true;
        await db.SaveChangesAsync();
        var service = CreateService(db, clock);
        var flags = plan.Features;
        var expires = history.EndedAt;

        // Act
        await service.ArchivePlanAsync(history.UserId, plan.PlanId);
        var current = await service.GetMyPlanAsync(user.UserId);
        var quota = await service.GetEffectiveStorageLimitAsync(user.UserId);

        // Assert
        Assert.Equal("archived", plan.Status);
        Assert.False(plan.IsDefaultForNewUsers);
        Assert.Equal(flags, plan.Features);
        Assert.True(await db.Plans.AnyAsync(p => p.PlanId == plan.PlanId));
        Assert.Equal("active", history.Status);
        Assert.Equal(expires, history.EndedAt);
        Assert.Equal(plan.PlanId, user.PlanId);
        Assert.Equal(plan.PlanId, current!.PlanId);
        Assert.Equal(shared, current.IsSharedMember);
        Assert.Equal(expires, current.Subscription!.EndedAt);
        Assert.False(current.Subscription.IsExpired);
        Assert.True(current.Features!["pip"]);
        Assert.True(current.Features["background_play"]);
        Assert.True(current.Features["download"]);
        Assert.Equal(shared ? 200L : 600L, quota);
        Assert.DoesNotContain(await service.GetPlansAsync(), p => p.PlanId == plan.PlanId);
    }

    [Theory]
    [InlineData(false, 0)]
    [InlineData(true, 0)]
    [InlineData(false, -1)]
    [InlineData(true, -1)]
    public async Task ArchivedPlan_AtOrAfterExpiry_DoesNotGrantPaidRightsBeforeWorker(bool shared, int seconds)
    {
        // Arrange
        using var db = CreateDb();
        var clock = new FixedClock();
        var (plan, user, _) = await SeedAsync(db, clock, shared, clock.GetUtcNow().AddSeconds(seconds));
        plan.Status = "archived";
        await db.SaveChangesAsync();
        var service = CreateService(db, clock);

        // Act
        var current = await service.GetMyPlanAsync(user.UserId);
        var quota = await service.GetEffectiveStorageLimitAsync(user.UserId);

        // Assert
        Assert.Equal("free", current!.Code);
        Assert.False(current.Features!["download"]);
        Assert.False(current.Features["pip"]);
        Assert.False(current.Features["background_play"]);
        Assert.Null(current.Subscription);
        Assert.Null(quota);
        Assert.Equal(plan.PlanId, user.PlanId);
    }

    private static HuTubeDbContext CreateDb() => new(new DbContextOptionsBuilder<HuTubeDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);

    private static PlanService CreateService(HuTubeDbContext db, TimeProvider clock) =>
        new(db, new Mail(), clock, new AuthOptions(), new RbacService(new RbacStore(db), new AuthStore(db)));

    private static async Task<(Plan, User, PlanHistory)> SeedAsync(HuTubeDbContext db, TimeProvider clock, bool shared, DateTimeOffset expiry)
    {
        var free = new Plan { PlanId = Guid.NewGuid(), Code = "free", StorageLimit = 100,
            IsDefaultForNewUsers = true, Features = "{\"pip\":false,\"background_play\":false,\"download\":false}" };
        var paid = new Plan { PlanId = Guid.NewGuid(), Code = "paid", Price = 10, StorageLimit = 1000,
            Features = "{\"pip\":true,\"background_play\":true,\"download\":true}" };
        var owner = new User { Email = "owner@example.test", PlanId = paid.PlanId };
        var member = new User { Email = "member@example.test", PlanId = paid.PlanId };
        var history = new PlanHistory { UserId = owner.UserId, OwnerUserId = owner.UserId, PlanId = paid.PlanId,
            StartedAt = clock.GetUtcNow().AddDays(-1), EndedAt = expiry, OwnerAllocatedStorage = 600 };
        db.Plans.AddRange(free, paid);
        db.Users.AddRange(owner, member);
        db.PlanHistories.Add(history);
        if (shared) db.PlanMembers.Add(new PlanMember { OwnerUserId = owner.UserId, MemberUserId = member.UserId,
            MemberEmail = member.Email, PlanHistoryId = history.PlanHistoryId, Status = "accepted", AllocatedStorage = 200 });
        await db.SaveChangesAsync();
        return (paid, shared ? member : owner, history);
    }

    private sealed class FixedClock : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => DateTimeOffset.Parse("2026-10-25T00:00:00Z");
    }

    private sealed class Mail : IAuthEmailSender
    {
        public Task SendAsync(string email, string subject, string body, CancellationToken ct) => Task.CompletedTask;
    }
}
