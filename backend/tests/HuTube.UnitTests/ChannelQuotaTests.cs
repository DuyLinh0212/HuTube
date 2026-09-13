using HuTube.Domain.Channels;
using Xunit;

namespace HuTube.UnitTests;

public sealed class ChannelQuotaTests
{
    [Fact]
    public void CanReserve_ShouldRejectWhenUploadWouldExceedLimit()
    {
        var result = ChannelQuotaRules.CanReserve(900L * 1024 * 1024, 200L * 1024 * 1024, 1L * 1024 * 1024 * 1024);
        Assert.False(result);
    }

    [Fact]
    public void CanReserve_ShouldAllowExactLimitBoundary()
    {
        var result = ChannelQuotaRules.CanReserve(500L * 1024 * 1024, 500L * 1024 * 1024, 1L * 1024 * 1024 * 1024);
        Assert.True(result);
    }

    [Fact]
    public void Remaining_ShouldNeverGoNegative()
    {
        var result = ChannelQuotaRules.Remaining(2L * 1024 * 1024 * 1024, 3L * 1024 * 1024 * 1024);
        Assert.Equal(0L, result);
    }
}
