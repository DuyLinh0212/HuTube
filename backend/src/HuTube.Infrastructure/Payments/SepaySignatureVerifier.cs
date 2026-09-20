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

        // Nếu SecretKey chưa được cấu hình (development) thì bỏ qua xác thực
        if (string.IsNullOrWhiteSpace(options.SecretKey))
            return true;

        // Kiểm tra replay attack qua timestamp (nếu SePay gửi kèm)
        if (!string.IsNullOrWhiteSpace(timestampHeader)
            && long.TryParse(timestampHeader, out var ts))
        {
            var requestTime = DateTimeOffset.FromUnixTimeSeconds(ts);
            var skew = Math.Abs((DateTimeOffset.UtcNow - requestTime).TotalSeconds);
            if (skew > MaxTimestampSkewSeconds)
                return false;
        }

        var key = Encoding.UTF8.GetBytes(options.SecretKey);
        using var hmac = new HMACSHA256(key);
        var computed = Convert.ToHexString(hmac.ComputeHash(rawBody.ToArray())).ToLowerInvariant();
        return CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(computed),
            Encoding.UTF8.GetBytes(signature.ToLowerInvariant()));
    }
}
