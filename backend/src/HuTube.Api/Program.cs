using System.Text;
using System.Threading.RateLimiting;
using HuTube.Api.Middleware;
using HuTube.Application.Auth;
using HuTube.Infrastructure.Authentication;
using HuTube.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);
var rawConnection = builder.Configuration.GetConnectionString("Database") ?? throw new InvalidOperationException("Set ConnectionStrings__Database using your environment or local secret file.");
var connection = DatabaseConnectionString.Normalize(rawConnection);
var jwt = builder.Configuration.GetSection("Jwt").Get<JwtOptions>() ?? new();
var authOptions = builder.Configuration.GetSection("Auth").Get<AuthOptions>() ?? new();
var googleOptions = builder.Configuration.GetSection("Google").Get<GoogleOptions>() ?? new();
var emailOptions = builder.Configuration.GetSection("Email").Get<EmailOptions>() ?? new();
if (jwt.SigningKey.Length < 32) throw new InvalidOperationException("Jwt__SigningKey must contain at least 32 random characters.");
if (authOptions.AccessTokenMinutes is < 1 or > 60 || authOptions.RefreshTokenDays is < 1 or > 90)
    throw new InvalidOperationException("Auth token lifetime configuration is outside its supported range.");
foreach (var url in new[] { authOptions.WebBaseUrl, authOptions.AdminBaseUrl })
    if (!Uri.TryCreate(url, UriKind.Absolute, out var parsed) || parsed.AbsolutePath != "/" || parsed.Query.Length > 0 || parsed.Fragment.Length > 0
        || (builder.Environment.IsDevelopment() ? parsed.Scheme is not ("http" or "https") : parsed.Scheme != "https"))
        throw new InvalidOperationException("Auth client URLs must be origins; HTTPS is required outside Development.");
if (emailOptions.Mode is not ("Pickup" or "Smtp") || (!builder.Environment.IsDevelopment() && emailOptions.Mode == "Pickup"))
    throw new InvalidOperationException("Email pickup is Development-only. Configure SMTP for Staging/Production.");
if (emailOptions.Mode == "Smtp" && string.IsNullOrWhiteSpace(emailOptions.Host)) throw new InvalidOperationException("Email__Host is required for SMTP.");

