using System.Text;
using System.Threading.RateLimiting;
using HuTube.Api.Middleware;
using HuTube.Api.Services;
using HuTube.Application.Account;
using HuTube.Application.Auth;
using HuTube.Application.Channels;
using HuTube.Application.Notifications;
using HuTube.Application.Plans;
using HuTube.Application.Playlists;
using HuTube.Application.Storage;
using HuTube.Application.Videos;
using HuTube.Infrastructure.Account;
using HuTube.Application.CfSeeding;
using HuTube.Infrastructure.CfSeeding;
using HuTube.Infrastructure.Authentication;
using HuTube.Infrastructure.Persistence;
using HuTube.Infrastructure.Plans;
using HuTube.Infrastructure.Playlists;
using HuTube.Infrastructure.Storage;
using HuTube.Infrastructure.Taxonomy;
using HuTube.Infrastructure.Users;
using HuTube.Infrastructure.Videos;
using HuTube.Infrastructure.Notifications;
using HuTube.Infrastructure.Policies;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.FileProviders;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);
var rawConnection = builder.Configuration.GetConnectionString("Database") ?? throw new InvalidOperationException("Set ConnectionStrings__Database using your environment or local secret file.");
var connection = DatabaseConnectionString.Normalize(rawConnection);
var jwt = builder.Configuration.GetSection("Jwt").Get<JwtOptions>() ?? new();
var authOptions = builder.Configuration.GetSection("Auth").Get<AuthOptions>() ?? new();
var googleOptions = builder.Configuration.GetSection("Google").Get<GoogleOptions>() ?? new();
var emailOptions = builder.Configuration.GetSection("Email").Get<EmailOptions>() ?? new();
var storageOptions = builder.Configuration.GetSection("Storage").Get<StorageOptions>() ?? new();
var r2Options = builder.Configuration.GetSection("Storage:R2").Get<R2Options>() ?? new();
var featureOptions = builder.Configuration.GetSection("Features").Get<FeatureOptions>() ?? new();
var videoProcessingOptions = builder.Configuration.GetSection("VideoProcessing").Get<VideoProcessingOptions>() ?? new();
if (builder.Environment.IsDevelopment())
    R2OptionsLoader.LoadDevelopmentFile(r2Options, builder.Environment.ContentRootPath, builder.Configuration["Storage:R2:CredentialsFile"]);
if (jwt.SigningKey.Length < 32) throw new InvalidOperationException("Jwt__SigningKey must contain at least 32 random characters.");
if (authOptions.AccessTokenMinutes is < 1 or > 60 || authOptions.RefreshTokenDays is < 1 or > 90)
    throw new InvalidOperationException("Auth token lifetime configuration is outside its supported range.");
var requiredAuthOrigins = new[] { authOptions.WebBaseUrl, authOptions.AdminBaseUrl };
var additionalAuthOrigins = (authOptions.AllowedOrigins ?? []).Select(url => url.TrimEnd('/'))
    .Where(url => !string.IsNullOrWhiteSpace(url)).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
foreach (var url in requiredAuthOrigins)
    if (!Uri.TryCreate(url, UriKind.Absolute, out var parsed) || parsed.AbsolutePath != "/" || parsed.Query.Length > 0 || parsed.Fragment.Length > 0
        || parsed.UserInfo.Length > 0 || (builder.Environment.IsDevelopment()
            ? parsed.Scheme is not ("http" or "https")
            : parsed.Scheme != "https" && !(parsed.IsLoopback && parsed.Scheme == "http" && additionalAuthOrigins.Contains(url.TrimEnd('/'), StringComparer.OrdinalIgnoreCase))))
        throw new InvalidOperationException("Auth client URLs must be valid origins; non-HTTPS local origins must be explicitly allowlisted.");
foreach (var url in additionalAuthOrigins)
    if (!Uri.TryCreate(url, UriKind.Absolute, out var parsed) || parsed.AbsolutePath != "/" || parsed.Query.Length > 0 || parsed.Fragment.Length > 0
        || parsed.UserInfo.Length > 0 || parsed.Scheme is not ("http" or "https")
        || (!builder.Environment.IsDevelopment() && parsed.Scheme == "http" && !parsed.IsLoopback))
        throw new InvalidOperationException("Auth client URLs must be valid origins; non-HTTPS local origins must be explicitly allowlisted.");
