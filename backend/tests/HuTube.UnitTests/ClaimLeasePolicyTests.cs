using HuTube.Application.Auth;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Videos;
using Xunit;

namespace HuTube.UnitTests;

public sealed class ClaimLeasePolicyTests
{
    private static readonly DateTimeOffset Start = new(2026, 10, 16, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void FirstClaimUsesDatabaseMicrosecondPrecisionWithoutExtendingDuration()
    {
        var now = Start.AddTicks(17); var item = new ModerationCase();
        ClaimLeasePolicy.Assign(item, Guid.NewGuid(), now);
        Assert.Equal(Start.AddTicks(10), item.ClaimedAt);
        Assert.Equal(Start.AddMinutes(15).AddTicks(10), item.ClaimExpiresAt);
        Assert.Equal(0, item.ClaimExpiresAt!.Value.UtcTicks % 10);
    }

    [Theory]
    [InlineData(-1, true)]
    [InlineData(0, false)]
    [InlineData(1, false)]
    public void ClaimExpiresExactlyAtFifteenMinutes(long ticksAfterDeadline, bool allowed)
    {
        var actor = Guid.NewGuid(); var item = new ModerationCase();
        ClaimLeasePolicy.Assign(item, actor, Start);
        var now = Start.AddMinutes(15).AddTicks(ticksAfterDeadline);
        Assert.Equal(Start.AddMinutes(15), item.ClaimExpiresAt);
        if (allowed) ClaimLeasePolicy.Ensure(item, actor, item.ClaimId, now);
        else Assert.Equal("CLAIM_EXPIRED", Assert.Throws<AuthException>(() => ClaimLeasePolicy.Ensure(item, actor, item.ClaimId, now)).Code);
    }

    [Fact]
    public void IdempotentClaimDoesNotRenewAndAnotherReviewerCannotSteal()
    {
        var actor = Guid.NewGuid(); var item = new ModerationCase();
        ClaimLeasePolicy.Assign(item, actor, Start); var token = item.ClaimId;
        ClaimLeasePolicy.Assign(item, actor, Start.AddMinutes(14));
        Assert.Equal(token, item.ClaimId); Assert.Equal(Start.AddMinutes(15), item.ClaimExpiresAt);
        Assert.Equal(409, Assert.Throws<AuthException>(() => ClaimLeasePolicy.Assign(item, Guid.NewGuid(), Start.AddMinutes(14))).Status);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void ReclaimRotatesTokenAndStaleBrowserCannotReleaseOrResolve(bool sameReviewer)
    {
        var actor = Guid.NewGuid(); var item = new Appeal();
        ClaimLeasePolicy.Assign(item, actor, Start); var old = item.ClaimId;
        var nextActor = sameReviewer ? actor : Guid.NewGuid();
        ClaimLeasePolicy.Assign(item, nextActor, Start.AddMinutes(15));
        Assert.NotEqual(old, item.ClaimId);
        Assert.Equal("CLAIM_STALE", Assert.Throws<AuthException>(() => ClaimLeasePolicy.Ensure(item, actor, old, Start.AddMinutes(16))).Code);
        ClaimLeasePolicy.Ensure(item, nextActor, item.ClaimId, Start.AddMinutes(16));
        ClaimLeasePolicy.Release(item); Assert.Null(item.ClaimId); Assert.Null(item.ReviewerId); Assert.Equal("pending", item.Status);
    }

    [Fact]
    public void ClosedCaseAndLegacyUnleasedCaseCannotBeResolved()
    {
        var item = new ModerationCase { Status = "approved" };
        Assert.Throws<AuthException>(() => ClaimLeasePolicy.Assign(item, Guid.NewGuid(), Start));
        item.Status = "reviewing"; item.ReviewerId = Guid.NewGuid();
        Assert.Equal("CLAIM_REQUIRED", Assert.Throws<AuthException>(() => ClaimLeasePolicy.Ensure(item, item.ReviewerId.Value, null, Start)).Code);
    }

    [Fact]
    public void UnresolvedEscalationRequiresANewLeaseButClosedReportCannotReopen()
    {
        var actor = Guid.NewGuid();
        var item = new ModerationCase { Status = "pending", CaseType = "upload_review" };
        ClaimLeasePolicy.Assign(item, actor, Start); var old = item.ClaimId;
        item.Status = "escalated";
        Assert.Throws<AuthException>(() => ClaimLeasePolicy.Ensure(item, actor, old, Start.AddMinutes(1)));
        ClaimLeasePolicy.Assign(item, actor, Start.AddMinutes(1)); Assert.NotEqual(old, item.ClaimId);
        var appeal = new Appeal { Status = "escalated" }; ClaimLeasePolicy.Assign(appeal, actor, Start);
        var report = new ModerationCase { CaseType = "report_case", Status = "escalated", ResolvedAt = Start };
        Assert.Throws<AuthException>(() => ClaimLeasePolicy.Assign(report, actor, Start));
    }
}
