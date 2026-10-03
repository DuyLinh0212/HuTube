using Npgsql;

namespace HuTube.Infrastructure.Persistence;

public static class DatabaseResilience
{
    private static readonly TimeSpan[] RetryDelays = [TimeSpan.FromMilliseconds(250), TimeSpan.FromMilliseconds(750)];

    public static bool IsTransientFailure(Exception exception)
    {
        for (Exception? current = exception; current is not null; current = current.InnerException)
            if (current is TimeoutException || current is NpgsqlException { IsTransient: true })
                return true;

        return false;
    }

    public static async Task<T> ExecuteWithRetryAsync<T>(Func<Task<T>> operation, CancellationToken cancellationToken)
    {
        for (var attempt = 0; ; attempt++)
        {
            try
            {
                return await operation();
            }
            catch (Exception exception) when (attempt < RetryDelays.Length
                && IsTransientFailure(exception)
                && !cancellationToken.IsCancellationRequested)
            {
                await Task.Delay(RetryDelays[attempt], cancellationToken);
            }
        }
    }
}
