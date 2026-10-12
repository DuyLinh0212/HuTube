using System.Collections.Concurrent;
using HuTube.Application.Operations;

namespace HuTube.Infrastructure.Operations;

/// <summary>
/// Keeps bounded, process-local aggregates of real API requests. These metrics
/// intentionally start when this API instance starts and are not persisted.
/// </summary>
public sealed class ApiRequestTelemetry
{
    private static readonly int[] LatencyBucketUpperBoundsMs = [1, 5, 10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 30_000];
    private const int RetainedMinutes = 24 * 60;
    private readonly ConcurrentDictionary<long, MinuteBucket> buckets = new();
    private long lastPrunedMinute = DateTimeOffset.UtcNow.ToUnixTimeSeconds() / 60;

    public DateTimeOffset CollectedSince { get; } = DateTimeOffset.UtcNow;

    public void Record(DateTimeOffset timestamp, int statusCode, double elapsedMilliseconds)
    {
        var minute = timestamp.ToUnixTimeSeconds() / 60;
        var bucket = buckets.GetOrAdd(minute, _ => new MinuteBucket(LatencyBucketUpperBoundsMs.Length + 1));
        bucket.Record(statusCode, Math.Max(0, elapsedMilliseconds));
        var lastPruned = Interlocked.Read(ref lastPrunedMinute);
        if (minute - lastPruned >= 60 && Interlocked.CompareExchange(ref lastPrunedMinute, minute, lastPruned) == lastPruned)
            Prune(minute - RetainedMinutes);
    }

    public AdminApiTrafficOverview Snapshot(DateTimeOffset now)
    {
        var currentMinute = now.ToUnixTimeSeconds() / 60;
        Prune(currentMinute - RetainedMinutes);

        var recentMinutes = buckets
            .Where(item => item.Key >= currentMinute - 14 && item.Key <= currentMinute)
            .Select(item => item.Value.Snapshot())
            .ToArray();
        var current = buckets.TryGetValue(currentMinute, out var currentBucket)
            ? currentBucket.Snapshot()
            : MinuteSnapshot.Empty(LatencyBucketUpperBoundsMs.Length + 1);
        var requests = recentMinutes.Sum(item => item.Requests);
        var clientErrors = recentMinutes.Sum(item => item.ClientErrors);
        var serverErrors = recentMinutes.Sum(item => item.ServerErrors);
        var rateLimited = recentMinutes.Sum(item => item.RateLimited);
        var latencyTotal = recentMinutes.Sum(item => item.TotalLatencyMilliseconds);
        var latencySamples = recentMinutes.Sum(item => item.Requests);
        var latencyHistogram = new long[LatencyBucketUpperBoundsMs.Length + 1];
        foreach (var sample in recentMinutes)
            for (var index = 0; index < latencyHistogram.Length; index++)
                latencyHistogram[index] += sample.LatencyHistogram[index];

        double? p95 = latencySamples == 0 ? null : Percentile95(latencyHistogram, latencySamples);
        double? average = latencySamples == 0 ? null : latencyTotal / (double)latencySamples;
        var currentHour = DateTimeOffset.FromUnixTimeSeconds(now.ToUnixTimeSeconds() / 3_600 * 3_600);
        var hourly = Enumerable.Range(0, 24).Select(offset =>
        {
            var bucketStart = currentHour.AddHours(offset - 23);
            var bucketEnd = bucketStart.AddHours(1);
            var observed = bucketEnd > CollectedSince && bucketStart <= now;
            var startMinute = bucketStart.ToUnixTimeSeconds() / 60;
            var endMinute = bucketEnd.ToUnixTimeSeconds() / 60;
            var samples = buckets.Where(item => item.Key >= startMinute && item.Key < endMinute)
                .Select(item => item.Value.Snapshot()).ToArray();
            return new AdminApiTrafficBucket(bucketStart, observed,
                observed ? samples.Sum(item => item.Requests) : null,
                observed ? samples.Sum(item => item.ClientErrors) : null,
                observed ? samples.Sum(item => item.ServerErrors) : null);
        }).ToArray();

        return new AdminApiTrafficOverview(
            CollectedSince,
            current.Requests,
            requests,
            clientErrors,
            serverErrors,
            rateLimited,
            requests == 0 ? 0 : clientErrors * 100d / requests,
            requests == 0 ? 0 : serverErrors * 100d / requests,
            average,
            p95,
            hourly);
    }

    private void Prune(long minimumMinute)
    {
        foreach (var minute in buckets.Keys)
            if (minute < minimumMinute) buckets.TryRemove(minute, out _);
    }

    private static double Percentile95(IReadOnlyList<long> histogram, long sampleCount)
    {
        var target = (long)Math.Ceiling(sampleCount * 0.95d);
        long cumulative = 0;
        for (var index = 0; index < histogram.Count; index++)
        {
            cumulative += histogram[index];
            if (cumulative >= target)
                return index < LatencyBucketUpperBoundsMs.Length ? LatencyBucketUpperBoundsMs[index] : 30_000;
        }
        return 30_000;
    }

    private sealed class MinuteBucket(int histogramSize)
    {
        private long requests;
        private long clientErrors;
        private long serverErrors;
        private long rateLimited;
        private long totalLatencyMilliseconds;
        private readonly long[] latencyHistogram = new long[histogramSize];

        public void Record(int statusCode, double elapsedMilliseconds)
        {
            Interlocked.Increment(ref requests);
            if (statusCode is >= 400 and < 500) Interlocked.Increment(ref clientErrors);
            if (statusCode >= 500) Interlocked.Increment(ref serverErrors);
            if (statusCode == 429) Interlocked.Increment(ref rateLimited);
            var elapsed = (long)Math.Round(elapsedMilliseconds);
            Interlocked.Add(ref totalLatencyMilliseconds, elapsed);
            var index = Array.FindIndex(LatencyBucketUpperBoundsMs, boundary => elapsed <= boundary);
            Interlocked.Increment(ref latencyHistogram[index < 0 ? latencyHistogram.Length - 1 : index]);
        }

        public MinuteSnapshot Snapshot()
        {
            var histogram = new long[latencyHistogram.Length];
            for (var index = 0; index < histogram.Length; index++)
                histogram[index] = Interlocked.Read(ref latencyHistogram[index]);
            return new MinuteSnapshot(
                Interlocked.Read(ref requests),
                Interlocked.Read(ref clientErrors),
                Interlocked.Read(ref serverErrors),
                Interlocked.Read(ref rateLimited),
                Interlocked.Read(ref totalLatencyMilliseconds),
                histogram);
        }
    }

    private sealed record MinuteSnapshot(
        long Requests,
        long ClientErrors,
        long ServerErrors,
        long RateLimited,
        long TotalLatencyMilliseconds,
        long[] LatencyHistogram)
    {
        public static MinuteSnapshot Empty(int histogramSize) => new(0, 0, 0, 0, 0, new long[histogramSize]);
    }
}