if (emailOptions.Mode is not ("Pickup" or "Smtp" or "GmailApi") || (!builder.Environment.IsDevelopment() && emailOptions.Mode == "Pickup"))
    throw new InvalidOperationException("Email pickup is Development-only. Configure SMTP or Gmail API for Staging/Production.");
if (emailOptions.Mode == "Smtp" && string.IsNullOrWhiteSpace(emailOptions.Host)) throw new InvalidOperationException("Email__Host is required for SMTP.");
if (emailOptions.Mode == "GmailApi" && (string.IsNullOrWhiteSpace(emailOptions.From)
    || string.IsNullOrWhiteSpace(emailOptions.Gmail.ClientId)
    || string.IsNullOrWhiteSpace(emailOptions.Gmail.ClientSecret)
    || string.IsNullOrWhiteSpace(emailOptions.Gmail.RefreshToken)))
    throw new InvalidOperationException("Email__From and Email__Gmail__ClientId/ClientSecret/RefreshToken are required for Gmail API.");

builder.Services.AddSingleton(jwt); builder.Services.AddSingleton(authOptions); builder.Services.AddSingleton(googleOptions); builder.Services.AddSingleton(emailOptions); builder.Services.AddSingleton(storageOptions); builder.Services.AddSingleton(r2Options); builder.Services.AddSingleton(featureOptions); builder.Services.AddSingleton(videoProcessingOptions);
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.Configure<FormOptions>(options => options.MultipartBodyLengthLimit = 256L * 1024 * 1024 * 1024);
builder.Services.AddDbContext<HuTubeDbContext>(options => options.UseNpgsql(connection));
builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<IAuthStore, AuthStore>(); builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<HuTube.Application.Channels.IChannelStore, ChannelStore>();
builder.Services.AddScoped<HuTube.Application.Channels.ChannelService>();
builder.Services.AddScoped<HuTube.Application.Rbac.IRbacStore, RbacStore>();
builder.Services.AddScoped<HuTube.Application.Rbac.RbacService>();
builder.Services.AddSingleton<IPasswordService, PasswordService>(); builder.Services.AddSingleton<ITokenService, TokenService>();
builder.Services.AddSingleton<IGoogleTokenVerifier, GoogleTokenVerifier>();
var hasCloudinaryCredentials = !string.IsNullOrWhiteSpace(storageOptions.CloudName)
    && !string.IsNullOrWhiteSpace(storageOptions.ApiKey)
    && !string.IsNullOrWhiteSpace(storageOptions.ApiSecret);
var hasR2Credentials = !string.IsNullOrWhiteSpace(r2Options.AccountId)
    && !string.IsNullOrWhiteSpace(r2Options.AccessKeyId)
    && !string.IsNullOrWhiteSpace(r2Options.SecretAccessKey)
    && !string.IsNullOrWhiteSpace(r2Options.BucketName);
if (!hasCloudinaryCredentials && !builder.Environment.IsDevelopment())
    throw new InvalidOperationException("Cloudinary storage is required outside Development. Configure Storage__CloudName, Storage__ApiKey and Storage__ApiSecret for images.");
if (!hasR2Credentials && !builder.Environment.IsDevelopment())
    throw new InvalidOperationException("Cloudflare R2 storage is required outside Development. Configure Storage__R2__AccountId, AccessKeyId, SecretAccessKey and BucketName for videos.");
if (hasCloudinaryCredentials) builder.Services.AddSingleton<CloudinaryStorageService>();
else builder.Services.AddSingleton<LocalStorageService>();
if (hasR2Credentials) builder.Services.AddSingleton<R2ObjectStorageService>();
else builder.Services.AddSingleton<LocalStorageService>();
builder.Services.AddSingleton<IObjectStorage>(services => new DualObjectStorageService(
    hasCloudinaryCredentials ? services.GetRequiredService<CloudinaryStorageService>() : services.GetRequiredService<LocalStorageService>(),
    hasR2Credentials ? services.GetRequiredService<R2ObjectStorageService>() : services.GetRequiredService<LocalStorageService>()));