builder.Services.AddSingleton(jwt); builder.Services.AddSingleton(authOptions); builder.Services.AddSingleton(googleOptions); builder.Services.AddSingleton(emailOptions);
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddDbContext<HuTubeDbContext>(options => options.UseNpgsql(connection));
builder.Services.AddScoped<IAuthStore, AuthStore>(); builder.Services.AddScoped<AuthService>();
builder.Services.AddSingleton<IPasswordService, PasswordService>(); builder.Services.AddSingleton<ITokenService, TokenService>();
builder.Services.AddSingleton<IGoogleTokenVerifier, GoogleTokenVerifier>();
builder.Services.AddSingleton<IAuthEmailSender, AuthEmailSender>();
builder.Services.AddControllers().ConfigureApiBehaviorOptions(options => options.InvalidModelStateResponseFactory = context => {
    var problem = ApiErrors.Create(context.HttpContext, 400, "VALIDATION_ERROR", "Vui lòng kiểm tra các trường dữ liệu.");
    problem.Extensions["errors"] = context.ModelState.Where(x => x.Value?.Errors.Count > 0).ToDictionary(x => x.Key, x => x.Value!.Errors.Select(_ => "Giá trị không hợp lệ.").ToArray());
    var result = new BadRequestObjectResult(problem); result.ContentTypes.Add("application/problem+json"); return result;
});
builder.Services.AddOpenApi();
builder.Services.AddCors(options => options.AddDefaultPolicy(policy => policy.WithOrigins(authOptions.WebBaseUrl.TrimEnd('/'), authOptions.AdminBaseUrl.TrimEnd('/'))
    .WithMethods("GET", "POST", "DELETE", "OPTIONS").WithHeaders("Content-Type", "Authorization", "X-HuTube-Client", "X-HuTube-App").AllowCredentials()));
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options => {
    options.MapInboundClaims = false;
    options.TokenValidationParameters = new() {
        ValidateIssuer = true, ValidIssuer = jwt.Issuer, ValidateAudience = true, ValidAudience = jwt.Audience,
        ValidateIssuerSigningKey = true, IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.SigningKey)),
        ValidateLifetime = true, ClockSkew = TimeSpan.Zero, ValidAlgorithms = [SecurityAlgorithms.HmacSha256]
    };
    options.Events = new() {
        OnTokenValidated = async context => {
            if (!Guid.TryParse(context.Principal?.FindFirst("sub")?.Value, out var userId)
                || !Guid.TryParse(context.Principal?.FindFirst("sid")?.Value, out var sessionId)
                || !Guid.TryParse(context.Principal?.FindFirst("jti")?.Value, out var jti)
                || !await context.HttpContext.RequestServices.GetRequiredService<AuthService>().ValidateSessionAsync(userId, sessionId, jti, context.HttpContext.RequestAborted))
                context.Fail("SESSION_EXPIRED");
        },
        OnChallenge = async context => { context.HandleResponse(); await ApiErrors.WriteAsync(context.HttpContext, 401, "SESSION_EXPIRED", "Phiên đã hết hạn. Vui lòng đăng nhập lại."); },
        OnForbidden = context => ApiErrors.WriteAsync(context.HttpContext, 403, "PERMISSION_DENIED", "Bạn không có quyền thực hiện thao tác này.")
    };
});
builder.Services.AddAuthorization();
builder.Services.AddRateLimiter(options => {
    options.AddPolicy("auth", context => RateLimitPartition.GetFixedWindowLimiter(context.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ => new() {
        PermitLimit = builder.Configuration.GetValue("RateLimit:AuthPermitLimit", 60), Window = TimeSpan.FromMinutes(1), QueueLimit = 0
    }));
    options.OnRejected = async (context, _) => {
        context.HttpContext.Response.Headers.RetryAfter = "60";
        await ApiErrors.WriteAsync(context.HttpContext, 429, "RATE_LIMIT_EXCEEDED", "Yêu cầu quá nhanh. Vui lòng thử lại sau một phút.");
    };
});

var app = builder.Build();
if (args.Contains("--migrate"))
{
    await using var scope = app.Services.CreateAsyncScope();
    await scope.ServiceProvider.GetRequiredService<HuTubeDbContext>().Database.MigrateAsync();
    return;
}
app.UseMiddleware<ExceptionMiddleware>();
app.Use(async (context, next) => {
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    context.Response.Headers["X-Request-ID"] = context.TraceIdentifier;
    await next(context);
});
if (!app.Environment.IsDevelopment()) app.UseHsts();
app.UseCors(); app.UseRateLimiter(); app.UseAuthentication(); app.UseAuthorization();
app.UseStatusCodePages(context => ApiErrors.WriteAsync(context.HttpContext, context.HttpContext.Response.StatusCode, "HTTP_ERROR", "Yêu cầu không được xử lý."));
if (!app.Environment.IsProduction()) {
    app.MapOpenApi();
    app.UseSwaggerUI(options => options.SwaggerEndpoint("/openapi/v1.json", "HuTube API v1"));
}
app.MapGet("/health", async (HuTubeDbContext db, CancellationToken ct) => {
    try { return await db.Database.CanConnectAsync(ct) && await db.Users.OrderBy(x => x.UserId).Take(1).CountAsync(ct) >= 0
        ? Results.Ok(new { status = "healthy" }) : Results.Json(new { status = "unhealthy" }, statusCode: 503); }
    catch { return Results.Json(new { status = "unhealthy" }, statusCode: 503); }
}).AllowAnonymous();
app.MapGet("/api/v1/system/info", () => new { name = "HuTube", apiVersion = "v1", environment = app.Environment.EnvironmentName,
    serverTime = DateTimeOffset.UtcNow, commitSha = Environment.GetEnvironmentVariable("RENDER_GIT_COMMIT") ?? Environment.GetEnvironmentVariable("HUTUBE_COMMIT_SHA") ?? "local" }).AllowAnonymous();
app.MapGet("/api/v1/system/config", () => new { googleClientId = googleOptions.ClientId }).AllowAnonymous();
app.MapControllers();
app.Run();
public partial class Program { }
