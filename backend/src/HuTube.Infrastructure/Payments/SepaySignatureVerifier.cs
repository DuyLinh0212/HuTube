using System.Security.Cryptography;
using System.Text;

namespace HuTube.Infrastructure.Payments;

/// <summary>
/// Xác thực chữ ký HMAC-SHA256 từ webhook SePay.
/// Header X-SePay-Signature chứa chữ ký; X-SePay-Timestamp chứa Unix timestamp.
/// </summary>
public sealed class SepaySignatureVerifier(SepayOptions options)
{
    private const int MaxTimestampSkewSeconds = 300; // 5 phút

    /// <summary>
    /// Xác thực request webhook từ SePay.
    /// </summary>
    /// <param name="rawBody">Raw request body bytes (đọc trước khi middleware đọc).</param>
    /// <param name="signature">Giá trị header X-SePay-Signature.</param>
    /// <param name="timestampHeader">Giá trị header X-SePay-Timestamp (Unix seconds, nullable).</param>
    /// <returns>true nếu hợp lệ.</returns>
    public bool Verify(ReadOnlySpan<byte> rawBody, string? signature, string? timestampHeader)
    {
        if (string.IsNullOrWhiteSpace(signature))
            return false;

        if (string.IsNullOrWhiteSpace(options.SecretKey))
            return false;

        if (!long.TryParse(timestampHeader, out var ts)
            || Math.Abs((double)DateTimeOffset.UtcNow.ToUnixTimeSeconds() - ts) > MaxTimestampSkewSeconds
            || !signature.StartsWith("sha256=", StringComparison.Ordinal)
            || signature.Length != 71)
            return false;

        byte[] supplied;
        try { supplied = Convert.FromHexString(signature[7..]); }
        catch (FormatException) { return false; }

        var key = Encoding.UTF8.GetBytes(options.SecretKey);
        using var hmac = new HMACSHA256(key);
        var prefix = Encoding.UTF8.GetBytes(timestampHeader + ".");
        var signed = new byte[prefix.Length + rawBody.Length];
        prefix.CopyTo(signed, 0);
        rawBody.CopyTo(signed.AsSpan(prefix.Length));
        return CryptographicOperations.FixedTimeEquals(hmac.ComputeHash(signed), supplied);
    }
}
