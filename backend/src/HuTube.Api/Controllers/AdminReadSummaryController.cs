using HuTube.Api.Authorization;
using HuTube.Domain.Rbac;
using HuTube.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Api.Controllers;

[ApiController, Authorize, Route("api/v1/admin/channels")]
public sealed class AdminReadSummaryController(HuTubeDbContext db) : ControllerBase
{
    [HttpGet("counts"), RequirePermission(AdminPermissions.ChannelView)]
    public async Task<object> CountsAsync(CancellationToken ct)
    {
        var counts = await db.Channels.IgnoreQueryFilters().AsNoTracking()
            .GroupBy(x => x.Status).Select(group => new { Status = group.Key, Count = group.Count() }).ToListAsync(ct);
        return new { all = counts.Sum(x => x.Count), active = counts.Where(x => x.Status == "active").Sum(x => x.Count),
            restricted = counts.Where(x => x.Status == "suspended").Sum(x => x.Count),
            banned = counts.Where(x => x.Status == "banned").Sum(x => x.Count) };
    }
}
