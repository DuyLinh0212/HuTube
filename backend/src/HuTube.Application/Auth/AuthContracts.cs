using System.ComponentModel.DataAnnotations;
using HuTube.Domain.Users;

namespace HuTube.Application.Auth;

public sealed record RegisterRequest(
    [Required, RegularExpression(@"^[a-zA-Z0-9_.-]{3,50}$")] string Username,
    [Required, EmailAddress, StringLength(254)] string Email,
    [Required, StringLength(120, MinimumLength = 1)] string DisplayName,
    [Required, StringLength(128, MinimumLength = 10)] string Password);
public sealed record LoginRequest(
    [Required, EmailAddress, StringLength(254)] string Email,
    [Required, StringLength(128)] string Password,
    [RegularExpression("^(web|mobile|admin)$")] string Platform = "web",
    [StringLength(200)] string DeviceName = "Unknown device");
public sealed record EmailRequest([Required, EmailAddress, StringLength(254)] string Email);
public sealed record TokenRequest([Required, StringLength(256)] string Token);
public sealed record ResetPasswordRequest([Required, StringLength(256)] string Token,
    [Required, StringLength(128, MinimumLength = 10)] string Password);
public sealed record RefreshRequest([StringLength(256)] string? RefreshToken = null);
public sealed record MessageResponse(string Message);
public sealed record UserResponse(Guid UserId, string Username, string Email, string DisplayName, bool EmailVerified, bool IsAdmin);
public sealed record LoginResponse(string AccessToken, DateTimeOffset ExpiresAt, string? RefreshToken, UserResponse User);
public sealed record SessionResponse(Guid SessionId, string DeviceName, string Platform, DateTimeOffset IssuedAt,
    DateTimeOffset LastActiveAt, DateTimeOffset ExpiresAt, bool IsCurrent);
public sealed record SessionListResponse(IReadOnlyList<SessionResponse> Items);
public sealed class AuthException(int status, string code, string message) : Exception(message)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
}
public sealed class AuthOptions
{
    public int AccessTokenMinutes { get; set; } = 15;
    public int RefreshTokenDays { get; set; } = 30;
    public string WebBaseUrl { get; set; } = "http://localhost:4200";
    public string AdminBaseUrl { get; set; } = "http://localhost:4201";
}

public interface IPasswordService
{
    string Hash(string password);
    bool Verify(string password, string hash);
}
public interface ITokenService
{
    string CreateOpaqueToken();
    string HashToken(string token);
    (string Token, DateTimeOffset ExpiresAt) CreateAccessToken(User user, UserSession session);
}
public interface IAuthEmailSender
{
    Task SendAsync(string email, string subject, string body, CancellationToken cancellationToken);
}
public interface IAuthTransaction : IAsyncDisposable
{
    Task CommitAsync(CancellationToken cancellationToken);
}
public interface IAuthStore
{
    Task<IAuthTransaction> LockUserAsync(Guid userId, CancellationToken ct);
    Task<User?> FindUserByEmailAsync(string email, CancellationToken ct);
    Task<User?> FindUserAsync(Guid id, CancellationToken ct);
    Task<bool> UsernameExistsAsync(string username, CancellationToken ct);
    Task<AuthIdentity?> FindIdentityAsync(Guid userId, CancellationToken ct);
    Task<UserSession?> FindSessionByHashAsync(string hash, CancellationToken ct);
    Task<UserSession?> FindSessionAsync(Guid id, CancellationToken ct);
    Task<List<UserSession>> GetSessionsAsync(Guid userId, CancellationToken ct);
    Task<List<UserSession>> GetActiveSessionsAsync(Guid userId, DateTimeOffset now, CancellationToken ct);
    Task TouchSessionAsync(Guid sessionId, DateTimeOffset now, CancellationToken ct);
    Task<EmailVerificationToken?> FindVerificationAsync(string hash, CancellationToken ct);
    Task<PasswordResetToken?> FindResetAsync(string hash, CancellationToken ct);
    Task<bool> IsAdminAsync(Guid userId, CancellationToken ct);
    void AddUser(User user, AuthIdentity identity);
    void AddSession(UserSession session);
    void AddVerification(EmailVerificationToken token);
    void AddReset(PasswordResetToken token);
    Task InvalidateTokensAsync(Guid userId, bool reset, DateTimeOffset now, CancellationToken ct);
    Task SaveAsync(CancellationToken ct);
}
