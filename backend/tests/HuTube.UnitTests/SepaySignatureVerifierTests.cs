using System.Security.Cryptography;
using System.Text;
using HuTube.Infrastructure.Payments;
using Xunit;

namespace HuTube.UnitTests;

public sealed class SepaySignatureVerifierTests
{
    [Theory]
    [InlineData(null)]
    [InlineData("invalid")]
    [InlineData("9223372036854775807")]
    [InlineData("-9223372036854775808")]
    public void Verify_WhenTimestampMalformedOrOutsideWindow_RejectsWithoutThrowing(string? timestamp)
    {
        var verifier = new SepaySignatureVerifier(new SepayOptions { SecretKey = "test-secret" });
        Assert.False(verifier.Verify(Encoding.UTF8.GetBytes("{}"), "sha256=" + new string('0', 64), timestamp));
    }

    [Fact]
    public void Verify_WhenSecretKeyIsEmpty_ReturnsFalse()
    {
        var options = new SepayOptions { SecretKey = "" };
        var verifier = new SepaySignatureVerifier(options);
        var rawBody = Encoding.UTF8.GetBytes("{\"test\":\"data\"}");

        var result = verifier.Verify(rawBody, "any-sig", null);

        Assert.False(result);
    }

    [Fact]
    public void Verify_WhenSignatureIsNull_ReturnsFalse()
    {
        var options = new SepayOptions { SecretKey = "secret123" };
        var verifier = new SepaySignatureVerifier(options);
        var rawBody = Encoding.UTF8.GetBytes("{\"test\":\"data\"}");

        var result = verifier.Verify(rawBody, null, null);

        Assert.False(result);
    }

    [Fact]
    public void Verify_WhenValidSignature_ReturnsTrue()
    {
        var secret = "my_sepay_secret_key_123";
        var options = new SepayOptions { SecretKey = secret };
        var verifier = new SepaySignatureVerifier(options);
        var bodyString = "{\"id\":12345,\"transferAmount\":99000}";
        var rawBody = Encoding.UTF8.GetBytes(bodyString);

        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
        var validSignature = "sha256=" + Convert.ToHexString(hmac.ComputeHash(Encoding.UTF8.GetBytes(timestamp + "." + bodyString))).ToLowerInvariant();

        var result = verifier.Verify(rawBody, validSignature, timestamp);

        Assert.True(result);
    }

    [Fact]
    public void Verify_WhenInvalidSignature_ReturnsFalse()
    {
        var secret = "my_sepay_secret_key_123";
        var options = new SepayOptions { SecretKey = secret };
        var verifier = new SepaySignatureVerifier(options);
        var bodyString = "{\"id\":12345,\"transferAmount\":99000}";
        var rawBody = Encoding.UTF8.GetBytes(bodyString);

        var result = verifier.Verify(rawBody, "invalid_hex_signature", null);

        Assert.False(result);
    }

    [Fact]
    public void Verify_WhenTimestampTooOld_ReturnsFalse()
    {
        var secret = "my_sepay_secret_key_123";
        var options = new SepayOptions { SecretKey = secret };
        var verifier = new SepaySignatureVerifier(options);
        var bodyString = "{\"id\":12345,\"transferAmount\":99000}";
        var rawBody = Encoding.UTF8.GetBytes(bodyString);

        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
        var validSignature = Convert.ToHexString(hmac.ComputeHash(rawBody)).ToLowerInvariant();

        // Timestamp 10 phút trước (quá giới hạn 5 phút)
        var oldTimestamp = DateTimeOffset.UtcNow.AddMinutes(-10).ToUnixTimeSeconds().ToString();

        var result = verifier.Verify(rawBody, validSignature, oldTimestamp);

        Assert.False(result);
    }
}
