using System.Security.Cryptography;
using System.Text;
using HuTube.Infrastructure.Account;

namespace HuTube.UnitTests;

public sealed class FeedbackSurveySecurityTests
{
    private const string Secret = "hutube-survey-tests-secret-at-least-32-characters";
    private static FeedbackSurveySecurity Security(string secret = Secret) => new(new FeedbackSurveyOptions { TokenEntryId = "123", WebhookSecret = secret });

    [Fact]
    public void AccountToken_BindsToItsAccountAndRejectsTampering()
    {
        var security = Security();
        var userId = Guid.NewGuid();
        var token = security.CreateToken(userId);
        Assert.True(security.TryReadToken(token, out var actual));
        Assert.Equal(userId, actual);
        Assert.False(security.TryReadToken(Guid.NewGuid().ToString("N") + token[32..], out _));
        Assert.False(Security(Secret + "changed").TryReadToken(token, out _));
        Assert.False(security.TryReadToken(token[..33] + new string('x', 64), out _));
        Assert.False(security.TryReadToken(null, out _));
    }

    [Fact]
    public void Webhook_RequiresFreshTimestampAndExactUtf8Payload()
    {
        var security = Security();
        var body = "{\"message\":\"Cảm ơn bạn\"}";
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
        var signature = Sign(timestamp, body);
        Assert.True(security.VerifyWebhook(body, timestamp, signature));
        Assert.False(security.VerifyWebhook(body + " ", timestamp, signature));
        Assert.False(security.VerifyWebhook(body, DateTimeOffset.UtcNow.AddMinutes(-10).ToUnixTimeSeconds().ToString(), signature));
        Assert.False(security.VerifyWebhook(body, DateTimeOffset.UtcNow.AddMinutes(10).ToUnixTimeSeconds().ToString(), signature));
        Assert.False(security.VerifyWebhook(body, "9223372036854775807", signature));
        Assert.False(security.VerifyWebhook(body, null, signature));
        Assert.False(security.VerifyWebhook(body, timestamp, "sha256=" + new string('x', 64)));
        Assert.False(Security("").VerifyWebhook(body, timestamp, signature));
    }

    private static string Sign(string timestamp, string body) => "sha256=" + Convert.ToHexStringLower(
        HMACSHA256.HashData(Encoding.UTF8.GetBytes(Secret), Encoding.UTF8.GetBytes(timestamp + "." + body)));
}
