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

public sealed class FamilyStorageUsageTests(AuthApiFactory factory) : IClassFixture<AuthApiFactory>
{
    private const long Gb = 1024L * 1024 * 1024;

    [Theory]
    [InlineData("active")]
    [InlineData("archived")]
    public async Task OwnerBreakdown_ReconcilesBilledStorage_IncludesZeroAndFormerMembers_AndStaysPrivate(string status)
    {
        await using var db = factory.CreateDb();
        var free = await db.Plans.FirstAsync(p => p.Code == "free");
        var plan = new Plan { Code = "family_" + Guid.NewGuid().ToString("N")[..10], Name = "Family fixture",
            Status = status, StorageLimit = 30 * Gb, MaxUploadSize = Gb, DurationDays = 30, MaxVideoDuration = 3600,
            MaxVideoQuality = "1080p", MaxMembers = 6 };
        db.Plans.Add(plan);
        await db.SaveChangesAsync();
        User Person(string name) => new() { Email = $"{Guid.NewGuid():N}@example.test", Username = "u_" + Guid.NewGuid().ToString("N")[..14],
            DisplayName = name, PasswordHash = "fixture", Status = "active", RoleId = UserRoles.User, PlanId = plan.PlanId,
            CreatedAt = DateTimeOffset.UtcNow, UpdatedAt = DateTimeOffset.UtcNow };
        var owner = Person("Owner"); var alice = Person("Alice"); var bob = Person("Bob");
        var former = Person("Former member"); var empty = Person("Empty member"); var unrelated = Person("Unrelated owner");
        former.PlanId = free.PlanId; unrelated.PlanId = free.PlanId;
        db.Users.AddRange(owner, alice, bob, former, empty, unrelated);
        await db.SaveChangesAsync();
        var history = new PlanHistory { UserId = owner.UserId, OwnerUserId = owner.UserId, PlanId = plan.PlanId,
            OwnerAllocatedStorage = 5 * Gb, EndedAt = DateTimeOffset.UtcNow.AddDays(30) };
        db.PlanHistories.Add(history);
        await db.SaveChangesAsync();
        Channel ChannelFor(User person, string state = "active") => new() { OwnerUserId = person.UserId, Name = person.DisplayName,
            Handle = "c_" + Guid.NewGuid().ToString("N")[..14], Status = state };
        var ownerChannel = ChannelFor(owner); var aliceChannel = ChannelFor(alice); var bobChannel = ChannelFor(bob, "suspended");
        var formerChannel = ChannelFor(former, "deleted"); var unrelatedChannel = ChannelFor(unrelated);
        db.Channels.AddRange(ownerChannel, aliceChannel, bobChannel, formerChannel, unrelatedChannel);
        await db.SaveChangesAsync();
        foreach (var (channel, used) in new[] { (ownerChannel, 2 * Gb), (aliceChannel, 3 * Gb), (bobChannel, 7 * Gb), (formerChannel, 0L) })
            db.ChannelQuotas.Add(new ChannelQuota { ChannelId = channel.ChannelId, StorageUsed = used, StorageLimit = 30 * Gb });
        PlanMember Member(User person, string state = "accepted") => new() { OwnerUserId = owner.UserId, PlanHistoryId = history.PlanHistoryId,
            MemberEmail = person.Email, MemberUserId = person.UserId, Status = state, AcceptedAt = DateTimeOffset.UtcNow,
            AllocatedStorage = person.UserId == empty.UserId ? 0 : 10 * Gb, RevokedAt = state == "revoked" ? DateTimeOffset.UtcNow : null };
        db.PlanMembers.AddRange(Member(alice), Member(bob), Member(empty), Member(former, "revoked"),
            new PlanMember { OwnerUserId = owner.UserId, PlanHistoryId = history.PlanHistoryId,
                MemberEmail = "pending@example.test", Status = "pending" });
        Video VideoFor(Channel channel, long size, Guid billingOwner, string state = "published") => new() {
            ChannelId = channel.ChannelId, UploadedByUserId = channel.OwnerUserId, StorageBillingOwnerUserId = billingOwner,
            Title = "Stored media", VideoUrl = "/fixture/video.mp4", Duration = 5, FileSize = size, Status = state,
            PublishedAt = DateTimeOffset.UtcNow, CreatedAt = DateTimeOffset.UtcNow };
        var purged = VideoFor(aliceChannel, 10 * Gb, owner.UserId); purged.MediaPurgedAt = DateTimeOffset.UtcNow;
        db.Videos.AddRange(VideoFor(ownerChannel, 2 * Gb, owner.UserId), VideoFor(aliceChannel, 3 * Gb, owner.UserId),
            VideoFor(bobChannel, 7 * Gb, owner.UserId), VideoFor(formerChannel, 4 * Gb, owner.UserId),
            VideoFor(aliceChannel, 9 * Gb, owner.UserId, "deleted"), purged, VideoFor(unrelatedChannel, 8 * Gb, unrelated.UserId));
        await db.SaveChangesAsync();
        var service = new PlanService(db, new TestEmails(), TimeProvider.System, new AuthOptions(), new RbacService(new RbacStore(db), new AuthStore(db)));
        var detail = (await service.GetMyPlanAsync(owner.UserId))!;
        Assert.False(detail.IsSharedMember);
        Assert.Equal(16 * Gb, detail.UsedStorage);
        Assert.Equal(14 * Gb, detail.RemainingStorage); // Free space in the whole 30 GB pool, independent of the owner's cap.
        Assert.Equal(2 * Gb, detail.OwnerOwnStorageUsed);
        Assert.NotNull(detail.StorageUsageBreakdown);
        var breakdown = detail.StorageUsageBreakdown;
        Assert.Equal(detail.UsedStorage, breakdown.Sum(item => item.StorageUsed));
        Assert.Equal(2 * Gb, Assert.Single(breakdown, item => item.IsOwner).StorageUsed);
        Assert.Equal(3 * Gb, Assert.Single(breakdown, item => item.UserId == alice.UserId).StorageUsed);
        Assert.Equal(7 * Gb, Assert.Single(breakdown, item => item.UserId == bob.UserId).StorageUsed);
        var previous = Assert.Single(breakdown, item => item.UserId == former.UserId);
        Assert.True(previous.IsFormerMember);
        Assert.Equal(4 * Gb, previous.StorageUsed);
        Assert.Equal(0, Assert.Single(breakdown, item => item.UserId == empty.UserId).StorageUsed);
        Assert.DoesNotContain(breakdown, item => item.UserId == unrelated.UserId);
        Assert.Equal(7 * Gb, Assert.Single(detail.Members, item => item.MemberUserId == bob.UserId).StorageUsed);
        Assert.DoesNotContain(detail.Members, item => item.MemberUserId == former.UserId);

        var memberDetail = (await service.GetMyPlanAsync(alice.UserId))!;
        Assert.True(memberDetail.IsSharedMember);
        Assert.Null(memberDetail.StorageUsageBreakdown);
        Assert.Null(memberDetail.OwnerOwnStorageUsed);
        Assert.Single(memberDetail.Members);
        Assert.Equal(alice.UserId, memberDetail.Members[0].MemberUserId);
        Assert.Equal(3 * Gb, memberDetail.UsedStorage);
        Assert.Equal(7 * Gb, memberDetail.RemainingStorage);
    }

