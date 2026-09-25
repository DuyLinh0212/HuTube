using HuTube.Api.Middleware;
using HuTube.Application.Auth;
using HuTube.Application.Rbac;
using HuTube.Domain.Rbac;
using Microsoft.AspNetCore.Mvc.Filters;

namespace HuTube.Api.Authorization;

[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false, Inherited = true)]
public sealed class RequirePermissionAttribute : Attribute, IAsyncActionFilter
{
    public IReadOnlyList<string> Permissions { get; }
    public string Permission => Permissions.FirstOrDefault() ?? string.Empty;

    public RequirePermissionAttribute(string permission)
    {
        Permissions = [permission];
    }

    public RequirePermissionAttribute(params string[] permissions)
    {
        Permissions = permissions;
    }

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var httpContext = context.HttpContext;
        var user = httpContext.User;

        if (!(user.Identity?.IsAuthenticated ?? false))
        {
            await ApiErrors.WriteAsync(httpContext, 401, "SESSION_EXPIRED", "Phiên đã hết hạn hoặc chưa đăng nhập.");
            return;
        }

        if (!Guid.TryParse(user.FindFirst("sub")?.Value, out var userId))
        {
            await ApiErrors.WriteAsync(httpContext, 401, "SESSION_EXPIRED", "Phiên không hợp lệ.");
            return;
        }

        var authStore = httpContext.RequestServices.GetRequiredService<IAuthStore>();
        var rbacService = httpContext.RequestServices.GetRequiredService<RbacService>();

        var dbUser = await authStore.FindUserAsync(userId, httpContext.RequestAborted);
        if (dbUser == null || dbUser.IsBlocked || dbUser.Status != "active")
        {
            await ApiErrors.WriteAsync(httpContext, 403, "ACCOUNT_INACTIVE", "Tài khoản bị khóa hoặc vô hiệu hóa.");
            return;
        }

        var isAdmin = await authStore.IsAdminAsync(userId, httpContext.RequestAborted);
        if (!isAdmin)
        {
            await ApiErrors.WriteAsync(httpContext, 403, "ADMIN_ACCESS_DENIED", "Bạn không có quyền truy cập quản trị.");
            return;
        }

        var hasPermission = false;
        foreach (var p in Permissions)
        {
            if (await rbacService.HasPermissionAsync(userId, p, httpContext.RequestAborted))
            {
                hasPermission = true;
                break;
            }
        }

        if (!hasPermission)
        {
            var permLabel = string.Join("' hoặc '", Permissions);
            await rbacService.LogAuditAsync(new AuditLogEntry(
                userId,
                "security.permission_denied",
                "permission",
                null,
                $"Access denied for permission '{permLabel}'",
                IpAddress: httpContext.Connection.RemoteIpAddress?.ToString(),
                UserAgent: httpContext.Request.Headers.UserAgent.ToString()), httpContext.RequestAborted);

            await ApiErrors.WriteAsync(httpContext, 403, "PERMISSION_DENIED", $"Bạn không có quyền '{permLabel}' để thực hiện thao tác này.");
            return;
        }

        await next();
    }
}
