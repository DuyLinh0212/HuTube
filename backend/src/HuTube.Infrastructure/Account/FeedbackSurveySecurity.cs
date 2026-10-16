using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace HuTube.Infrastructure.Account;

public sealed class FeedbackSurveySecurity(FeedbackSurveyOptions options)
{
    public string CreateToken(Guid userId)
    {
        var id = userId.ToString("N");
        return id + "." + Convert.ToHexStringLower(Sign("hutube-feedback-v1:" + id));
    }

    public bool TryReadToken(string? token, out Guid userId)
    {
        userId = default;
        if (!options.IsConfigured || token is not { Length: 97 }
            || token[32] != '.' || !Guid.TryParseExact(token[..32], "N", out var id)) return false;
        if (!Matches(Sign("hutube-feedback-v1:" + id.ToString("N")), token[33..])) return false;
        userId = id;
        return true;
    }

    public bool VerifyWebhook(string body, string? timestamp, string? signature)
    {
        if (!options.IsConfigured || timestamp is not { Length: > 0 and <= 12 }
            || !long.TryParse(timestamp, NumberStyles.None, CultureInfo.InvariantCulture, out var seconds)
            || Math.Abs((double)DateTimeOffset.UtcNow.ToUnixTimeSeconds() - seconds) > 300
            || signature is not { Length: 71 } || !signature.StartsWith("sha256=", StringComparison.Ordinal)) return false;
        return Matches(Sign(timestamp + "." + body), signature[7..]);
    }

    private byte[] Sign(string value) => HMACSHA256.HashData(Encoding.UTF8.GetBytes(options.WebhookSecret), Encoding.UTF8.GetBytes(value));

    private static bool Matches(byte[] expected, string hex)
    {
        try { return CryptographicOperations.FixedTimeEquals(expected, Convert.FromHexString(hex)); }
        catch (FormatException) { return false; }
    }
}
