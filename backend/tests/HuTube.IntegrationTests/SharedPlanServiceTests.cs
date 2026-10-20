using HuTube.Application.Auth;
using HuTube.Application.Rbac;
using HuTube.Domain.Channels;
using HuTube.Domain.Plans;
using HuTube.Domain.Users;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using HuTube.Infrastructure.Plans;
using Microsoft.EntityFrameworkCore;

namespace HuTube.IntegrationTests;

// Bulk updates, quota transfers and advisory locks require a relational provider.
public sealed class SharedPlanServiceTests(AuthApiFactory factory) : IClassFixture<AuthApiFactory>
{
    private sealed class Mail : IAuthEmailSender
    {
        public Task SendAsync(string email, string subject, string body, CancellationToken ct) => Task.CompletedTask;
    }

    [Fact]
    public async Task AcceptSharedPlan_OverridesDefaultFreeQuota_AndRevocationRestoresIt()
    {
        await using var db = factory.CreateDb();
        var free = await db.Plans.SingleAsync(p => p.Code == "free");
        free.StorageLimit = 100;
        var shared = new Plan { PlanId = Guid.NewGuid(), Code = "shared", Name = "Shared quota fixture",
            StorageLimit = 1000, DurationDays = 30, MaxUploadSize = 1000, MaxVideoDuration = 60,
            MaxVideoQuality = "720p", MaxMembers = 2, Features = "{\"pip\":true}" };
        var user = new User { Email = "member@example.test", Username = "shared_member", PasswordHash = "fixture-hash", DisplayName = "Shared member", RoleId = UserRoles.User, PlanId = free.PlanId };
        var owner = new User { Email = "owner@example.test", Username = "shared_owner", PasswordHash = "fixture-hash", DisplayName = "Shared owner", RoleId = UserRoles.User, PlanId = shared.PlanId };
        var personalHistory = new PlanHistory { UserId = user.UserId, OwnerUserId = user.UserId, PlanId = free.PlanId };
        var sharedHistory = new PlanHistory { UserId = owner.UserId, OwnerUserId = owner.UserId, PlanId = shared.PlanId };
        var channel = new Channel { ChannelId = Guid.NewGuid(), OwnerUserId = user.UserId, Name = "Shared member", Handle = "shared_member", Status = "active" };
        var quota = new ChannelQuota { ChannelQuotaId = Guid.NewGuid(), ChannelId = channel.ChannelId, StorageLimit = 100, StorageUsed = 10 };
        var member = new PlanMember { OwnerUserId = owner.UserId, PlanHistoryId = sharedHistory.PlanHistoryId, MemberEmail = user.Email, AllocatedStorage = 200 };
        db.Plans.Add(shared);
        await db.SaveChangesAsync();
        db.Users.AddRange(user, owner);
        await db.SaveChangesAsync();
        db.PlanHistories.AddRange(personalHistory, sharedHistory);
        await db.SaveChangesAsync();
        db.Channels.Add(channel);
        await db.SaveChangesAsync();
        db.ChannelQuotas.Add(quota); db.PlanMembers.Add(member);
        await db.SaveChangesAsync();
        db.PlanInvitationTokens.Add(new PlanInvitationToken { PlanMemberId = member.PlanMemberId, Token = "owned-token", ExpiresAt = DateTimeOffset.UtcNow.AddHours(1) });
        db.Videos.Add(new Video { ChannelId = channel.ChannelId, UploadedByUserId = user.UserId,
            StorageBillingOwnerUserId = user.UserId, Title = "Existing member upload", VideoUrl = "/fixture/member.mp4",
            Duration = 5, FileSize = 10, Status = "published", PublishedAt = DateTimeOffset.UtcNow });
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
        await db.Entry(user).ReloadAsync();
        Assert.Equal(free.PlanId, user.PlanId);
        Assert.Equal(100, quota.StorageLimit);
        Assert.Equal(100, await service.GetEffectiveStorageLimitAsync(user.UserId));
    }
}
