using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Domain.Users;
using Microsoft.EntityFrameworkCore;

namespace HuTube.IntegrationTests;

public sealed class AuthApiTests(AuthApiFactory factory) : IClassFixture<AuthApiFactory>
{
    private const string Password = "CorrectHorse42!";
    private HttpClient Client() => factory.CreateClient(new() { HandleCookies = false });
    private static HttpClient Bearer(HttpClient client, string token) { client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token); return client; }
    private async Task<(HttpClient Client, string Email, Guid Id)> RegisterAsync(bool verify = true)
    {
        var client = Client(); var name = "user_" + Guid.NewGuid().ToString("N"); var email = name + "@example.com";
        var result = await client.PostAsJsonAsync("/api/v1/auth/register", new { username = name, email, displayName = "Người dùng kiểm thử", password = Password });
        Assert.Equal(HttpStatusCode.Created, result.StatusCode);
        await using var db = factory.CreateDb(); var user = await db.Users.SingleAsync(u => u.Email == email);
        if (verify) Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync("/api/v1/auth/verify-email", new { token = factory.Emails.Token(email) })).StatusCode);
        return (client, email, user.UserId);
    }
    private static async Task<LoginResponse> LoginAsync(HttpClient client, string email, string password = Password, string platform = "mobile")
    {
        var response = await client.PostAsJsonAsync("/api/v1/auth/login", new { email, password, platform, deviceName = "Integration test" });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<LoginResponse>())!;
    }
    private static async Task AssertCodeAsync(HttpResponseMessage response, HttpStatusCode status, string code)
    {
        Assert.Equal(status, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(code, body.GetProperty("code").GetString()); Assert.False(string.IsNullOrEmpty(body.GetProperty("traceId").GetString()));
    }
    [Fact]
    public async Task Register_NewEmail_ShouldPersistPendingUserAndHashedSecrets()
    {
        var (_, email, id) = await RegisterAsync(false);
        await using var db = factory.CreateDb();
        var user = await db.Users.SingleAsync(x => x.UserId == id);
        Assert.Null(user.EmailVerifiedAt); Assert.Equal("pending", user.Status);
        Assert.DoesNotContain(Password, user.PasswordHash);
        Assert.NotEqual(factory.Emails.Token(email), user.EmailVerificationTokenHash);
    }
    [Fact]
    public async Task GoogleLogin_VerifiedIdentity_ShouldCreateActiveAccountAndIssueSession()
    {
        var response = await Client().PostAsJsonAsync("/api/v1/auth/google", new { credential = "valid-google-token-123", platform = "mobile", deviceName = "Google integration test" });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var login = (await response.Content.ReadFromJsonAsync<LoginResponse>())!;
        Assert.True(login.User.EmailVerified);
        await using var db = factory.CreateDb();
        var user = await db.Users.SingleAsync(x => x.Email == "google.user@example.com");
        Assert.Equal("google-subject-123", user.GoogleSubject);
        Assert.NotEmpty(login.AccessToken);
    }
    [Fact]
    public async Task Register_DuplicateEmailIgnoringCase_ShouldReturnConflict()
    {
        var (client, email, _) = await RegisterAsync();
        await AssertCodeAsync(await client.PostAsJsonAsync("/api/v1/auth/register", new { username = "other_" + Guid.NewGuid().ToString("N"), email = email.ToUpperInvariant(), displayName = "Other", password = Password }), HttpStatusCode.Conflict, "EMAIL_ALREADY_EXISTS");
    }
    [Theory]
    [InlineData("invalid", "CorrectHorse42!")][InlineData("valid@example.com", "short")]
    public async Task Register_InvalidInput_ShouldReturnValidation(string email, string password)
    {
        var response = await Client().PostAsJsonAsync("/api/v1/auth/register", new { username = "validuser", email, password, displayName = "Test" });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }
    [Fact]
    public async Task Verify_UsedLink_ShouldRejectReplay()
    {
        var (client, email, _) = await RegisterAsync();
        await AssertCodeAsync(await client.PostAsJsonAsync("/api/v1/auth/verify-email", new { token = factory.Emails.Token(email) }), HttpStatusCode.BadRequest, "INVALID_OR_EXPIRED_TOKEN");
    }
    [Fact]
    public async Task Verify_ExpiredLink_ShouldReject()
    {
        var (client, email, id) = await RegisterAsync(false);
        await using var db = factory.CreateDb();
        await db.Users.Where(t => t.UserId == id).ExecuteUpdateAsync(s => s.SetProperty(t => t.EmailVerificationCreatedAt, DateTimeOffset.UtcNow.AddDays(-2)).SetProperty(t => t.EmailVerificationExpiresAt, DateTimeOffset.UtcNow.AddDays(-1)));
        await AssertCodeAsync(await client.PostAsJsonAsync("/api/v1/auth/verify-email", new { token = factory.Emails.Token(email) }), HttpStatusCode.BadRequest, "INVALID_OR_EXPIRED_TOKEN");
    }
    [Fact]
    public async Task Resend_PreviousVerificationLink_ShouldInvalidate()
    {
        var (client, email, _) = await RegisterAsync(false); var old = factory.Emails.Token(email);
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync("/api/v1/auth/resend-verification", new { email })).StatusCode);
        await AssertCodeAsync(await client.PostAsJsonAsync("/api/v1/auth/verify-email", new { token = old }), HttpStatusCode.BadRequest, "INVALID_OR_EXPIRED_TOKEN");
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync("/api/v1/auth/verify-email", new { token = factory.Emails.Token(email) })).StatusCode);
    }
    [Fact]
    public async Task Login_Unverified_ShouldReject()
    {
        var (client, email, _) = await RegisterAsync(false);
        await AssertCodeAsync(await client.PostAsJsonAsync("/api/v1/auth/login", new { email, password = Password, platform = "mobile" }), HttpStatusCode.Forbidden, "EMAIL_NOT_VERIFIED");
    }
    [Fact]
    public async Task Login_WrongPassword_ShouldRejectAndLockAfterFiveAttempts()
    {
        var (client, email, _) = await RegisterAsync();
        for (var i = 0; i < 5; i++) await AssertCodeAsync(await client.PostAsJsonAsync("/api/v1/auth/login", new { email, password = "wrong", platform = "mobile" }), HttpStatusCode.Unauthorized, "INVALID_CREDENTIALS");
        await AssertCodeAsync(await client.PostAsJsonAsync("/api/v1/auth/login", new { email, password = Password, platform = "mobile" }), HttpStatusCode.TooManyRequests, "ACCOUNT_LOCKED");
    }
    [Theory]
    [InlineData("suspended")][InlineData("banned")]
    public async Task Login_BlockedStatus_ShouldRejectLoginAndExistingToken(string status)
    {
        var (client, email, id) = await RegisterAsync(); var login = await LoginAsync(client, email);
        await using var db = factory.CreateDb(); await db.Users.Where(x => x.UserId == id).ExecuteUpdateAsync(s => s.SetProperty(x => x.Status, status));
        await AssertCodeAsync(await client.PostAsJsonAsync("/api/v1/auth/login", new { email, password = Password, platform = "mobile" }), HttpStatusCode.Forbidden, "ACCOUNT_BLOCKED");
        Assert.Equal(HttpStatusCode.Unauthorized, (await Bearer(client, login.AccessToken).GetAsync("/api/v1/auth/me")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = login.RefreshToken })).StatusCode);
    }
    [Fact]
    public async Task Login_RefreshLogout_ShouldRevokeAccessImmediately()
    {
        var (client, email, _) = await RegisterAsync(); var login = await LoginAsync(client, email);
        Assert.Equal(HttpStatusCode.OK, (await Bearer(client, login.AccessToken).GetAsync("/api/v1/auth/me")).StatusCode);
        var response = await client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = login.RefreshToken });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode); var refreshed = (await response.Content.ReadFromJsonAsync<LoginResponse>())!;
        Assert.NotEqual(login.RefreshToken, refreshed.RefreshToken);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1/auth/me")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Bearer(client, refreshed.AccessToken).GetAsync("/api/v1/auth/me")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync("/api/v1/auth/logout", new { refreshToken = refreshed.RefreshToken })).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1/auth/me")).StatusCode);
        await AssertCodeAsync(await client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = refreshed.RefreshToken }), HttpStatusCode.Unauthorized, "INVALID_REFRESH_TOKEN");
    }
    [Fact]
    public async Task Refresh_ReusedToken_ShouldRevokeDescendant()
    {
        var (client, email, _) = await RegisterAsync(); var login = await LoginAsync(client, email);
        var response = await client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = login.RefreshToken });
        var refreshed = (await response.Content.ReadFromJsonAsync<LoginResponse>())!;
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = login.RefreshToken })).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Bearer(client, refreshed.AccessToken).GetAsync("/api/v1/auth/me")).StatusCode);
    }
    [Fact]
    public async Task Refresh_ConcurrentRequests_ShouldAllowOnlyOneRotation()
    {
        var (client, email, _) = await RegisterAsync(); var login = await LoginAsync(client, email);
        var responses = await Task.WhenAll(Enumerable.Range(0, 2).Select(_ => client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = login.RefreshToken })));
        Assert.Single(responses, x => x.StatusCode == HttpStatusCode.OK); Assert.Single(responses, x => x.StatusCode == HttpStatusCode.Unauthorized);
    }
    [Fact]
    public async Task Refresh_ExpiredToken_ShouldReject()
    {
        var (client, email, id) = await RegisterAsync(); var login = await LoginAsync(client, email);
        await using var db = factory.CreateDb(); await db.Sessions.Where(x => x.UserId == id).ExecuteUpdateAsync(s => s.SetProperty(x => x.IssuedAt, DateTimeOffset.UtcNow.AddDays(-2)).SetProperty(x => x.ExpiresAt, DateTimeOffset.UtcNow.AddDays(-1)));
        await AssertCodeAsync(await client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = login.RefreshToken }), HttpStatusCode.Unauthorized, "INVALID_REFRESH_TOKEN");
    }
    [Fact]
    public async Task LogoutOthers_TwoDevices_ShouldPreserveCurrentOnly()
    {
        var (client, email, _) = await RegisterAsync(); var first = await LoginAsync(client, email); var other = await LoginAsync(client, email);
        var response = await Bearer(client, first.AccessToken).PostAsJsonAsync("/api/v1/auth/logout-others", new { }); Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/v1/auth/me")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Bearer(client, other.AccessToken).GetAsync("/api/v1/auth/me")).StatusCode);
    }
    [Fact]
    public async Task RevokeSession_AnotherUsersSession_ShouldReject()
    {
        var (client, email, _) = await RegisterAsync(); var first = await LoginAsync(client, email);
        var (otherClient, otherEmail, _) = await RegisterAsync(); var other = await LoginAsync(otherClient, otherEmail);
        var sessions = await Bearer(otherClient, other.AccessToken).GetFromJsonAsync<SessionListResponse>("/api/v1/auth/sessions");
        await AssertCodeAsync(await Bearer(client, first.AccessToken).DeleteAsync("/api/v1/auth/sessions/" + sessions!.Items[0].SessionId), HttpStatusCode.NotFound, "SESSION_NOT_FOUND");
    }
    [Fact]
    public async Task ResetPassword_ValidLink_ShouldRevokeAllSessionsAndConsumeToken()
    {
        var (client, email, _) = await RegisterAsync(); var login = await LoginAsync(client, email);
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync("/api/v1/auth/forgot-password", new { email })).StatusCode);
        var token = factory.Emails.Token(email);
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync("/api/v1/auth/reset-password", new { token, password = "NewPassword42!" })).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Bearer(client, login.AccessToken).GetAsync("/api/v1/auth/me")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsJsonAsync("/api/v1/auth/login", new { email, password = Password, platform = "mobile" })).StatusCode);
        await LoginAsync(client, email, "NewPassword42!");
        await AssertCodeAsync(await client.PostAsJsonAsync("/api/v1/auth/reset-password", new { token, password = Password }), HttpStatusCode.BadRequest, "INVALID_OR_EXPIRED_TOKEN");
    }
    [Fact]
    public async Task ForgotPassword_UnknownEmail_ShouldReturnSameMessage()
    {
        var (client, email, _) = await RegisterAsync();
        var known = await client.PostAsJsonAsync("/api/v1/auth/forgot-password", new { email });
        var unknown = await client.PostAsJsonAsync("/api/v1/auth/forgot-password", new { email = "missing@example.com" });
        Assert.Equal(await known.Content.ReadAsStringAsync(), await unknown.Content.ReadAsStringAsync());
    }
    [Fact]
    public async Task Admin_OrdinaryUser_ShouldDenyApiAndLogin()
    {
        var (client, email, _) = await RegisterAsync(); var login = await LoginAsync(client, email);
        await AssertCodeAsync(await Bearer(client, login.AccessToken).GetAsync("/api/v1/admin/me"), HttpStatusCode.Forbidden, "ADMIN_ACCESS_DENIED");
        client.DefaultRequestHeaders.Add("X-HuTube-Client", "web"); client.DefaultRequestHeaders.Add("X-HuTube-App", "admin");
        await AssertCodeAsync(await client.PostAsJsonAsync("/api/v1/auth/login", new { email, password = Password, platform = "admin" }), HttpStatusCode.Forbidden, "ADMIN_ACCESS_DENIED");
    }
    [Fact]
    public async Task Admin_DisabledAfterLogin_ShouldBlockImmediately()
    {
        var (client, email, id) = await RegisterAsync();
        await using var db = factory.CreateDb(); await db.Users.Where(x => x.UserId == id).ExecuteUpdateAsync(s => s.SetProperty(x => x.RoleId, UserRoles.Admin));
        client.DefaultRequestHeaders.Add("X-HuTube-Client", "web"); client.DefaultRequestHeaders.Add("X-HuTube-App", "admin");
        var login = await LoginAsync(client, email, platform: "admin");
        Assert.Equal(HttpStatusCode.OK, (await Bearer(client, login.AccessToken).GetAsync("/api/v1/admin/me")).StatusCode);
        await db.Users.Where(x => x.UserId == id).ExecuteUpdateAsync(s => s.SetProperty(x => x.RoleId, UserRoles.User));
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1/admin/me")).StatusCode);
        await AssertCodeAsync(await client.PostAsJsonAsync("/api/v1/auth/login", new { email, password = Password, platform = "admin" }), HttpStatusCode.Forbidden, "ADMIN_ACCESS_DENIED");
    }
    [Fact]
    public async Task Web_Login_ShouldUseHttpOnlyCookieAndRequireCsrfHeader()
    {
        var (client, email, _) = await RegisterAsync(); client.DefaultRequestHeaders.Add("X-HuTube-Client", "web"); client.DefaultRequestHeaders.Add("Origin", "http://localhost:4200");
        var response = await client.PostAsJsonAsync("/api/v1/auth/login", new { email, password = Password, platform = "web" });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Null((await response.Content.ReadFromJsonAsync<LoginResponse>())!.RefreshToken);
        var cookie = response.Headers.GetValues("Set-Cookie").Single(); Assert.Contains("httponly", cookie.ToLowerInvariant()); Assert.Contains("samesite=lax", cookie.ToLowerInvariant());
        client.DefaultRequestHeaders.Add("Cookie", cookie.Split(';')[0]);
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync("/api/v1/auth/refresh", new { })).StatusCode);
        client.DefaultRequestHeaders.Remove("X-HuTube-Client");
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsJsonAsync("/api/v1/auth/refresh", new { })).StatusCode);
    }
    [Fact]
    public async Task Web_UntrustedOrigin_ShouldDenyCookieRequest()
    {
        var client = Client(); client.DefaultRequestHeaders.Add("X-HuTube-Client", "web"); client.DefaultRequestHeaders.Add("Origin", "https://evil.example");
        await AssertCodeAsync(await client.PostAsJsonAsync("/api/v1/auth/refresh", new { }), HttpStatusCode.Forbidden, "ORIGIN_NOT_ALLOWED");
        Assert.False((await client.GetAsync("/api/v1/system/info")).Headers.Contains("Access-Control-Allow-Origin"));
    }
    [Fact]
    public async Task Health_OpenApiAndAnonymousProtected_ShouldMatchContract()
    {
        var client = Client(); Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/health")).StatusCode);
        var spec = await client.GetStringAsync("/openapi/v1.json"); Assert.Contains("/api/v1/auth/login", spec); Assert.Contains("/api/v1/auth/reset-password", spec);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/swagger/index.html")).StatusCode);
        await AssertCodeAsync(await client.GetAsync("/api/v1/auth/me"), HttpStatusCode.Unauthorized, "SESSION_EXPIRED");
    }
    [Fact]
    public async Task Migration_Reapplied_ShouldPreserveFullBootstrapSchema()
    {
        await using var db = factory.CreateDb(); await db.Database.MigrateAsync();
        var count = await db.Database.SqlQueryRaw<int>("SELECT count(*)::integer AS \"Value\" FROM information_schema.tables WHERE table_schema='public' AND table_name <> '__EFMigrationsHistory'").SingleAsync();
        Assert.Equal(42, count);
    }

    [Fact]
    public async Task RevokeSession_DeviceRotatedSinceList_ShouldRevokeReplacement()
    {
        var (client, email, _) = await RegisterAsync(); var current = await LoginAsync(client, email); var other = await LoginAsync(client, email);
        var sessions = await Bearer(client, other.AccessToken).GetFromJsonAsync<SessionListResponse>("/api/v1/auth/sessions");
        var oldId = sessions!.Items.Single(x => x.IsCurrent).SessionId;
        var rotatedResponse = await client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = other.RefreshToken });
        var rotated = (await rotatedResponse.Content.ReadFromJsonAsync<LoginResponse>())!;
        Assert.Equal(HttpStatusCode.OK, (await Bearer(client, current.AccessToken).DeleteAsync("/api/v1/auth/sessions/" + oldId)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Bearer(client, rotated.AccessToken).GetAsync("/api/v1/auth/me")).StatusCode);
    }
    [Fact]
    public async Task Web_UserOriginWithAdminCookie_ShouldDenyCrossAppRefresh()
    {
        var (client, email, id) = await RegisterAsync();
        await using var db = factory.CreateDb(); await db.Users.Where(x => x.UserId == id).ExecuteUpdateAsync(s => s.SetProperty(x => x.RoleId, UserRoles.Admin));
        client.DefaultRequestHeaders.Add("X-HuTube-Client", "web"); client.DefaultRequestHeaders.Add("X-HuTube-App", "admin");
        client.DefaultRequestHeaders.Add("Origin", "http://localhost:4201");
        var response = await client.PostAsJsonAsync("/api/v1/auth/login", new { email, password = Password, platform = "admin" });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        client.DefaultRequestHeaders.Add("Cookie", response.Headers.GetValues("Set-Cookie").Single().Split(';')[0]);
        client.DefaultRequestHeaders.Remove("Origin"); client.DefaultRequestHeaders.Add("Origin", "http://localhost:4200");
        await AssertCodeAsync(await client.PostAsJsonAsync("/api/v1/auth/refresh", new { }), HttpStatusCode.Forbidden, "ORIGIN_NOT_ALLOWED");
        client.DefaultRequestHeaders.Remove("Origin"); client.DefaultRequestHeaders.Add("Origin", "http://localhost:4201");
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync("/api/v1/auth/refresh", new { })).StatusCode);
    }

    [Fact]
    public async Task Logout_OldRotatedCookie_ShouldRevokeReplacement()
    {
        var (client, email, _) = await RegisterAsync(); var login = await LoginAsync(client, email);
        var response = await client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = login.RefreshToken });
        var rotated = (await response.Content.ReadFromJsonAsync<LoginResponse>())!;
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync("/api/v1/auth/logout", new { refreshToken = login.RefreshToken })).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Bearer(client, rotated.AccessToken).GetAsync("/api/v1/auth/me")).StatusCode);
    }

    [Fact]
    public async Task ResetPassword_ConcurrentLinkUse_ShouldSucceedOnce()
    {
        var (client, email, _) = await RegisterAsync();
        await client.PostAsJsonAsync("/api/v1/auth/forgot-password", new { email }); var token = factory.Emails.Token(email);
        var responses = await Task.WhenAll(Enumerable.Range(0, 2).Select(_ => client.PostAsJsonAsync("/api/v1/auth/reset-password", new { token, password = "NextPassword42!" })));
        Assert.Single(responses, x => x.StatusCode == HttpStatusCode.OK); Assert.Single(responses, x => x.StatusCode == HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task ProtectedApi_TamperedToken_ShouldReject()
    {
        var (client, email, _) = await RegisterAsync(); var login = await LoginAsync(client, email);
        var parts = login.AccessToken.Split('.'); parts[2] = "tampered" + parts[2][8..];
        Assert.Equal(HttpStatusCode.Unauthorized, (await Bearer(client, string.Join('.', parts)).GetAsync("/api/v1/auth/me")).StatusCode);
    }

    [Fact]
    public async Task ProtectedApi_ExpiredSignedToken_ShouldRejectEvenWithActiveSession()
    {
        var (client, email, _) = await RegisterAsync(); var login = await LoginAsync(client, email);
        var handler = new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler();
        var original = handler.ReadJwtToken(login.AccessToken);
        var expired = new System.IdentityModel.Tokens.Jwt.JwtSecurityToken("HuTube", "HuTube.Clients",
            original.Claims.Where(x => x.Type is "sub" or "sid" or "jti"), DateTime.UtcNow.AddHours(-2), DateTime.UtcNow.AddHours(-1),
            new Microsoft.IdentityModel.Tokens.SigningCredentials(new Microsoft.IdentityModel.Tokens.SymmetricSecurityKey(System.Text.Encoding.UTF8.GetBytes(new string('t', 80))), Microsoft.IdentityModel.Tokens.SecurityAlgorithms.HmacSha256));
        Assert.Equal(HttpStatusCode.Unauthorized, (await Bearer(client, handler.WriteToken(expired)).GetAsync("/api/v1/auth/me")).StatusCode);
    }

    [Fact]
    public async Task ResetPassword_ExpiredLink_ShouldReject()
    {
        var (client, email, id) = await RegisterAsync(); await client.PostAsJsonAsync("/api/v1/auth/forgot-password", new { email });
        await using var db = factory.CreateDb();
        await db.Users.Where(x => x.UserId == id).ExecuteUpdateAsync(s => s.SetProperty(x => x.PasswordResetCreatedAt, DateTimeOffset.UtcNow.AddDays(-2)).SetProperty(x => x.PasswordResetExpiresAt, DateTimeOffset.UtcNow.AddDays(-1)));
        await AssertCodeAsync(await client.PostAsJsonAsync("/api/v1/auth/reset-password", new { token = factory.Emails.Token(email), password = "NextPassword42!" }), HttpStatusCode.BadRequest, "INVALID_OR_EXPIRED_TOKEN");
    }

    [Fact]
    public async Task Auth_RateLimitExceeded_ShouldReturnRetryContract()
    {
        await using var limited = factory.WithWebHostBuilder(builder => builder.UseSetting("RateLimit:AuthPermitLimit", "2"));
        var client = limited.CreateClient();
        await client.PostAsJsonAsync("/api/v1/auth/forgot-password", new { email = "no-account@example.com" });
        await client.PostAsJsonAsync("/api/v1/auth/forgot-password", new { email = "no-account@example.com" });
        var response = await client.PostAsJsonAsync("/api/v1/auth/forgot-password", new { email = "no-account@example.com" });
        await AssertCodeAsync(response, HttpStatusCode.TooManyRequests, "RATE_LIMIT_EXCEEDED");
        Assert.NotNull(response.Headers.RetryAfter);
    }
}
