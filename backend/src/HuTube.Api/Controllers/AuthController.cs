using HuTube.Application.Auth;
using HuTube.Application.Rbac;
using HuTube.Infrastructure.Notifications;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.SignalR;

namespace HuTube.Api.Controllers;

[ApiController, Route("api/v1/auth"), EnableRateLimiting("auth")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class AuthController(AuthService auth, AuthOptions options, IWebHostEnvironment environment, RbacService rbacService,
    IHubContext<NotificationHub> notificationHub) : ControllerBase
{
    private bool IsWeb => Request.Headers["X-HuTube-Client"] == "web";
    private string Platform => IsWeb ? (Request.Headers["X-HuTube-App"] == "admin" ? "admin" : "web") : "mobile";
    private string CookieName => Platform == "admin" ? "hutube_admin_refresh" : "hutube_refresh";
    private Guid UserId => Guid.Parse(User.FindFirst("sub")!.Value);
    private Guid SessionId => Guid.Parse(User.FindFirst("sid")!.Value);

    private void ValidateBrowser()
    {
        if (!IsWeb) return;
        var origin = Request.Headers.Origin.ToString();
        var expectedOrigin = Platform == "admin" ? options.AdminBaseUrl.TrimEnd('/') : options.WebBaseUrl.TrimEnd('/');
        var allowedOrigins = (options.AllowedOrigins ?? []).Select(value => value.TrimEnd('/'));
        if (origin.Length > 0 && !string.Equals(origin, expectedOrigin, StringComparison.OrdinalIgnoreCase)
            && !allowedOrigins.Contains(origin, StringComparer.OrdinalIgnoreCase))
            throw new AuthException(403, "ORIGIN_NOT_ALLOWED", "Nguồn yêu cầu không được phép.");
    }
    private string? ReadRefresh(RefreshRequest request)
    {
        ValidateBrowser();
        return IsWeb ? Request.Cookies[CookieName] : request.RefreshToken;
    }
    private LoginResponse SetSession(LoginResponse response)
    {
        if (!IsWeb) return response;
        Response.Cookies.Append(CookieName, response.RefreshToken!, new CookieOptions {
            HttpOnly = true, Secure = !environment.IsDevelopment(), SameSite = environment.IsDevelopment() ? SameSiteMode.Lax : SameSiteMode.None,
            Path = "/api/v1/auth", MaxAge = TimeSpan.FromDays(options.RefreshTokenDays), IsEssential = true
        });
        return response with { RefreshToken = null };
    }
    [HttpPost("register")]
    public async Task<ActionResult<MessageResponse>> RegisterAsync(RegisterRequest request, CancellationToken ct) => StatusCode(201, await auth.RegisterAsync(request, ct));
    [HttpPost("login")]
    public async Task<ActionResult<LoginResponse>> LoginAsync(LoginRequest request, CancellationToken ct)
    {
        ValidateBrowser();
        if (request.Platform != Platform) throw new AuthException(400, "CLIENT_PLATFORM_MISMATCH", "Cấu hình client không khớp nền tảng đăng nhập.");
        var response = await auth.LoginAsync(request, ct);

        if (Platform == "admin")
        {
            await rbacService.LogAuditAsync(new AuditLogEntry(
                response.User.UserId,
                "admin.login",
                "user",
                response.User.UserId,
                "Admin login succeeded",
                IpAddress: HttpContext.Connection.RemoteIpAddress?.ToString(),
                UserAgent: Request.Headers.UserAgent.ToString()), ct);
        }

        return SetSession(response);
    }
    [HttpPost("google")]
    public async Task<ActionResult<LoginResponse>> GoogleAsync(GoogleLoginRequest request, CancellationToken ct)
    {
        ValidateBrowser();
        if (request.Platform != Platform || Platform == "admin")
            throw new AuthException(400, "CLIENT_PLATFORM_MISMATCH", "Cấu hình client không khớp nền tảng đăng nhập Google.");
        return SetSession(await auth.GoogleLoginAsync(request, ct));
    }
    [HttpPost("refresh")]
    public async Task<ActionResult<LoginResponse>> RefreshAsync(RefreshRequest request, CancellationToken ct) =>
        SetSession(await auth.RefreshAsync(ReadRefresh(request) ?? "", Platform, ct));
    [HttpPost("logout")]
    public async Task<ActionResult<MessageResponse>> LogoutAsync(RefreshRequest request, CancellationToken ct)
    {
        var response = await auth.LogoutAsync(ReadRefresh(request), Platform, ct);
        if (IsWeb) Response.Cookies.Delete(CookieName, new CookieOptions { Path = "/api/v1/auth", Secure = !environment.IsDevelopment(), HttpOnly = true,
            SameSite = environment.IsDevelopment() ? SameSiteMode.Lax : SameSiteMode.None });

        if (Platform == "admin" && User.Identity?.IsAuthenticated == true && Guid.TryParse(User.FindFirst("sub")?.Value, out var adminUserId))
        {
            await rbacService.LogAuditAsync(new AuditLogEntry(
                adminUserId,
                "admin.logout",
                "user",
                adminUserId,
                "Admin logout",
                IpAddress: HttpContext.Connection.RemoteIpAddress?.ToString(),
                UserAgent: Request.Headers.UserAgent.ToString()), ct);
        }

        return response;
    }
    [HttpPost("verify-email")]
    public Task<MessageResponse> VerifyEmailAsync(TokenRequest request, CancellationToken ct) => auth.VerifyEmailAsync(request.Token, ct);
    [HttpPost("resend-verification")]
    public Task<MessageResponse> ResendVerificationAsync(EmailRequest request, CancellationToken ct) => auth.ResendVerificationAsync(request.Email, ct);
    [HttpPost("forgot-password")]
    public Task<MessageResponse> ForgotPasswordAsync(EmailRequest request, CancellationToken ct) => auth.ForgotPasswordAsync(request.Email, ct);
    [HttpPost("reset-password")]
    public Task<MessageResponse> ResetPasswordAsync(ResetPasswordRequest request, CancellationToken ct) => auth.ResetPasswordAsync(request, ct);
    [Authorize, HttpGet("me")]
    public Task<UserResponse> GetMeAsync(CancellationToken ct) => auth.GetMeAsync(UserId, false, ct);
    [Authorize, HttpGet("sessions")]
    public Task<SessionListResponse> GetSessionsAsync(CancellationToken ct) => auth.GetSessionsAsync(UserId, SessionId, ct);
    [Authorize, HttpPost("logout-others")]
    public async Task<MessageResponse> LogoutOthersAsync(CancellationToken ct)
    {
        var userId = UserId;
        var currentSessionId = SessionId;
        var response = await auth.RevokeSessionsAsync(userId, currentSessionId, null, ct);
        await notificationHub.Clients.User(userId.ToString()).SendAsync("SessionRevoked", new
        {
            reason = "user-revoked-others",
            allSessions = false,
            exceptSessionId = currentSessionId,
            revokedAt = DateTimeOffset.UtcNow
        }, ct);
        return response;
    }
    [Authorize, HttpPost("logout-all")]
    public async Task<MessageResponse> LogoutAllAsync(CancellationToken ct)
    {
        var userId = UserId;
        var response = await auth.RevokeAllSessionsAsync(userId, ct);
        await rbacService.LogAuditAsync(new AuditLogEntry(
            userId,
            "auth.sessions_revoked_all",
            "user",
            userId,
            "User signed out all devices",
            IpAddress: HttpContext.Connection.RemoteIpAddress?.ToString(),
            UserAgent: Request.Headers.UserAgent.ToString()), ct);
        if (IsWeb) Response.Cookies.Delete(CookieName, new CookieOptions { Path = "/api/v1/auth", Secure = !environment.IsDevelopment(), HttpOnly = true,
            SameSite = environment.IsDevelopment() ? SameSiteMode.Lax : SameSiteMode.None });
        try
        {
            await notificationHub.Clients.User(userId.ToString()).SendAsync("SessionRevoked", new
            {
                reason = "user-revoked-all",
                allSessions = true,
                revokedAt = DateTimeOffset.UtcNow
            }, ct);
        }
        catch
        {
            // Session revocation and the HTTP response remain authoritative if realtime delivery is unavailable.
        }
        return response;
    }
    [Authorize, HttpDelete("sessions/{sessionId:guid}")]
    public Task<MessageResponse> RevokeSessionAsync(Guid sessionId, CancellationToken ct) => auth.RevokeSessionsAsync(UserId, SessionId, sessionId, ct);
}
