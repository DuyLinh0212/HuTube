using HuTube.Application.Auth;
using HuTube.Domain.Users;
using HuTube.Infrastructure.Authentication;

namespace HuTube.UnitTests;

public sealed class AuthRulesTests
{
    [Theory]
    [InlineData("bad")][InlineData("a@")][InlineData("@example.com")][InlineData("a b@example.com")]
    public void NormalizeEmail_InvalidEmail_ShouldReject(string value) => Assert.Throws<AuthException>(() => AuthRules.NormalizeEmail(value));
    [Fact]
    public void NormalizeEmail_MixedCase_ShouldNormalize() => Assert.Equal("user@example.com", AuthRules.NormalizeEmail(" User@Example.com "));
    [Theory]
    [InlineData("short")][InlineData("alllowercase1")][InlineData("ALLUPPERCASE1")][InlineData("NoDigitsHere")]
    public void ValidatePassword_WeakPassword_ShouldReject(string value) => Assert.Throws<AuthException>(() => AuthRules.ValidatePassword(value));
    [Fact]
    public void ValidatePassword_TooLong_ShouldReject() => Assert.Throws<AuthException>(() => AuthRules.ValidatePassword("Ab1" + new string('x', 126)));
    [Fact]
    public void ValidatePassword_Valid_ShouldAccept() => AuthRules.ValidatePassword("CorrectHorse42!");
    [Theory]
    [InlineData("suspended")][InlineData("banned")][InlineData("deleted")]
    public void IsBlocked_RestrictedAccount_ShouldBlock(string status) => Assert.True(new User { Status = status }.IsBlocked);
    [Fact]
    public void IsBlocked_SoftDeleted_ShouldBlock() => Assert.True(new User { Status = "active", DeletedAt = DateTimeOffset.UtcNow }.IsBlocked);
    [Fact]
    public void IsActive_ExpiredSession_ShouldReject() => Assert.False(new UserSession { ExpiresAt = DateTimeOffset.UtcNow.AddSeconds(-1) }.IsActive(DateTimeOffset.UtcNow));
    [Fact]
    public void Revoke_Repeated_ShouldPreserveFirstReason()
    {
        var now = DateTimeOffset.UtcNow;
        var session = new UserSession { ExpiresAt = now.AddDays(1) };
        session.Revoke(now, "logout"); session.Revoke(now.AddMinutes(1), "other");
        Assert.Equal(now, session.RevokedAt); Assert.Equal("logout", session.RevokeReason); Assert.False(session.IsActive(now));
    }
    [Fact]
    public void Hash_Password_ShouldUseRandomSaltAndVerify()
    {
        var service = new PasswordService(); var hash = service.Hash("StrongPassword42");
        Assert.NotEqual(hash, service.Hash("StrongPassword42")); Assert.DoesNotContain("StrongPassword42", hash);
        Assert.True(service.Verify("StrongPassword42", hash)); Assert.False(service.Verify("wrong", hash));
        Assert.False(service.Verify("wrong", "invalid hash"));
    }
    [Fact]
    public void CreateOpaqueToken_Repeated_ShouldBeUniqueAndStoreOnlyHash()
    {
        var service = new TokenService(new(), new(), TimeProvider.System);
        var token = service.CreateOpaqueToken();
        Assert.Equal(64, token.Length); Assert.NotEqual(token, service.CreateOpaqueToken());
        Assert.NotEqual(token, service.HashToken(token)); Assert.Equal(service.HashToken(token), service.HashToken(token));
    }
}
