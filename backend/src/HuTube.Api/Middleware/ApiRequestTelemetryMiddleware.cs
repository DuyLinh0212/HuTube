using System.Diagnostics;
using HuTube.Infrastructure.Operations;

namespace HuTube.Api.Middleware;

public sealed class ApiRequestTelemetryMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context, ApiRequestTelemetry telemetry)
    {
        var path = context.Request.Path;
        var shouldRecord = path.StartsWithSegments("/api")
            && context.Request.Method != HttpMethods.Options
            && !path.StartsWithSegments("/api/v1/admin/operations/system")
            && !path.StartsWithSegments("/api/v1/system/info");
        var startedAt = Stopwatch.GetTimestamp();
        try
        {
            await next(context);
        }
        finally
        {
            if (shouldRecord)
                telemetry.Record(DateTimeOffset.UtcNow, context.Response.StatusCode,
                    Stopwatch.GetElapsedTime(startedAt).TotalMilliseconds);
        }
    }
}
