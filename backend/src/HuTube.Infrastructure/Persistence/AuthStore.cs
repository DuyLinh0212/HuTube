using HuTube.Application.Auth;
using HuTube.Domain.Users;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Npgsql;

namespace HuTube.Infrastructure.Persistence;

public sealed class AuthStore(HuTubeDbContext db) : IAuthStore
{
    public async Task<IAuthTransaction> LockUserAsync(Guid userId, CancellationToken ct)
    {
        db.ChangeTracker.Clear();
        var transaction = await db.Database.BeginTransactionAsync(ct);
        try
        {
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({userId.ToString()}, 0))", ct);
            return new AuthTransaction(transaction);
        }
        catch { await transaction.DisposeAsync(); throw; }
    }

    public Task<User?> FindUserByEmailAsync(string email, CancellationToken ct) => db.Users.SingleOrDefaultAsync(x => x.Email == email, ct);
    public Task<User?> FindUserByGoogleSubjectAsync(string subject, CancellationToken ct) => db.Users.SingleOrDefaultAsync(x => x.GoogleSubject == subject, ct);
    public Task<User?> FindUserAsync(Guid id, CancellationToken ct) => db.Users.SingleOrDefaultAsync(x => x.UserId == id, ct);
    public Task<bool> UsernameExistsAsync(string username, CancellationToken ct) => db.Users.AnyAsync(x => x.Username == username, ct);
    public Task<string?> FindPasswordHashAsync(Guid userId, CancellationToken ct) => db.Users.Where(x => x.UserId == userId).Select(x => x.PasswordHash).SingleOrDefaultAsync(ct);
    public Task<UserSession?> FindSessionByHashAsync(string hash, CancellationToken ct) => db.Sessions.SingleOrDefaultAsync(x => x.RefreshTokenHash == hash, ct);
    public Task<UserSession?> FindSessionAsync(Guid id, CancellationToken ct) => db.Sessions.SingleOrDefaultAsync(x => x.SessionId == id, ct);
    public Task<List<UserSession>> GetSessionsAsync(Guid userId, CancellationToken ct) => db.Sessions.Where(x => x.UserId == userId).ToListAsync(ct);
    public Task<List<UserSession>> GetActiveSessionsAsync(Guid userId, DateTimeOffset now, CancellationToken ct) =>
        db.Sessions.Where(x => x.UserId == userId && x.RevokedAt == null && x.ExpiresAt > now).OrderByDescending(x => x.IssuedAt).ToListAsync(ct);
    public async Task TouchSessionAsync(Guid sessionId, DateTimeOffset now, CancellationToken ct) =>
        await db.Sessions.Where(x => x.SessionId == sessionId && x.RevokedAt == null && x.LastActiveAt < now.AddMinutes(-1))
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.LastActiveAt, now), ct);

    public async Task<EmailVerificationToken?> FindVerificationAsync(string hash, CancellationToken ct)
    {
        var user = await db.Users.SingleOrDefaultAsync(x => x.EmailVerificationTokenHash == hash, ct);
        return user == null ? null : new EmailVerificationToken { UserId = user.UserId, TokenHash = hash,
            CreatedAt = user.EmailVerificationCreatedAt ?? DateTimeOffset.MinValue,
            ExpiresAt = user.EmailVerificationExpiresAt ?? DateTimeOffset.MinValue, UsedAt = user.EmailVerificationUsedAt };
    }

    public async Task<PasswordResetToken?> FindResetAsync(string hash, CancellationToken ct)
    {
        var user = await db.Users.SingleOrDefaultAsync(x => x.PasswordResetTokenHash == hash, ct);
        return user == null ? null : new PasswordResetToken { UserId = user.UserId, TokenHash = hash,
            CreatedAt = user.PasswordResetCreatedAt ?? DateTimeOffset.MinValue,
            ExpiresAt = user.PasswordResetExpiresAt ?? DateTimeOffset.MinValue, UsedAt = user.PasswordResetUsedAt };
    }

    public Task<bool> IsAdminAsync(Guid userId, CancellationToken ct) =>
        db.Users.Where(u => u.UserId == userId).Join(db.Roles, u => u.RoleId, r => r.RoleId,
            (_, r) => r.Code == "admin" && r.Status == "active").SingleOrDefaultAsync(ct);

    public void AddUser(User user, string passwordHash)
    {
        user.PasswordHash = passwordHash;
        user.RoleId = UserRoles.User;
        db.Users.Add(user);
    }

    public void AddSession(UserSession session) => db.Sessions.Add(session);

    public void AddVerification(User user, EmailVerificationToken token)
    {
        user.EmailVerificationTokenHash = token.TokenHash; user.EmailVerificationCreatedAt = token.CreatedAt;
        user.EmailVerificationExpiresAt = token.ExpiresAt; user.EmailVerificationUsedAt = null;
    }

    public void AddReset(User user, PasswordResetToken token)
    {
        user.PasswordResetTokenHash = token.TokenHash; user.PasswordResetCreatedAt = token.CreatedAt;
        user.PasswordResetExpiresAt = token.ExpiresAt; user.PasswordResetUsedAt = null;
    }

    public async Task InvalidateTokensAsync(Guid userId, bool reset, DateTimeOffset now, CancellationToken ct)
    {
        var user = await db.Users.SingleOrDefaultAsync(u => u.UserId == userId, ct);
        if (user is null) return;
        if (reset && user.PasswordResetTokenHash is not null) user.PasswordResetUsedAt = now;
        if (!reset && user.EmailVerificationTokenHash is not null) user.EmailVerificationUsedAt = now;
    }

    public async Task SaveAsync(CancellationToken ct)
    {
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateException ex) when (ex.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation } pg)
        {
            throw pg.ConstraintName switch {
                "ux_users_email_ci" => new AuthException(409, "EMAIL_ALREADY_EXISTS", "Email đã được sử dụng."),
                "ux_users_username_ci" => new AuthException(409, "USERNAME_ALREADY_EXISTS", "Tên người dùng đã được sử dụng."),
                _ => new AuthException(409, "RESOURCE_CONFLICT", "Dữ liệu đã thay đổi. Vui lòng thử lại.")
            };
        }
    }

    private sealed class AuthTransaction(IDbContextTransaction transaction) : IAuthTransaction
    {
        public Task CommitAsync(CancellationToken ct) => transaction.CommitAsync(ct);
        public ValueTask DisposeAsync() => transaction.DisposeAsync();
    }
}
