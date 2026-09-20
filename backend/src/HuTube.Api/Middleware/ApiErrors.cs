using HuTube.Application.Auth;
using Microsoft.AspNetCore.Mvc;
using HttpBadHttpRequestException = Microsoft.AspNetCore.Http.BadHttpRequestException;

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
        catch (HuTube.Application.Channels.ChannelException ex) { await ApiErrors.WriteAsync(context, ex.Status, ex.Code, ex.Message); }
        catch (HuTube.Application.Rbac.RbacException ex) { await ApiErrors.WriteAsync(context, ex.Status, ex.Code, ex.Message); }
        catch (HuTube.Application.Storage.ObjectStorageException ex) { logger.LogWarning(ex, "Object storage request failed for {TraceId}", context.TraceIdentifier); await ApiErrors.WriteAsync(context, 502, "STORAGE_UPLOAD_FAILED", ex.Message); }
        catch (HuTube.Application.Videos.ContentException ex) { await ApiErrors.WriteAsync(context, ex.Status, ex.Code, ex.Message); }
        catch (HuTube.Application.Playlists.PlaylistException ex) { await ApiErrors.WriteAsync(context, ex.Status, ex.Code, ex.Message); }
        catch (HuTube.Domain.Videos.VideoValidationException ex) { await ApiErrors.WriteAsync(context, 400, ex.Code, ex.Message); }
        catch (HttpBadHttpRequestException ex)
        {
            var status = ex.StatusCode is >= 400 and < 500 ? ex.StatusCode : StatusCodes.Status400BadRequest;
            logger.LogWarning(ex, "Request {TraceId} was rejected as malformed {Method} {Path}",
                context.TraceIdentifier, context.Request.Method, context.Request.Path);
            if (!context.Response.HasStarted && !context.RequestAborted.IsCancellationRequested)
                await ApiErrors.WriteAsync(context, status, "BAD_REQUEST", "Nội dung yêu cầu không đầy đủ hoặc không hợp lệ.");
        }
        catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested) { }
        catch (Exception ex)
        {
            logger.LogError(ex, "Request {TraceId} failed with {ExceptionType}", context.TraceIdentifier, ex.GetType().Name);
            var detail = context.RequestServices.GetRequiredService<IWebHostEnvironment>().IsDevelopment()
                ? $"{ex.GetType().Name}: {ex.Message}"
                : "Đã có lỗi xảy ra. Vui lòng thử lại và cung cấp mã truy vết nếu cần hỗ trợ.";
            await ApiErrors.WriteAsync(context, 500, "INTERNAL_ERROR", detail);
        }
    }
}
