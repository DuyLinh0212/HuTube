using System.Diagnostics;
using System.Text.Json;
using HuTube.Domain.Rbac;
using HuTube.Infrastructure.Persistence;

namespace HuTube.Api.Middleware;

public sealed class AdminApiAuditMiddleware(RequestDelegate next, IServiceScopeFactory scopeFactory, ILogger<AdminApiAuditMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        var path = context.Request.Path;
        if (!path.StartsWithSegments("/api/v1/admin")
            || context.User.Identity?.IsAuthenticated != true
            || path.Value?.Contains("audit-logs", StringComparison.OrdinalIgnoreCase) == true
            || !Guid.TryParse(context.User.FindFirst("sub")?.Value, out var actorUserId))
        {
            await next(context);
            return;
        }

        var method = context.Request.Method;
        var pathValue = path.Value ?? "/api/v1/admin";
        var ipAddress = context.Connection.RemoteIpAddress?.ToString();
        var userAgent = context.Request.Headers.UserAgent.ToString();
        var stopwatch = Stopwatch.StartNew();
        var failed = false;
        try
        {
            await next(context);
        }
        catch
        {
            failed = true;
            throw;
        }
        finally
        {
            stopwatch.Stop();
            var statusCode = failed && context.Response.StatusCode < 400 ? StatusCodes.Status500InternalServerError : context.Response.StatusCode;
            try
            {
                await using var scope = scopeFactory.CreateAsyncScope();
                var db = scope.ServiceProvider.GetRequiredService<HuTubeDbContext>();
                db.AuditLogs.Add(new AuditLog
                {
                    ActorUserId = actorUserId,
                    Action = "admin.api_request",
                    ResourceType = "api_endpoint",
                    Reason = $"{method} {pathValue} → {statusCode} ({stopwatch.ElapsedMilliseconds} ms)",
                    NewValues = JsonSerializer.Serialize(new { method, path = pathValue, statusCode, durationMs = stopwatch.ElapsedMilliseconds }),
                    IpAddress = ipAddress,
                    UserAgent = userAgent,
                    CreatedAt = DateTimeOffset.UtcNow
                });
                await db.SaveChangesAsync(CancellationToken.None);
            }
            catch (Exception exception)
            {
                logger.LogWarning(exception, "Could not persist admin API audit event for {Method} {Path}", method, pathValue);
            }
        }
    }
}
