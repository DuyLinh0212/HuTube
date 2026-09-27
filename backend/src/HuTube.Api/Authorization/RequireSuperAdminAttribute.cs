using HuTube.Api.Middleware;
using HuTube.Domain.Rbac;
using HuTube.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Api.Authorization;

[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
public sealed class RequireSuperAdminAttribute : Attribute, IAsyncActionFilter
{
    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var http = context.HttpContext;
        if (!Guid.TryParse(http.User.FindFirst("sub")?.Value, out var userId))
        {
            await ApiErrors.WriteAsync(http, 401, "SESSION_EXPIRED", "Vui lòng đăng nhập.");
            return;
        }
        var db = http.RequestServices.GetRequiredService<HuTubeDbContext>();
        var allowed = await (from user in db.Users.AsNoTracking()
                             join role in db.Roles.AsNoTracking() on user.RoleId equals role.RoleId
                             where user.UserId == userId && user.Status == "active"
                                 && user.RoleId == SystemRoles.SuperAdmin && role.Status == "active"
                             select user.UserId).AnyAsync(http.RequestAborted);
        if (!allowed)
        {
            await ApiErrors.WriteAsync(http, 403, "SUPER_ADMIN_REQUIRED", "Chỉ Super Admin được quản trị thuật toán đề xuất.");
            return;
        }
        await next();
    }
}
