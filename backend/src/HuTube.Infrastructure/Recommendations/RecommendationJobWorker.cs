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
        while (!stoppingToken.IsCancellationRequested)
        {
            try { await RunWithLeadershipAsync(stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { return; }
            catch (Exception ex) { logger.LogWarning(ex, "Recommendation worker lost its database connection; reconnecting."); }
            if (!stoppingToken.IsCancellationRequested) await Task.Delay(TimeSpan.FromSeconds(2), stoppingToken);
        }
    }

    private async Task RunWithLeadershipAsync(CancellationToken stoppingToken)
    {
        // A session lock elects one worker across API instances. It is released by
        // PostgreSQL on process/connection loss, so only its new owner recovers jobs.
        await using var lockScope = scopes.CreateAsyncScope();
        var lockDb = lockScope.ServiceProvider.GetRequiredService<HuTubeDbContext>();
        await lockDb.Database.OpenConnectionAsync(stoppingToken);
        await using var claim = lockDb.Database.GetDbConnection().CreateCommand();
        claim.CommandText = "SELECT pg_try_advisory_lock(hashtextextended('hutube:recommendation-worker', 0))";
        while (!(bool)(await claim.ExecuteScalarAsync(stoppingToken))!)
            await Task.Delay(TimeSpan.FromSeconds(2), stoppingToken);
        using var lease = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
        var monitor = MonitorLockAsync(lockDb, lease);
        stoppingToken = lease.Token;
        try
        {
        await using (var scope = scopes.CreateAsyncScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<HuTubeDbContext>();
            var interrupted = await db.RecommendationJobs.Where(x => x.Status == "running").ToListAsync(stoppingToken);
            foreach (var job in interrupted)
            {
                if (job.Kind == "model_update" && job.ModelCsvKey != null && job.ModelCsvSha256 != null)
                { job.Status = "queued"; job.Step = "recovering"; job.Error = null; continue; }
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
                    var changed = await db.RecommendationJobs.Where(x => x.JobId == job.JobId && x.Status == "queued")
                        .ExecuteUpdateAsync(update => update.SetProperty(x => x.Status, "running")
                            .SetProperty(x => x.UpdatedAt, DateTimeOffset.UtcNow), stoppingToken);
                    if (changed == 0) continue;
                    await db.Entry(job).ReloadAsync(stoppingToken);
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
        finally
        {
            await lease.CancelAsync();
            await monitor;
            try
            {
                await using var release = lockDb.Database.GetDbConnection().CreateCommand();
                release.CommandText = "SELECT pg_advisory_unlock(hashtextextended('hutube:recommendation-worker', 0))";
                await release.ExecuteScalarAsync(CancellationToken.None);
            }
            finally { await lockDb.Database.CloseConnectionAsync(); }
        }
    }

    private static async Task MonitorLockAsync(HuTubeDbContext db, CancellationTokenSource lease)
    {
        try
        {
            while (!lease.IsCancellationRequested)
            {
                await Task.Delay(TimeSpan.FromSeconds(2), lease.Token);
                await using var ping = db.Database.GetDbConnection().CreateCommand();
                ping.CommandText = "SELECT 1";
                await ping.ExecuteScalarAsync(lease.Token);
            }
        }
        catch (OperationCanceledException) when (lease.IsCancellationRequested) { }
        catch { await lease.CancelAsync(); }
    }
}
