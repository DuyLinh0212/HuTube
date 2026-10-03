using HuTube.Domain.Payments;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace HuTube.Infrastructure.Payments;

public sealed class PaymentExpirationWorker(
    IServiceScopeFactory scopeFactory,
    TimeProvider clock,
    ILogger<PaymentExpirationWorker> logger) : BackgroundService
{
    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(30);
    private const int BatchSize = 100;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await ExpirePaymentsAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception exception)
            {
                logger.LogError(exception, "Failed to expire pending payments.");
            }

            await Task.Delay(PollInterval, stoppingToken);
        }
    }

    private async Task ExpirePaymentsAsync(CancellationToken ct)
    {
        await using var scope = scopeFactory.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<HuTubeDbContext>();
        var now = clock.GetUtcNow();
        var expired = await db.Payments.AsNoTracking()
            .Where(payment => payment.Status == "pending" && payment.ExpiresAt <= now)
            .OrderBy(payment => payment.ExpiresAt)
            .Select(payment => new { payment.PaymentId, payment.UserId })
            .Take(BatchSize)
            .ToListAsync(ct);

        foreach (var candidate in expired)
        {
            await using var transaction = await db.Database.BeginTransactionAsync(ct);
            await db.Database.ExecuteSqlInterpolatedAsync(
                $"SELECT pg_advisory_xact_lock(hashtextextended({candidate.UserId.ToString()}, 0))", ct);

            var payment = await db.Payments.SingleOrDefaultAsync(item => item.PaymentId == candidate.PaymentId, ct);
            if (payment is { Status: "pending" } && payment.ExpiresAt <= now)
            {
                payment.Status = "cancelled";
                payment.UpdatedAt = now;
                await db.SaveChangesAsync(ct);
            }

            await transaction.CommitAsync(ct);
        }
    }
}
