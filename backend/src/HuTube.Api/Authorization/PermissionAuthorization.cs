using HuTube.Api.Middleware;
using HuTube.Application.Auth;
using HuTube.Application.Rbac;
using Microsoft.AspNetCore.Mvc.Filters;

namespace HuTube.Api.Authorization;

[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false, Inherited = true)]
public sealed class RequirePermissionAttribute(string permission) : Attribute, IAsyncActionFilter
{
    public string Permission { get; } = permission;

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

        var hasPermission = await rbacService.HasPermissionAsync(userId, Permission, httpContext.RequestAborted);
        var roleCode = (await rbacService.GetAdminMeAsync(userId, httpContext.RequestAborted)).Role;
        if (!hasPermission && Permission.StartsWith("plan.", StringComparison.OrdinalIgnoreCase)
            && (string.Equals(roleCode, "admin", StringComparison.OrdinalIgnoreCase)
                || string.Equals(roleCode, "super_admin", StringComparison.OrdinalIgnoreCase)
                || dbUser.RoleId == HuTube.Domain.Rbac.SystemRoles.Admin
                || dbUser.RoleId == HuTube.Domain.Rbac.SystemRoles.SuperAdmin))
            hasPermission = true;
        if (!hasPermission)
        {
            await rbacService.LogAuditAsync(new AuditLogEntry(
                userId,
                "security.permission_denied",
                "permission",
                null,
                $"Access denied for permission '{Permission}'",
                IpAddress: httpContext.Connection.RemoteIpAddress?.ToString(),
                UserAgent: httpContext.Request.Headers.UserAgent.ToString()), httpContext.RequestAborted);

            await ApiErrors.WriteAsync(httpContext, 403, "PERMISSION_DENIED", $"Bạn không có quyền '{Permission}' để thực hiện thao tác này.");
            return;
        }

        await next();
    }
}
