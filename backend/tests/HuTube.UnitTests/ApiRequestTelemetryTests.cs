using HuTube.Infrastructure.Operations;

namespace HuTube.UnitTests;

public sealed class ApiRequestTelemetryTests
{
    [Fact]
    public void SnapshotAggregatesObservedApiRequestsAndHourlyTraffic()
    {
        var telemetry = new ApiRequestTelemetry();
        var now = DateTimeOffset.UtcNow;

        telemetry.Record(now, 200, 10);
        telemetry.Record(now, 429, 50);
        telemetry.Record(now, 503, 200);

        var snapshot = telemetry.Snapshot(now.AddSeconds(1));

        Assert.Equal(3, snapshot.RequestsThisMinute);
        Assert.Equal(3, snapshot.RequestsLast15Minutes);
        Assert.Equal(1, snapshot.ClientErrorsLast15Minutes);
        Assert.Equal(1, snapshot.ServerErrorsLast15Minutes);
        Assert.Equal(1, snapshot.RateLimitedLast15Minutes);
        Assert.Equal(100d / 3, snapshot.ClientErrorRateLast15Minutes, 5);
        Assert.Equal(100d / 3, snapshot.ServerErrorRateLast15Minutes, 5);
        Assert.Equal(260d / 3, snapshot.AverageLatencyMsLast15Minutes!.Value, 5);
        Assert.Equal(250d, snapshot.P95LatencyMsLast15Minutes!.Value);

        var currentHour = snapshot.Hourly.Single(bucket => now >= bucket.BucketStart && now < bucket.BucketStart.AddHours(1));
        Assert.True(currentHour.IsObserved);
        Assert.Equal(3, currentHour.Requests);
        Assert.Equal(1, currentHour.ClientErrors);
        Assert.Equal(1, currentHour.ServerErrors);
        Assert.Contains(snapshot.Hourly, bucket => !bucket.IsObserved);
    }

    [Fact]
    public void SnapshotLeavesLatencyUnavailableWhenNoRequestsWereObserved()
    {
        var telemetry = new ApiRequestTelemetry();

        var snapshot = telemetry.Snapshot(DateTimeOffset.UtcNow);

        Assert.Equal(0, snapshot.RequestsLast15Minutes);
        Assert.Null(snapshot.AverageLatencyMsLast15Minutes);
        Assert.Null(snapshot.P95LatencyMsLast15Minutes);
    }
}
