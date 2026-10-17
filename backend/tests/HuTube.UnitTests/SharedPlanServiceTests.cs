using HuTube.Application.Auth;
using HuTube.Application.Rbac;
using HuTube.Domain.Channels;
using HuTube.Domain.Plans;
using HuTube.Domain.Users;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using HuTube.Infrastructure.Plans;
using Microsoft.EntityFrameworkCore;

namespace HuTube.UnitTests;

public sealed class SharedPlanServiceTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task ExpiredHistory_CannotGrantCachedPaidFeatures_BeforeWorker(bool sharedMember)
    {
        using var db = new HuTubeDbContext(new DbContextOptionsBuilder<HuTubeDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var free = new Plan { PlanId = Guid.NewGuid(), Code = "free", StorageLimit = 100, IsDefaultForNewUsers = true, Features = "{\"pip\":false,\"background_play\":false}" };
        var paid = new Plan { PlanId = Guid.NewGuid(), Code = "paid", Price = 10, StorageLimit = 1000, Features = "{\"pip\":true,\"background_play\":true}" };
        var user = new User { Email = "expired@example.test", PlanId = paid.PlanId };
        var owner = new User { Email = "owner@example.test", PlanId = paid.PlanId };
        var history = new PlanHistory { UserId = sharedMember ? owner.UserId : user.UserId, PlanId = paid.PlanId, EndedAt = DateTimeOffset.UtcNow.AddMinutes(-1) };
        db.Plans.AddRange(free, paid); db.Users.AddRange(user, owner); db.PlanHistories.Add(history);
        if (sharedMember) db.PlanMembers.Add(new PlanMember { OwnerUserId = owner.UserId, MemberUserId = user.UserId, MemberEmail = user.Email, PlanHistoryId = history.PlanHistoryId, Status = "accepted" });
        await db.SaveChangesAsync();
        var service = new PlanService(db, new Mail(), TimeProvider.System, new AuthOptions(), new RbacService(new RbacStore(db), new AuthStore(db)));
        var detail = await service.GetMyPlanAsync(user.UserId);
        Assert.Equal(free.PlanId, detail!.PlanId);
        Assert.NotNull(detail.Features);
        Assert.False(detail.Features["pip"]);
        Assert.False(detail.Features["background_play"]);
        Assert.Null(detail.Subscription);
        Assert.False(detail.IsSharedMember);
        Assert.Equal(paid.PlanId, user.PlanId); // Read must be safe without waiting for worker mutation.
    }

    private sealed class Mail : IAuthEmailSender
    {
        public Task SendAsync(string email, string subject, string body, CancellationToken ct) => Task.CompletedTask;
    }

    [Fact]
    public async Task AcceptSharedPlan_OverridesDefaultFreeQuota_AndRevocationRestoresIt()
    {
        using var db = new HuTubeDbContext(new DbContextOptionsBuilder<HuTubeDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var free = new Plan { PlanId = Guid.NewGuid(), Code = "free", StorageLimit = 100 };
        var shared = new Plan { PlanId = Guid.NewGuid(), Code = "shared", StorageLimit = 1000, Features = "{\"pip\":true}" };
        var user = new User { Email = "member@example.test", PlanId = free.PlanId };
        var owner = new User { Email = "owner@example.test", PlanId = shared.PlanId };
        var personalHistory = new PlanHistory { UserId = user.UserId, OwnerUserId = user.UserId, PlanId = free.PlanId };
        var sharedHistory = new PlanHistory { UserId = owner.UserId, OwnerUserId = owner.UserId, PlanId = shared.PlanId };
        var channel = new Channel { ChannelId = Guid.NewGuid(), OwnerUserId = user.UserId, Status = "active" };
        var quota = new ChannelQuota { ChannelQuotaId = Guid.NewGuid(), ChannelId = channel.ChannelId, StorageLimit = 100, StorageUsed = 10 };
        var member = new PlanMember { OwnerUserId = owner.UserId, PlanHistoryId = sharedHistory.PlanHistoryId, MemberEmail = user.Email, AllocatedStorage = 200 };
        db.Plans.AddRange(free, shared); db.Users.AddRange(user, owner);
        db.PlanHistories.AddRange(personalHistory, sharedHistory); db.Channels.Add(channel); db.ChannelQuotas.Add(quota); db.PlanMembers.Add(member);
        db.PlanInvitationTokens.Add(new PlanInvitationToken { PlanMemberId = member.PlanMemberId, Token = "owned-token", ExpiresAt = DateTimeOffset.UtcNow.AddHours(1) });
        await db.SaveChangesAsync();
        var service = new PlanService(db, new Mail(), TimeProvider.System, new AuthOptions(), new RbacService(new RbacStore(db), new AuthStore(db)));
        await service.AcceptInvitationAsync(user.UserId, member.PlanMemberId, "owned-token");
        var detail = await service.GetMyPlanAsync(user.UserId);
        Assert.True(detail!.IsSharedMember);
        Assert.Equal(shared.PlanId, detail.PlanId);
        Assert.Equal(member.PlanMemberId, Assert.Single(detail.Members).PlanMemberId);
        Assert.Equal(190, detail.RemainingStorage);
        Assert.Equal(200, await service.GetEffectiveStorageLimitAsync(user.UserId));
        Assert.Equal(200, quota.StorageLimit);
        await service.RemoveMemberAsync(owner.UserId, member.PlanMemberId);
        Assert.False((await service.GetMyPlanAsync(user.UserId))!.IsSharedMember);
        Assert.Equal(free.PlanId, user.PlanId);
        Assert.Equal(100, quota.StorageLimit);
        Assert.Equal(100, await service.GetEffectiveStorageLimitAsync(user.UserId));
    }
}
