using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace HuTube.Infrastructure.Operations;

public sealed class DatabaseBackupWorker(
    IServiceScopeFactory scopes,
    ILogger<DatabaseBackupWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try { await RunWithLeadershipAsync(stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { return; }
            catch (Exception ex) { logger.LogWarning(ex, "Database backup worker lost its database connection; reconnecting."); }
            if (!stoppingToken.IsCancellationRequested)
                await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
        }
    }

    private async Task RunWithLeadershipAsync(CancellationToken stoppingToken)
    {
        // A PostgreSQL session lock keeps only one API instance responsible for schedules and jobs.
        await using var lockScope = scopes.CreateAsyncScope();
        var lockDb = lockScope.ServiceProvider.GetRequiredService<HuTubeDbContext>();
        await lockDb.Database.OpenConnectionAsync(stoppingToken);
        await using var claim = lockDb.Database.GetDbConnection().CreateCommand();
        claim.CommandText = "SELECT pg_try_advisory_lock(hashtextextended('hutube:database-backup-worker', 0))";
        while (!(bool)(await claim.ExecuteScalarAsync(stoppingToken))!)
            await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);

        using var lease = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
        var monitor = MonitorLockAsync(lockDb, lease);
        var workerToken = lease.Token;
        try
        {
            await using (var scope = scopes.CreateAsyncScope())
                await scope.ServiceProvider.GetRequiredService<AdminDatabaseBackupService>()
                    .RecoverInterruptedRunsAsync(workerToken);

            while (!workerToken.IsCancellationRequested)
            {
                var processed = false;
                try
                {
                    await using var scope = scopes.CreateAsyncScope();
                    var backups = scope.ServiceProvider.GetRequiredService<AdminDatabaseBackupService>();
                    await backups.QueueDueScheduleAsync(workerToken);
                    processed = await backups.ProcessNextQueuedRunAsync(workerToken);
                }
                catch (OperationCanceledException) when (workerToken.IsCancellationRequested) { break; }
                catch (Exception ex) { logger.LogError(ex, "Database backup job polling failed."); }

                if (!processed) await Task.Delay(TimeSpan.FromSeconds(4), workerToken);
            }
        }
        finally
        {
            await lease.CancelAsync();
            await monitor;
            try
            {
                await using var release = lockDb.Database.GetDbConnection().CreateCommand();
                release.CommandText = "SELECT pg_advisory_unlock(hashtextextended('hutube:database-backup-worker', 0))";
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
                await Task.Delay(TimeSpan.FromSeconds(5), lease.Token);
                await using var ping = db.Database.GetDbConnection().CreateCommand();
                ping.CommandText = "SELECT 1";
                await ping.ExecuteScalarAsync(lease.Token);
            }
        }
        catch (OperationCanceledException) when (lease.IsCancellationRequested) { }
        catch { await lease.CancelAsync(); }
    }
}
