using HuTube.Domain.Channels;
using HuTube.Domain.Plans;

namespace HuTube.UnitTests;

public sealed class PlanEntitlementTests
{
    [Fact]
    public void ReadFlags_ShouldReturnOnlyBooleanEntitlements()
    {
        var flags = PlanEntitlementRules.ReadFlags("{\"download\":true,\"background_play\":false,\"label\":\"Creator\"}");

        Assert.True(flags[PlanEntitlementRules.Download]);
        Assert.False(flags[PlanEntitlementRules.BackgroundPlay]);
        Assert.DoesNotContain("label", flags.Keys);
    }

    [Fact]
    public void ReadFlags_ShouldNormalizeEntitlementKeys()
    {
        var flags = PlanEntitlementRules.ReadFlags("{\"DOWNLOAD\":true}");

        Assert.True(PlanEntitlementRules.IsEnabled("{\"DOWNLOAD\":true}", PlanEntitlementRules.Download));
        Assert.True(flags[PlanEntitlementRules.Download]);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("[]")]
    [InlineData("not-json")]
    public void ReadFlags_ShouldFailClosedForInvalidOrNonObjectJson(string? json)
    {
        var flags = PlanEntitlementRules.ReadFlags(json);

        Assert.Empty(flags);
        Assert.False(PlanEntitlementRules.IsEnabled(json, PlanEntitlementRules.Download));
    }

    [Fact]
    public void CanReserve_ShouldAvoidOverflowAndRejectInvalidCounters()
    {
        Assert.False(ChannelQuotaRules.CanReserve(long.MaxValue, 1, long.MaxValue));
        Assert.False(ChannelQuotaRules.CanReserve(-1, 1, 100));
        Assert.False(ChannelQuotaRules.CanReserve(1, -1, 100));
        Assert.False(ChannelQuotaRules.CanReserve(101, 0, 100));
    }
}
