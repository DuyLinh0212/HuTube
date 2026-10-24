using System.Net;
using HuTube.Application.Videos;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using HuTube.Infrastructure.Recommendations;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;

namespace HuTube.UnitTests;

public sealed class ModelCancellationTests
{
    private sealed class Transport(HttpStatusCode status, string body) : HttpMessageHandler, IHttpClientFactory
    {
        public int Calls { get; private set; }
        public string? Path { get; private set; }
        public HttpClient CreateClient(string name) => new(this, disposeHandler: false);
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            Calls++; Path = request.RequestUri!.AbsolutePath;
            Assert.Equal("qc-only", request.Headers.GetValues("X-Model-Admin-Token").Single());
            return Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent(body) });
        }
    }

    [Theory]
    [InlineData("queued")]
    [InlineData("cancelled")]
    [InlineData("completed")]
    [InlineData("failed")]
    public async Task QueuedCancellationAndTerminalReplayDoNotNeedModelTransport(string status)
    {
        await using var db = new HuTubeDbContext(new DbContextOptionsBuilder<HuTubeDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var job = new RecommendationJob { Kind = "model_update", Status = status };
        db.RecommendationJobs.Add(job); await db.SaveChangesAsync();
        var transport = new Transport(HttpStatusCode.ServiceUnavailable, "{}");
        var service = Service(db, transport);
        await service.StopAsync(job.JobId, default); await service.StopAsync(job.JobId, default);
        Assert.Equal(status == "queued" ? "cancelled" : status, job.Status);
        Assert.Equal(0, transport.Calls);
    }

    [Theory]
    [InlineData(200, "cancelled", "cancelled", null)]
    [InlineData(409, "publishing", "running", "MODEL_JOB_FINALIZING")]
    [InlineData(503, "running", "running", "MODEL_CANCEL_UNCONFIRMED")]
    [InlineData(200, "completed", "running", "MODEL_JOB_ALREADY_FINISHED")]
    public async Task RunningJobRequiresActualCancellationAcknowledgement(int status, string reply, string expected, string? code)
    {
        await using var db = new HuTubeDbContext(new DbContextOptionsBuilder<HuTubeDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var job = new RecommendationJob { Kind = "model_update", Status = "running", ServiceJobId = Guid.NewGuid().ToString() };
        db.RecommendationJobs.Add(job); await db.SaveChangesAsync();
        var transport = new Transport((HttpStatusCode)status, "{\"status\":\"" + reply + "\"}");
        var service = Service(db, transport);
        if (code is null) await service.StopAsync(job.JobId, default);
        else Assert.Equal(code, (await Assert.ThrowsAsync<ContentException>(() => service.StopAsync(job.JobId, default))).Code);
        Assert.Equal(expected, job.Status);
        Assert.Equal("/internal/model/jobs/" + job.ServiceJobId + "/cancel", transport.Path);
        Assert.Equal(1, transport.Calls);
    }

    private static RecommendationAdminService Service(HuTubeDbContext db, IHttpClientFactory transport) =>
        new(db, null!, transport, new RecommendationOptions { ServiceUrl = "http://qc.invalid", AdminToken = "qc-only" },
            null!, null!, null!, NullLogger<RecommendationAdminService>.Instance);
}
