using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace HuTube.Infrastructure.Recommendations;

public sealed class RecommendationJobWorker(IServiceScopeFactory scopes,
    ILogger<RecommendationJobWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await using (var scope = scopes.CreateAsyncScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<HuTubeDbContext>();
            var interrupted = await db.RecommendationJobs.Where(x => x.Status == "running").ToListAsync(stoppingToken);
            foreach (var job in interrupted)
            {
                job.Status = "failed"; job.Step = "interrupted";
                job.Error = "Tiến trình bị dừng trước khi job hoàn thành. Có thể chạy lại.";
                job.UpdatedAt = DateTimeOffset.UtcNow;
            }
            await db.SaveChangesAsync(stoppingToken);
        }
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await using var scope = scopes.CreateAsyncScope();
                var db = scope.ServiceProvider.GetRequiredService<HuTubeDbContext>();
                var cancelled = await db.RecommendationJobs.Where(x => x.Status == "cancelling").ToListAsync(stoppingToken);
                foreach (var item in cancelled) { item.Status = "cancelled"; item.Step = "cancelled"; }
                await db.SaveChangesAsync(stoppingToken);
                var job = await db.RecommendationJobs.Where(x => x.Status == "queued")
                    .OrderBy(x => x.CreatedAt).FirstOrDefaultAsync(stoppingToken);
                if (job != null)
                {
                    job.Status = "running"; job.UpdatedAt = DateTimeOffset.UtcNow;
                    await db.SaveChangesAsync(stoppingToken);
                    await scope.ServiceProvider.GetRequiredService<RecommendationAdminService>()
                        .ProcessAsync(job, stoppingToken);
                    continue;
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception ex) { logger.LogError(ex, "Recommendation job polling failed."); }
            await Task.Delay(TimeSpan.FromSeconds(2), stoppingToken);
        }
    }
}
