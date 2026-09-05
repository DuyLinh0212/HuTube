using HuTube.Domain.Users;

namespace HuTube.Application.Auth;

public sealed class AuthService(IAuthStore store, IPasswordService passwords, ITokenService tokens,
    IAuthEmailSender emailSender, IGoogleTokenVerifier google, AuthOptions options, TimeProvider clock)
{
    private DateTimeOffset Now => clock.GetUtcNow();
    private static readonly MessageResponse EmailSent = new("Nếu email phù hợp, hướng dẫn đã được gửi. Vui lòng kiểm tra hộp thư.");
    private static AuthException InvalidRefresh() => new(401, "INVALID_REFRESH_TOKEN", "Phiên đã hết hạn. Vui lòng đăng nhập lại.");
    private static AuthException InvalidLink() => new(400, "INVALID_OR_EXPIRED_TOKEN", "Liên kết đã hết hạn hoặc đã được sử dụng. Vui lòng yêu cầu liên kết mới.");

    public async Task<MessageResponse> RegisterAsync(RegisterRequest request, CancellationToken ct = default)
    {
        var email = AuthRules.NormalizeEmail(request.Email);
        AuthRules.ValidatePassword(request.Password);
        if (!System.Text.RegularExpressions.Regex.IsMatch(request.Username ?? "", @"^[a-zA-Z0-9_.-]{3,50}$")
            || string.IsNullOrWhiteSpace(request.DisplayName) || request.DisplayName.Length > 120)
            throw new AuthException(400, "VALIDATION_ERROR", "Tên người dùng hoặc tên hiển thị không hợp lệ.");
        var user = new User { Email = email, Username = request.Username!, DisplayName = request.DisplayName.Trim(), CreatedAt = Now, UpdatedAt = Now };
        await using var transaction = await store.LockUserAsync(user.UserId, ct);
        if (await store.FindUserByEmailAsync(email, ct) != null)
            throw new AuthException(409, "EMAIL_ALREADY_EXISTS", "Email đã được sử dụng.");
        if (await store.UsernameExistsAsync(user.Username, ct))
            throw new AuthException(409, "USERNAME_ALREADY_EXISTS", "Tên người dùng đã được sử dụng.");
        store.AddUser(user, passwords.Hash(request.Password));
        await store.SaveAsync(ct);
        await SendVerificationAsync(user, ct);
        await transaction.CommitAsync(ct);
        return new("Đăng ký thành công. Vui lòng xác minh email trước khi đăng nhập.");
    }

    private void EnsureActive(User user)
    {
        if (user.IsBlocked) throw new AuthException(403, "ACCOUNT_BLOCKED", "Tài khoản đang bị tạm ngưng hoặc bị khóa.");
        if (user.EmailVerifiedAt == null || user.Status != "active")
            throw new AuthException(403, "EMAIL_NOT_VERIFIED", "Vui lòng xác minh email trước khi đăng nhập.");
    }

    public async Task<LoginResponse> LoginAsync(LoginRequest request, CancellationToken ct = default)
    {
        var email = AuthRules.NormalizeEmail(request.Email);
        var candidate = await store.FindUserByEmailAsync(email, ct);
        if (candidate == null)
        {
            // Comparable password derivation cost for unknown accounts.
            passwords.Hash(request.Password);
            throw new AuthException(401, "INVALID_CREDENTIALS", "Email hoặc mật khẩu không đúng.");
        }
        await using var transaction = await store.LockUserAsync(candidate.UserId, ct);
        var user = (await store.FindUserAsync(candidate.UserId, ct))!;
        if (user.LockedUntil > Now) throw new AuthException(429, "ACCOUNT_LOCKED", "Thử đăng nhập quá nhiều lần. Vui lòng thử lại sau 15 phút.");
        if (string.IsNullOrWhiteSpace(user.PasswordHash) || !passwords.Verify(request.Password, user.PasswordHash))
        {
            user.FailedLoginAttempts++;
            if (user.FailedLoginAttempts >= 5) { user.LockedUntil = Now.AddMinutes(15); user.FailedLoginAttempts = 0; }
            await store.SaveAsync(ct);
            await transaction.CommitAsync(ct);
            throw new AuthException(401, "INVALID_CREDENTIALS", "Email hoặc mật khẩu không đúng.");
        }
        EnsureActive(user);
        if (request.Platform == "admin" && !await store.IsAdminAsync(user.UserId, ct))
            throw new AuthException(403, "ADMIN_ACCESS_DENIED", "Tài khoản không có quyền truy cập quản trị.");
        if (request.Platform is not ("web" or "mobile" or "admin"))
            throw new AuthException(400, "VALIDATION_ERROR", "Nền tảng không hợp lệ.");
        var response = await CompleteLoginAsync(user, request.Platform, request.DeviceName, ct);
        await transaction.CommitAsync(ct);
        return response;
    }

    public async Task<LoginResponse> GoogleLoginAsync(GoogleLoginRequest request, CancellationToken ct = default)
    {
        if (request.Platform is not ("web" or "mobile"))
            throw new AuthException(400, "VALIDATION_ERROR", "Nền tảng không hợp lệ.");
        var identity = await google.VerifyAsync(request.Credential, ct);
        var candidate = await store.FindUserByGoogleSubjectAsync(identity.Subject, ct)
            ?? await store.FindUserByEmailAsync(AuthRules.NormalizeEmail(identity.Email), ct);

        if (candidate is null)
        {
            var username = await CreateGoogleUsernameAsync(identity.Email, ct);
            var user = new User {
                Email = AuthRules.NormalizeEmail(identity.Email), Username = username, DisplayName = identity.DisplayName.Trim()[..Math.Min(identity.DisplayName.Trim().Length, 120)],
                GoogleSubject = identity.Subject, EmailVerifiedAt = Now, Status = "active", CreatedAt = Now, UpdatedAt = Now
            };
            Guid? concurrentUserId = null;
            await using (var transaction = await store.LockUserAsync(user.UserId, ct))
            {
                var concurrent = await store.FindUserByEmailAsync(user.Email, ct);
                if (concurrent is not null) concurrentUserId = concurrent.UserId;
                else
                {
                    store.AddUser(user, passwords.Hash(tokens.CreateOpaqueToken()));
                    var response = await CompleteLoginAsync(user, request.Platform, request.DeviceName, ct);
                    await transaction.CommitAsync(ct);
                    return response;
                }
                await transaction.CommitAsync(ct);
            }
            return await GoogleLoginExistingAsync(concurrentUserId!.Value, identity, request, ct);
        }
        return await GoogleLoginExistingAsync(candidate.UserId, identity, request, ct);
    }

    private async Task<LoginResponse> GoogleLoginExistingAsync(Guid userId, GoogleIdentity identity, GoogleLoginRequest request, CancellationToken ct)
    {
        await using var transaction = await store.LockUserAsync(userId, ct);
        var user = await store.FindUserAsync(userId, ct) ?? throw new AuthException(401, "INVALID_GOOGLE_TOKEN", "Không tìm thấy tài khoản Google.");
        if (user.IsBlocked) EnsureActive(user);
        if (user.GoogleSubject is not null && user.GoogleSubject != identity.Subject)
            throw new AuthException(409, "GOOGLE_ACCOUNT_CONFLICT", "Email này đã được liên kết với một tài khoản Google khác.");
        user.GoogleSubject = identity.Subject;
        user.EmailVerifiedAt ??= Now;
        if (user.Status == "pending") user.Status = "active";
        var response = await CompleteLoginAsync(user, request.Platform, request.DeviceName, ct);
        await transaction.CommitAsync(ct);
        return response;
    }

    public async Task<LoginResponse> RefreshAsync(string refresh, string platform, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(refresh)) throw InvalidRefresh();
        var hash = tokens.HashToken(refresh);
        var candidate = await store.FindSessionByHashAsync(hash, ct) ?? throw InvalidRefresh();
        await using var transaction = await store.LockUserAsync(candidate.UserId, ct);
        var old = await store.FindSessionByHashAsync(hash, ct) ?? throw InvalidRefresh();
        if (old.Platform != platform) throw InvalidRefresh();
        if (old.RevokedAt != null)
        {
            // Reuse of a rotated token revokes its descendants only, not unrelated devices.
            var nextId = old.ReplacedBySessionId;
            while (nextId != null)
            {
                var next = await store.FindSessionAsync(nextId.Value, ct);
                if (next == null) break;
                next.Revoke(Now, "refresh-token-reuse");
                nextId = next.ReplacedBySessionId;
            }
            await store.SaveAsync(ct); await transaction.CommitAsync(ct);
            throw InvalidRefresh();
        }
        if (!old.IsActive(Now)) throw InvalidRefresh();
        var user = await store.FindUserAsync(old.UserId, ct) ?? throw InvalidRefresh();
        EnsureActive(user);
        if (old.Platform == "admin" && !await store.IsAdminAsync(user.UserId, ct))
            throw new AuthException(403, "ADMIN_ACCESS_DENIED", "Quyền quản trị đã bị vô hiệu hóa.");
        var (session, nextRefresh) = CreateSession(user.UserId, old.Platform, old.DeviceName);
        // Absolute session lifetime cannot be extended indefinitely by refresh.
        session.ExpiresAt = old.ExpiresAt;
        old.Revoke(Now, "rotated"); old.ReplacedBySessionId = session.SessionId;
        store.AddSession(session);
        await store.SaveAsync(ct);
        var response = await CreateLoginResponseAsync(user, session, nextRefresh, ct);
        await transaction.CommitAsync(ct);
        return response;
    }

    public async Task<MessageResponse> LogoutAsync(string? refresh, string platform, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(refresh)) return new("Đã đăng xuất.");
        var hash = tokens.HashToken(refresh);
        var candidate = await store.FindSessionByHashAsync(hash, ct);
        if (candidate == null || candidate.Platform != platform) return new("Đã đăng xuất.");
        await using var transaction = await store.LockUserAsync(candidate.UserId, ct);
        var session = await store.FindSessionByHashAsync(hash, ct);
        while (session != null)
        {
            session.Revoke(Now, "logout");
            session = session.ReplacedBySessionId is { } next ? await store.FindSessionAsync(next, ct) : null;
        }
        await store.SaveAsync(ct); await transaction.CommitAsync(ct);
        return new("Đã đăng xuất.");
    }

    public async Task<MessageResponse> VerifyEmailAsync(string raw, CancellationToken ct = default)
    {
        var hash = tokens.HashToken(raw);
        var candidate = await store.FindVerificationAsync(hash, ct) ?? throw InvalidLink();
        await using var transaction = await store.LockUserAsync(candidate.UserId, ct);
        var token = await store.FindVerificationAsync(hash, ct) ?? throw InvalidLink();
        if (token.UsedAt != null || token.ExpiresAt <= Now) throw InvalidLink();
        var user = await store.FindUserAsync(token.UserId, ct) ?? throw InvalidLink();
        if (user.IsBlocked) throw new AuthException(403, "ACCOUNT_BLOCKED", "Tài khoản đang bị khóa.");
        user.EmailVerifiedAt ??= Now; user.Status = "active";
        token.UsedAt = Now;
        await store.InvalidateTokensAsync(user.UserId, false, Now, ct);
        await store.SaveAsync(ct); await transaction.CommitAsync(ct);
        return new("Email đã được xác minh. Bạn có thể đăng nhập.");
    }

    public async Task<MessageResponse> ResendVerificationAsync(string email, CancellationToken ct = default)
    {
        var candidate = await store.FindUserByEmailAsync(AuthRules.NormalizeEmail(email), ct);
        if (candidate == null) return EmailSent;
        await using var transaction = await store.LockUserAsync(candidate.UserId, ct);
        var user = await store.FindUserAsync(candidate.UserId, ct);
        if (user == null || user.IsBlocked || user.EmailVerifiedAt != null) return EmailSent;
        await store.InvalidateTokensAsync(user.UserId, false, Now, ct);
        await SendVerificationAsync(user, ct);
        await transaction.CommitAsync(ct);
        return EmailSent;
    }

    public async Task<MessageResponse> ForgotPasswordAsync(string email, CancellationToken ct = default)
    {
        var candidate = await store.FindUserByEmailAsync(AuthRules.NormalizeEmail(email), ct);
        if (candidate == null) return EmailSent;
        await using var transaction = await store.LockUserAsync(candidate.UserId, ct);
        var user = await store.FindUserAsync(candidate.UserId, ct);
        if (user == null || user.IsBlocked || user.EmailVerifiedAt == null) return EmailSent;
        await store.InvalidateTokensAsync(user.UserId, true, Now, ct);
        var raw = tokens.CreateOpaqueToken();
        store.AddReset(user, new() { UserId = user.UserId, TokenHash = tokens.HashToken(raw), CreatedAt = Now, ExpiresAt = Now.AddMinutes(30) });
        await store.SaveAsync(ct);
        await emailSender.SendAsync(user.Email, "Đặt lại mật khẩu HuTube", $"Mở liên kết trong 30 phút: {options.WebBaseUrl.TrimEnd('/')}/reset-password?token={Uri.EscapeDataString(raw)}", ct);
        await transaction.CommitAsync(ct);
        return EmailSent;
    }

    public async Task<MessageResponse> ResetPasswordAsync(ResetPasswordRequest request, CancellationToken ct = default)
    {
        AuthRules.ValidatePassword(request.Password);
        var hash = tokens.HashToken(request.Token);
        var candidate = await store.FindResetAsync(hash, ct) ?? throw InvalidLink();
        await using var transaction = await store.LockUserAsync(candidate.UserId, ct);
        var token = await store.FindResetAsync(hash, ct) ?? throw InvalidLink();
        if (token.UsedAt != null || token.ExpiresAt <= Now) throw InvalidLink();
        var user = await store.FindUserAsync(token.UserId, ct) ?? throw InvalidLink();
        EnsureActive(user);
        user.PasswordHash = passwords.Hash(request.Password); user.UpdatedAt = Now;
        user.FailedLoginAttempts = 0; user.LockedUntil = null; token.UsedAt = Now;
        await store.InvalidateTokensAsync(user.UserId, true, Now, ct);
        foreach (var session in await store.GetSessionsAsync(user.UserId, ct)) session.Revoke(Now, "password-reset");
        await store.SaveAsync(ct); await transaction.CommitAsync(ct);
        return new("Mật khẩu đã được đặt lại. Vui lòng đăng nhập lại trên các thiết bị.");
    }

    public async Task<UserResponse> GetMeAsync(Guid userId, bool requireAdmin, CancellationToken ct = default)
    {
        var user = await store.FindUserAsync(userId, ct) ?? throw InvalidRefresh();
        EnsureActive(user);
        var isAdmin = await store.IsAdminAsync(userId, ct);
        if (requireAdmin && !isAdmin) throw new AuthException(403, "ADMIN_ACCESS_DENIED", "Bạn không có quyền truy cập quản trị.");
        return ToResponse(user, isAdmin);
    }

    public async Task<bool> ValidateSessionAsync(Guid userId, Guid sessionId, Guid jti, CancellationToken ct = default)
    {
        var session = await store.FindSessionAsync(sessionId, ct);
        if (session == null || session.UserId != userId || session.Jti != jti || !session.IsActive(Now)) return false;
        var user = await store.FindUserAsync(userId, ct);
        if (user == null || user.IsBlocked || user.Status != "active" || user.EmailVerifiedAt == null) return false;
        if (session.Platform == "admin" && !await store.IsAdminAsync(userId, ct)) return false;
        await store.TouchSessionAsync(sessionId, Now, ct);
        return true;
    }

    public async Task<SessionListResponse> GetSessionsAsync(Guid userId, Guid current, CancellationToken ct = default) =>
        new((await store.GetActiveSessionsAsync(userId, Now, ct))
            .Select(s => new SessionResponse(s.SessionId, s.DeviceName, s.Platform, s.IssuedAt, s.LastActiveAt, s.ExpiresAt, s.SessionId == current)).ToList());

    public async Task<MessageResponse> RevokeSessionsAsync(Guid userId, Guid current, Guid? target, CancellationToken ct = default)
    {
        await using var transaction = await store.LockUserAsync(userId, ct);
        var sessions = await store.GetSessionsAsync(userId, ct);
        if (target.HasValue && sessions.All(s => s.SessionId != target))
            throw new AuthException(404, "SESSION_NOT_FOUND", "Không tìm thấy phiên đăng nhập.");
        if (target.HasValue)
        {
            var session = sessions.Single(s => s.SessionId == target);
            while (session != null)
            {
                session.Revoke(Now, "user-revoked");
                session = session.ReplacedBySessionId is { } next ? sessions.SingleOrDefault(s => s.SessionId == next) : null;
            }
        }
        else foreach (var session in sessions.Where(s => s.SessionId != current)) session.Revoke(Now, "user-revoked");
        await store.SaveAsync(ct); await transaction.CommitAsync(ct);
        return new("Đã kết thúc phiên đăng nhập.");
    }

    private async Task SendVerificationAsync(User user, CancellationToken ct)
    {
        var raw = tokens.CreateOpaqueToken();
        store.AddVerification(user, new() { UserId = user.UserId, TokenHash = tokens.HashToken(raw), CreatedAt = Now, ExpiresAt = Now.AddHours(24) });
        await store.SaveAsync(ct);
        await emailSender.SendAsync(user.Email, "Xác minh email HuTube", $"Mở liên kết trong 24 giờ: {options.WebBaseUrl.TrimEnd('/')}/verify-email?token={Uri.EscapeDataString(raw)}", ct);
    }

    private (UserSession Session, string Refresh) CreateSession(Guid userId, string platform, string deviceName)
    {
        var raw = tokens.CreateOpaqueToken();
        return (new() { UserId = userId, RefreshTokenHash = tokens.HashToken(raw), Platform = platform,
            DeviceName = deviceName, IssuedAt = Now, LastActiveAt = Now, ExpiresAt = Now.AddDays(options.RefreshTokenDays) }, raw);
    }
    private async Task<LoginResponse> CompleteLoginAsync(User user, string platform, string deviceName, CancellationToken ct)
    {
        EnsureActive(user);
        user.FailedLoginAttempts = 0; user.LockedUntil = null; user.LastLoginAt = Now; user.UpdatedAt = Now;
        var (session, refresh) = CreateSession(user.UserId, platform, deviceName);
        store.AddSession(session);
        await store.SaveAsync(ct);
        return await CreateLoginResponseAsync(user, session, refresh, ct);
    }
    private async Task<string> CreateGoogleUsernameAsync(string email, CancellationToken ct)
    {
        var stem = System.Text.RegularExpressions.Regex.Replace(email.Split('@')[0], "[^A-Za-z0-9_.-]", "-").Trim('-', '.', '_');
        if (stem.Length < 3) stem = "google-user";
        stem = stem[..Math.Min(stem.Length, 38)];
        for (var attempt = 0; attempt < 20; attempt++)
        {
            var suffix = Guid.NewGuid().ToString("N")[..12];
            var candidate = $"{stem[..Math.Min(stem.Length, 50 - suffix.Length - 1)]}-{suffix}";
            if (!await store.UsernameExistsAsync(candidate, ct)) return candidate;
        }
        throw new AuthException(503, "USERNAME_ALLOCATION_FAILED", "Không thể tạo tài khoản Google. Vui lòng thử lại.");
    }
    private async Task<LoginResponse> CreateLoginResponseAsync(User user, UserSession session, string refresh, CancellationToken ct)
    {
        var access = tokens.CreateAccessToken(user, session);
        return new(access.Token, access.ExpiresAt, refresh, ToResponse(user, await store.IsAdminAsync(user.UserId, ct)));
    }
    private static UserResponse ToResponse(User user, bool isAdmin) => new(user.UserId, user.Username, user.Email, user.DisplayName, user.EmailVerifiedAt != null, isAdmin);
}
