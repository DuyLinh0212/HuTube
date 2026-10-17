using System.Net;
using HuTube.Api.Middleware;
using HuTube.Infrastructure.Recommendations;
using Microsoft.AspNetCore.Http;

namespace HuTube.IntegrationTests;

public sealed class RecommendationProxyMiddlewareTests
{
    [Theory]
    [InlineData("/api/v1/feed/recommendation-context", "secret", "203.0.113.10")]
    [InlineData("/api/v1/feed/resolve", "secret", "203.0.113.10")]
    [InlineData("/api/v1/feed/resolve", "wrong", "127.0.0.1")]
    [InlineData("/api/v1/feed/home", "secret", "127.0.0.1")]
    public async Task OnlyTrustedModelDataCallsPreserveClientIp(string path, string token, string expected)
    {
        var context = new DefaultHttpContext();
        context.Connection.RemoteIpAddress = IPAddress.Loopback;
        context.Request.Path = path;
        context.Request.Headers["X-Service-Token"] = token;
        context.Request.Headers["X-Recommendation-Client-IP"] = "203.0.113.10";
        var middleware = new RecommendationProxyMiddleware(request => {
            Assert.Equal(expected, request.Connection.RemoteIpAddress!.ToString());
            return Task.CompletedTask;
        });
        await middleware.InvokeAsync(context, new RecommendationOptions { ServiceToken = "secret" });
        Assert.Equal(IPAddress.Loopback, context.Connection.RemoteIpAddress);
    }
}
