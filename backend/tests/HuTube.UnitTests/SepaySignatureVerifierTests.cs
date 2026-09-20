using System.Security.Cryptography;
using System.Text;
using HuTube.Infrastructure.Payments;
using Xunit;

namespace HuTube.UnitTests;

public sealed class SepaySignatureVerifierTests
{
    [Fact]
    public void Verify_WhenSecretKeyIsEmpty_ReturnsTrue()
    {
        var options = new SepayOptions { SecretKey = "" };
        var verifier = new SepaySignatureVerifier(options);
        var rawBody = Encoding.UTF8.GetBytes("{\"test\":\"data\"}");

        var result = verifier.Verify(rawBody, "any-sig", null);

        Assert.True(result);
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
        var validSignature = Convert.ToHexString(hmac.ComputeHash(rawBody)).ToLowerInvariant();

        var result = verifier.Verify(rawBody, validSignature, null);

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
