using HuTube.Application.Auth;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Middleware;

public static class ApiErrors
{
    public static ProblemDetails Create(HttpContext context, int status, string code, string detail)
    {
        var problem = new ProblemDetails { Status = status, Title = code, Detail = detail, Type = "about:blank" };
        problem.Extensions["code"] = code; problem.Extensions["traceId"] = context.TraceIdentifier;
        return problem;
    }
    public static async Task WriteAsync(HttpContext context, int status, string code, string detail)
    {
        context.Response.StatusCode = status;
        await context.Response.WriteAsJsonAsync(Create(context, status, code, detail), options: (System.Text.Json.JsonSerializerOptions?)null,
            contentType: "application/problem+json", cancellationToken: context.RequestAborted);
    }
}
public sealed class ExceptionMiddleware(RequestDelegate next, ILogger<ExceptionMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try { await next(context); }
        catch (AuthException ex) { await ApiErrors.WriteAsync(context, ex.Status, ex.Code, ex.Message); }
        catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested) { }
        catch (Exception ex)
        {
            logger.LogError("Request {TraceId} failed with {ExceptionType}", context.TraceIdentifier, ex.GetType().Name);
            await ApiErrors.WriteAsync(context, 500, "INTERNAL_ERROR", "Đã có lỗi xảy ra. Vui lòng thử lại và cung cấp mã truy vết nếu cần hỗ trợ.");
        }
    }
}
