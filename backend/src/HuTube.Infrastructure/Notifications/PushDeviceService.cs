using System.Security.Cryptography;
using System.Text;
using HuTube.Application.Auth;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Notifications;

public sealed record RegisterPushDeviceRequest(string Token, string Platform);
public sealed record RemovePushDeviceRequest(string Token);

public sealed class PushDeviceService(HuTubeDbContext db, TimeProvider clock)
{
    public async Task RegisterAsync(Guid userId, Guid sessionId, RegisterPushDeviceRequest request, CancellationToken ct)
    {
        var token = ValidateToken(request.Token);
        var platform = request.Platform?.Trim().ToLowerInvariant();
        if (platform is not ("android" or "ios")) throw new AuthException(400, "INVALID_PUSH_PLATFORM", "Nền tảng thông báo không hợp lệ.");
        var now = clock.GetUtcNow();
        if (!await db.Sessions.AnyAsync(session => session.SessionId == sessionId && session.UserId == userId
            && session.RevokedAt == null && session.ExpiresAt > now, ct))
            throw new AuthException(401, "SESSION_REVOKED", "Phiên đăng nhập không còn hiệu lực.");
        var hash = Hash(token);
        await db.Database.ExecuteSqlInterpolatedAsync($"""
            INSERT INTO push_devices (push_device_id, user_id, session_id, token, token_hash, platform, updated_at)
            VALUES ({Guid.NewGuid()}, {userId}, {sessionId}, {token}, {hash}, {platform}, {now})
            ON CONFLICT (token_hash) DO UPDATE SET user_id = EXCLUDED.user_id, session_id = EXCLUDED.session_id,
                token = EXCLUDED.token, platform = EXCLUDED.platform, updated_at = EXCLUDED.updated_at
            """, ct);
    }

    public Task RemoveAsync(Guid userId, Guid sessionId, string token, CancellationToken ct) =>
        db.PushDevices.Where(device => device.UserId == userId && device.SessionId == sessionId && device.TokenHash == Hash(ValidateToken(token)))
            .ExecuteDeleteAsync(ct);

    private static string ValidateToken(string? token)
    {
        token = token?.Trim();
        if (string.IsNullOrEmpty(token) || token.Length > 4096 || token.Any(char.IsWhiteSpace))
            throw new AuthException(400, "INVALID_PUSH_TOKEN", "Mã đăng ký thông báo không hợp lệ.");
        return token;
    }
    private static string Hash(string token) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));
}
