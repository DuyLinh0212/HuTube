using System.Net;
using System.Security.Cryptography;
using System.Text;
using HuTube.Infrastructure.Recommendations;

namespace HuTube.Api.Middleware;

public sealed class RecommendationProxyMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context, RecommendationOptions options)
    {
        var originalAddress = context.Connection.RemoteIpAddress;
        var path = context.Request.Path;
        // Only the model service may forward the client address for its two data calls.
        // This preserves per-client feed limits and the session's actual IP address.
        if ((path.Equals("/api/v1/feed/recommendation-context", StringComparison.OrdinalIgnoreCase)
                || path.Equals("/api/v1/feed/resolve", StringComparison.OrdinalIgnoreCase))
            && !string.IsNullOrWhiteSpace(options.ServiceToken)
            && CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(options.ServiceToken),
                Encoding.UTF8.GetBytes(context.Request.Headers["X-Service-Token"].ToString()))
            && IPAddress.TryParse(context.Request.Headers["X-Recommendation-Client-IP"].ToString(), out var clientAddress))
        {
            context.Connection.RemoteIpAddress = clientAddress;
        }
        try { await next(context); }
        finally { context.Connection.RemoteIpAddress = originalAddress; }
    }
}