    [Fact]
    public async Task SoloOwnerHasOnlyOwnUsage_AndNoSharedAllocationDataIsInvented()
    {
        await using var db = factory.CreateDb();
        var plan = await db.Plans.FirstAsync(p => p.Code == "free");
        var user = new User { Username = "solo_" + Guid.NewGuid().ToString("N")[..12], Email = $"{Guid.NewGuid():N}@example.test",
            DisplayName = "Solo owner", PasswordHash = "fixture", RoleId = UserRoles.User, PlanId = plan.PlanId, Status = "active" };
        db.Users.Add(user); await db.SaveChangesAsync();
        db.PlanHistories.Add(new PlanHistory { UserId = user.UserId, OwnerUserId = user.UserId, PlanId = plan.PlanId });
        await db.SaveChangesAsync();
        var service = new PlanService(db, new TestEmails(), TimeProvider.System, new AuthOptions(), new RbacService(new RbacStore(db), new AuthStore(db)));
        var detail = (await service.GetMyPlanAsync(user.UserId))!;
        Assert.Empty(detail.Members);
        Assert.Null(detail.OwnerAllocatedStorage);
        var usage = Assert.Single(detail.StorageUsageBreakdown!);
        Assert.True(usage.IsOwner);
        Assert.Equal(user.UserId, usage.UserId);
        Assert.Equal(0, usage.StorageUsed);
        Assert.Equal(plan.StorageLimit, detail.RemainingStorage);
    }
}
