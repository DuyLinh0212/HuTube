using HuTube.Application.Auth;
using HuTube.Application.Plans;
using HuTube.Domain.Plans;
using HuTube.Domain.Videos;
using HuTube.Domain.Users;
using HuTube.Infrastructure.Persistence;
using HuTube.Infrastructure.Plans;
using HuTube.Application.Rbac;
using Microsoft.EntityFrameworkCore;

namespace HuTube.UnitTests;

public sealed class UnavailablePlanSubscriptionTests
{
    [Theory]
    [InlineData("inactive")]
    [InlineData("archived")]
    [InlineData("missing")]
    public async Task SubscribeUnavailablePlan_ReturnsDomain404WithoutEntitlementMutation(string status)
    {
        using var db = new HuTubeDbContext(new DbContextOptionsBuilder<HuTubeDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var current = new Plan { PlanId = Guid.NewGuid(), Code = "free" };
        var unavailable = new Plan { PlanId = Guid.NewGuid(), Code = "unavailable", Status = status };
        var user = new User { Email = "qc-unavailable@example.test", PlanId = current.PlanId };
        db.Plans.Add(current);
        if (status != "missing") db.Plans.Add(unavailable);
        db.Users.Add(user);
        await db.SaveChangesAsync();
        var service = new PlanService(db, new Mail(), TimeProvider.System, new AuthOptions(),
            new RbacService(new RbacStore(db), new AuthStore(db)));

        var error = await Assert.ThrowsAsync<PlanException>(() =>
            service.SubscribeAsync(user.UserId, unavailable.PlanId, new PlanSubscriptionRequest()));

        Assert.Equal(404, error.Status);
        Assert.Equal("PLAN_NOT_FOUND", error.Code);
        Assert.Equal(current.PlanId, user.PlanId);
        Assert.Empty(db.PlanHistories);
        Assert.Empty(db.Payments);
    }

    private sealed class Mail : IAuthEmailSender
    {
        public Task SendAsync(string email, string subject, string body, CancellationToken ct) => Task.CompletedTask;
    }
}
