using HuTube.Application.Auth;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace HuTube.Api.Controllers;

[ApiController, Route("api/v1/auth"), EnableRateLimiting("auth")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class AuthController(AuthService auth, AuthOptions options, IWebHostEnvironment environment) : ControllerBase
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
        return SetSession(await auth.LoginAsync(request, ct));
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
    public Task<MessageResponse> LogoutOthersAsync(CancellationToken ct) => auth.RevokeSessionsAsync(UserId, SessionId, null, ct);
    [Authorize, HttpDelete("sessions/{sessionId:guid}")]
    public Task<MessageResponse> RevokeSessionAsync(Guid sessionId, CancellationToken ct) => auth.RevokeSessionsAsync(UserId, SessionId, sessionId, ct);
}

[ApiController, Authorize, Route("api/v1/admin")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class AdminController(AuthService auth) : ControllerBase
{
    [HttpGet("me")]
    public Task<UserResponse> GetMeAsync(CancellationToken ct) => auth.GetMeAsync(Guid.Parse(User.FindFirst("sub")!.Value), true, ct);
}
