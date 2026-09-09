using HuTube.Domain.Channels;
using Xunit;

namespace HuTube.UnitTests;

public sealed class ChannelRulesTests
{
    [Theory]
    [InlineData("mychannel", true)]
    [InlineData("@mychannel", true)]
    [InlineData("tech_hub-99.vlog", true)]
    [InlineData("abc", true)]
    [InlineData("a", false)] // too short
    [InlineData("ab", false)] // too short
    [InlineData("", false)]
    [InlineData("   ", false)]
    [InlineData("chan nel", false)] // contains space
    [InlineData("channel!@#", false)] // special chars
    public void IsValidHandle_ValidatesCorrectly(string handle, bool expected)
    {
        var result = Channel.IsValidHandle(handle);
        Assert.Equal(expected, result);
    }

    [Theory]
    [InlineData("@MyChannel", "mychannel")]
    [InlineData("Hello_World", "hello_world")]
    [InlineData("  @CoolVlog  ", "coolvlog")]
    public void NormalizeHandle_NormalizesToLowercaseWithoutAtPrefix(string raw, string expected)
    {
        var result = Channel.NormalizeHandle(raw);
        Assert.Equal(expected, result);
    }

    [Fact]
    public void SoftDelete_SetsStatusToDeletedAndIsActiveFalse()
    {
        var channel = new Channel
        {
            Name = "Tech Corner",
            Handle = "techcorner",
            Status = "active"
        };

        Assert.True(channel.IsActive);

        var now = DateTimeOffset.UtcNow;
        channel.SoftDelete(now);

        Assert.Equal("deleted", channel.Status);
        Assert.False(channel.IsActive);
        Assert.Equal(now, channel.UpdatedAt);
    }
}
