namespace HuTube.Domain.Users;

public sealed class User
{
    public Guid UserId { get; set; } = Guid.NewGuid();
    public string Username { get; set; } = "";
    public string Email { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public string Status { get; set; } = "pending";
    public DateTimeOffset? EmailVerifiedAt { get; set; }
    public DateTimeOffset? LastLoginAt { get; set; }
    public int FailedLoginAttempts { get; set; }
    public DateTimeOffset? LockedUntil { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public DateTimeOffset? DeletedAt { get; set; }
    public bool IsBlocked => DeletedAt != null || Status is "suspended" or "banned" or "deleted";
}

public sealed class AuthIdentity
{
    public Guid AuthIdentityId { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Provider { get; set; } = "local";
    public string PasswordHash { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}

public sealed class UserSession
{
    public Guid SessionId { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string RefreshTokenHash { get; set; } = "";
    public Guid Jti { get; set; } = Guid.NewGuid();
    public string DeviceName { get; set; } = "";
    public string Platform { get; set; } = "web";
    public DateTimeOffset IssuedAt { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset LastActiveAt { get; set; }
    public DateTimeOffset? RevokedAt { get; set; }
    public string? RevokeReason { get; set; }
    public Guid? ReplacedBySessionId { get; set; }
    public bool IsActive(DateTimeOffset now) => RevokedAt == null && ExpiresAt > now;
    public void Revoke(DateTimeOffset now, string reason) { RevokedAt ??= now; RevokeReason ??= reason; }
}

public sealed class EmailVerificationToken
{
    public Guid EmailVerificationTokenId { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string TokenHash { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? UsedAt { get; set; }
}

public sealed class PasswordResetToken
{
    public Guid PasswordResetTokenId { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string TokenHash { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? UsedAt { get; set; }
}

public sealed class AdminAccount
{
    public Guid AdminAccountId { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Status { get; set; } = "active";
    public DateTimeOffset? DisabledAt { get; set; }
}
