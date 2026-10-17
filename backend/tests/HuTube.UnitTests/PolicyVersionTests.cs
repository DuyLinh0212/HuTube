using HuTube.Application.Auth;
using HuTube.Application.Policies;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using HuTube.Infrastructure.Policies;
using Microsoft.EntityFrameworkCore;

namespace HuTube.UnitTests;

public sealed class PolicyVersionTests
{
    [Fact]
    public async Task PublishedVersion_KeepsOriginalEvidence_AndOnlyLatestIsPublic()
    {
        using var db = new HuTubeDbContext(new DbContextOptionsBuilder<HuTubeDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var original = new Policy { Code = "TEST", Name = "Original", Content = "Original evidence", Version = "1.0", EffectiveAt = DateTimeOffset.UtcNow.AddDays(-1) };
        db.Policies.Add(original); await db.SaveChangesAsync();
        var service = new PolicyService(db);
        var next = await service.PublishPolicyVersionAsync(Guid.NewGuid(), original.PolicyId,
            new UpdatePolicyRequest("Current", "content", "Current evidence", "high", "published", "1.1"));
        Assert.NotEqual(original.PolicyId, next.PolicyId);
        var historical = await db.Policies.SingleAsync(p => p.PolicyId == original.PolicyId);
        Assert.Equal("Original evidence", historical.Content);
        Assert.Equal("1.0", historical.Version);
        Assert.Equal(2, (await service.GetAdminPoliciesAsync()).Count);
        Assert.Equal(next.PolicyId, Assert.Single(await service.GetPublicPoliciesAsync()).PolicyId);
        var duplicate = await Assert.ThrowsAsync<AuthException>(() => service.PublishPolicyVersionAsync(Guid.NewGuid(), original.PolicyId,
            new UpdatePolicyRequest("Overwrite", "content", "Overwrite", "high", "published", "1.1")));
        Assert.Equal(409, duplicate.Status);
        Assert.Equal(2, await db.Policies.CountAsync());
    }
}
