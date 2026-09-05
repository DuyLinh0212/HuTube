using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using HuTube.Application.Auth;
using HuTube.Domain.Users;
using Microsoft.IdentityModel.Tokens;

namespace HuTube.Infrastructure.Authentication;

public sealed class JwtOptions
{
    public string SigningKey { get; set; } = "";
    public string Issuer { get; set; } = "HuTube";
    public string Audience { get; set; } = "HuTube.Clients";
}
public sealed class TokenService(JwtOptions jwt, AuthOptions auth, TimeProvider clock) : ITokenService
{
    public string CreateOpaqueToken() => Base64UrlEncoder.Encode(RandomNumberGenerator.GetBytes(48));
    public string HashToken(string token) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));
    public (string Token, DateTimeOffset ExpiresAt) CreateAccessToken(User user, UserSession session)
    {
        var now = clock.GetUtcNow();
        var expiry = now.AddMinutes(auth.AccessTokenMinutes);
        if (expiry > session.ExpiresAt) expiry = session.ExpiresAt;
        var claims = new[] { new Claim("sub", user.UserId.ToString()), new Claim("sid", session.SessionId.ToString()), new Claim("jti", session.Jti.ToString()) };
        var token = new JwtSecurityToken(jwt.Issuer, jwt.Audience, claims, now.UtcDateTime, expiry.UtcDateTime,
            new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.SigningKey)), SecurityAlgorithms.HmacSha256));
        return (new JwtSecurityTokenHandler().WriteToken(token), expiry);
    }
}