builder.Services.AddScoped<IAccountService, AccountService>();
builder.Services.AddScoped<IContentService, ContentService>();
builder.Services.AddScoped<ICfSeederService, CfSeederService>();
builder.Services.AddSingleton<VideoRenditionProcessingQueue>();
builder.Services.AddScoped<VideoRenditionProcessor>();
builder.Services.AddHostedService<VideoRenditionProcessingWorker>();
builder.Services.AddSingleton<CfSeedChunkUploadStore>();
builder.Services.AddScoped<IPlanService, PlanService>();
 builder.Services.AddScoped<IPlaylistService, PlaylistService>();
builder.Services.AddScoped<PolicyService>();
builder.Services.AddScoped<ModerationService>();
builder.Services.AddScoped<TaxonomyService>();
builder.Services.AddScoped<AdminUserService>();
builder.Services.AddScoped<INotificationService, NotificationService>();
builder.Services.AddSingleton<IVideoTranscoder, FfmpegVideoTranscoder>();
builder.Services.AddSingleton<Microsoft.AspNetCore.SignalR.IUserIdProvider, NotificationUserIdProvider>();
builder.Services.AddSignalR();
builder.Services.AddHttpClient();
builder.Services.AddSingleton<IAuthEmailSender, AuthEmailSender>();
builder.Services.AddControllers().ConfigureApiBehaviorOptions(options => options.InvalidModelStateResponseFactory = context => {
    var problem = ApiErrors.Create(context.HttpContext, 400, "VALIDATION_ERROR", "Vui lòng kiểm tra các trường dữ liệu.");
    problem.Extensions["errors"] = context.ModelState.Where(x => x.Value?.Errors.Count > 0).ToDictionary(x => x.Key, x => x.Value!.Errors.Select(_ => "Giá trị không hợp lệ.").ToArray());
    var result = new BadRequestObjectResult(problem); result.ContentTypes.Add("application/problem+json"); return result;
});
builder.Services.AddOpenApi();
var corsOrigins = requiredAuthOrigins.Concat(additionalAuthOrigins).Select(url => url.TrimEnd('/'))
    .Where(s => !string.IsNullOrWhiteSpace(s)).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
builder.Services.AddCors(options => options.AddDefaultPolicy(policy => policy.WithOrigins(corsOrigins)
    .WithMethods("GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS")
    .WithHeaders("Accept", "Content-Type", "Authorization", "Idempotency-Key", "X-Requested-With", "X-SignalR-User-Agent", "X-HuTube-Client", "X-HuTube-App")
    .AllowCredentials()));
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options => {
    options.MapInboundClaims = false;
    options.TokenValidationParameters = new() {
        ValidateIssuer = true, ValidIssuer = jwt.Issuer, ValidateAudience = true, ValidAudience = jwt.Audience,
        ValidateIssuerSigningKey = true, IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.SigningKey)),
        ValidateLifetime = true, ClockSkew = TimeSpan.Zero, ValidAlgorithms = [SecurityAlgorithms.HmacSha256]
    };
    options.Events = new() {
        OnMessageReceived = context => {
            var token = context.Request.Query["access_token"];
            if (!string.IsNullOrEmpty(token) && context.HttpContext.Request.Path.StartsWithSegments("/hubs/notifications")) context.Token = token;
            return Task.CompletedTask;
        },
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
app.Use(async (context, next) => {
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    context.Response.Headers["X-Request-ID"] = context.TraceIdentifier;
    await next(context);
});
if (!app.Environment.IsDevelopment()) app.UseHsts();
app.UseCors();
var uploadsPath = Path.Combine(builder.Environment.ContentRootPath, "uploads");
Directory.CreateDirectory(uploadsPath);
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new PhysicalFileProvider(uploadsPath),
    RequestPath = "/uploads"
});
app.UseMiddleware<ExceptionMiddleware>();
app.UseRateLimiter(); app.UseAuthentication(); app.UseAuthorization();
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
app.MapHub<NotificationHub>("/hubs/notifications");
app.Run();
public partial class Program { }
