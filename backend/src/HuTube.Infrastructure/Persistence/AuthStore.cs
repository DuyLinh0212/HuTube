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
            // PostgreSQL transaction lock makes refresh/reset/revoke atomic across API instances.
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({userId.ToString()}, 0))", ct);
            return new AuthTransaction(transaction);
        }
        catch { await transaction.DisposeAsync(); throw; }
    }
    public Task<User?> FindUserByEmailAsync(string email, CancellationToken ct) => db.Users.SingleOrDefaultAsync(x => x.Email == email, ct);
    public Task<User?> FindUserAsync(Guid id, CancellationToken ct) => db.Users.SingleOrDefaultAsync(x => x.UserId == id, ct);
    public Task<bool> UsernameExistsAsync(string username, CancellationToken ct) => db.Users.AnyAsync(x => x.Username == username, ct);
    public Task<AuthIdentity?> FindIdentityAsync(Guid userId, CancellationToken ct) => db.Identities.SingleOrDefaultAsync(x => x.UserId == userId && x.Provider == "local", ct);
    public Task<UserSession?> FindSessionByHashAsync(string hash, CancellationToken ct) => db.Sessions.SingleOrDefaultAsync(x => x.RefreshTokenHash == hash, ct);
    public Task<UserSession?> FindSessionAsync(Guid id, CancellationToken ct) => db.Sessions.SingleOrDefaultAsync(x => x.SessionId == id, ct);
    public Task<List<UserSession>> GetSessionsAsync(Guid userId, CancellationToken ct) => db.Sessions.Where(x => x.UserId == userId).ToListAsync(ct);
    public Task<List<UserSession>> GetActiveSessionsAsync(Guid userId, DateTimeOffset now, CancellationToken ct) =>
        db.Sessions.Where(x => x.UserId == userId && x.RevokedAt == null && x.ExpiresAt > now).OrderByDescending(x => x.IssuedAt).ToListAsync(ct);
    public async Task TouchSessionAsync(Guid sessionId, DateTimeOffset now, CancellationToken ct) =>
        await db.Sessions.Where(x => x.SessionId == sessionId && x.RevokedAt == null && x.LastActiveAt < now.AddMinutes(-1))
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.LastActiveAt, now), ct);
    public Task<EmailVerificationToken?> FindVerificationAsync(string hash, CancellationToken ct) => db.VerificationTokens.SingleOrDefaultAsync(x => x.TokenHash == hash, ct);
    public Task<PasswordResetToken?> FindResetAsync(string hash, CancellationToken ct) => db.ResetTokens.SingleOrDefaultAsync(x => x.TokenHash == hash, ct);
    public Task<bool> IsAdminAsync(Guid userId, CancellationToken ct) => db.AdminAccounts.AnyAsync(x => x.UserId == userId && x.Status == "active" && x.DisabledAt == null, ct);
    public void AddUser(User user, AuthIdentity identity) { db.Users.Add(user); db.Identities.Add(identity); }
    public void AddSession(UserSession session) => db.Sessions.Add(session);
    public void AddVerification(EmailVerificationToken token) => db.VerificationTokens.Add(token);
    public void AddReset(PasswordResetToken token) => db.ResetTokens.Add(token);
    public async Task InvalidateTokensAsync(Guid userId, bool reset, DateTimeOffset now, CancellationToken ct)
    {
        if (reset) await db.ResetTokens.Where(t => t.UserId == userId && t.UsedAt == null).ExecuteUpdateAsync(s => s.SetProperty(t => t.UsedAt, now), ct);
        else await db.VerificationTokens.Where(t => t.UserId == userId && t.UsedAt == null).ExecuteUpdateAsync(s => s.SetProperty(t => t.UsedAt, now), ct);
    }
    public async Task SaveAsync(CancellationToken ct)
    {
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateException ex) when (ex.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation } pg)
        {
            throw pg.ConstraintName switch {
                "ux_users_email_active" => new AuthException(409, "EMAIL_ALREADY_EXISTS", "Email đã được sử dụng."),
                "ux_users_username_active" => new AuthException(409, "USERNAME_ALREADY_EXISTS", "Tên người dùng đã được sử dụng."),
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
