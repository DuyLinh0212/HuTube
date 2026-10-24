using System.Reflection;
using System.Security.Claims;
using HuTube.Api.Controllers;
using HuTube.Api.Services;
using HuTube.Application.Videos;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;

namespace HuTube.IntegrationTests;

public sealed class VideoUploadCompletionTests
{
    [Fact]
    public async Task CompletionReturnsBeforeProcessingAndSurvivesTheRequestDisconnecting()
    {
        await using var upload = await Upload.CreateAsync();
        var started = new TaskCompletionSource<CancellationToken>(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var calls = 0;
        upload.Stub.OnCreate = async (command, ct) => {
            Interlocked.Increment(ref calls);
            Assert.Equal(upload.Id.ToString("D"), command.IdempotencyKey);
            Assert.Equal(3, command.Content.Length);
            started.TrySetResult(ct);
            await release.Task.WaitAsync(ct);
            return upload.Video;
        };
        using var disconnected = new CancellationTokenSource();
        var result = await upload.Controller.Complete(upload.Id, upload.Form, disconnected.Token);
        Assert.IsType<AcceptedAtActionResult>(result.Result);
        var processingToken = await started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        disconnected.Cancel();
        Assert.False(processingToken.IsCancellationRequested);
        Assert.IsType<AcceptedAtActionResult>((await upload.Controller.Complete(upload.Id, upload.Form, default)).Result);
        Assert.IsType<AcceptedResult>((await upload.Controller.Status(upload.Id, default)).Result);
        Assert.Equal(1, calls);
        release.SetResult();
        var completed = await upload.WaitForResult();
        Assert.Equal(upload.Video.VideoId, Assert.IsType<VideoResponse>(completed.Value).VideoId);
        Assert.False(File.Exists(upload.Store.Require(upload.Actor, upload.Id).FilePath));
    }

    [Fact]
    public async Task FailedCompletionCanBeRetriedWithoutUploadingTheSourceAgain()
    {
        await using var upload = await Upload.CreateAsync();
        upload.Stub.OnCreate = (_, _) => throw new ContentException(503, "STORAGE_BUSY", "Storage busy");
        await upload.Controller.Complete(upload.Id, upload.Form, default);
        var failure = await Assert.ThrowsAsync<ContentException>(() => upload.WaitForResult());
        Assert.Equal("STORAGE_BUSY", failure.Code);
        Assert.True(File.Exists(upload.Store.Require(upload.Actor, upload.Id).FilePath));
        upload.Stub.OnCreate = (_, _) => Task.FromResult(upload.Video);
        await upload.Controller.Complete(upload.Id, upload.Form, default);
        Assert.IsType<VideoResponse>((await upload.WaitForResult()).Value);
    }

    [Fact]
    public async Task LegacyClientsStillReceiveTheCompletedVideo()
    {
        await using var upload = await Upload.CreateAsync();
        upload.Controller.Request.Headers.Remove("Prefer");
        var completed = await upload.Controller.Complete(upload.Id, upload.Form, default);
        Assert.IsType<CreatedResult>(completed.Result);
    }

    [Fact]
    public async Task AnotherUserCannotReadTheUploadStatus()
    {
        await using var upload = await Upload.CreateAsync();
        upload.Controller.HttpContext.User = new ClaimsPrincipal(new ClaimsIdentity([new Claim("sub", Guid.NewGuid().ToString())]));
        var error = await Assert.ThrowsAsync<ContentException>(() => upload.Controller.Status(upload.Id, default));
        Assert.Equal(404, error.Status);
    }

    [Fact]
    public async Task ExplicitCancellationStillStopsTheBackgroundUpload()
    {
        await using var upload = await Upload.CreateAsync();
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        upload.Stub.OnCreate = async (_, ct) => {
            started.SetResult();
            await Task.Delay(Timeout.Infinite, ct);
            return upload.Video;
        };
        await upload.Controller.Complete(upload.Id, upload.Form, default);
        await started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        await upload.Controller.Cancel(upload.Id, default);
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        while (upload.Store.TryResume(upload.Actor, upload.Request) != null)
            await Task.Delay(10, deadline.Token);
    }

    private sealed class Upload : IAsyncDisposable
    {
        public readonly Guid Actor = Guid.NewGuid();
        public readonly Guid Id = Guid.NewGuid();
        public readonly VideoChunkUploadStore Store = new();
        public readonly IContentService Content = DispatchProxy.Create<IContentService, StubContent>();
        public StubContent Stub => (StubContent)Content;
        public readonly VideoResponse Video = new(Guid.NewGuid(), Guid.NewGuid(), "Channel", "channel", null,
            "Test", null, "https://video.test/source.mp4", null, 1, 3, "private", "ready", "not_submitted", null,
            false, null, DateTimeOffset.UtcNow, [], [], new(0, 0, 0, 0, null, 0, 0), null);
        public UploadVideoForm Form => new() { ChannelId = Video.ChannelId, Title = "Test", Visibility = "private" };
        public VideoUploadSessionRequest Request => new(Id, Video.ChannelId, "video.mp4", "video/mp4", 3, 1, "720p");
        public VideoUploadSessionsController Controller = null!;
        private ServiceProvider services = null!;
        private VideoUploadCompletionWorker worker = null!;

        public static async Task<Upload> CreateAsync()
        {
            var upload = new Upload();
            upload.Stub.Video = upload.Video;
            upload.Stub.OnCreate = (_, _) => Task.FromResult(upload.Video);
            upload.services = new ServiceCollection().AddSingleton(upload.Content).BuildServiceProvider();
            upload.worker = new(upload.services.GetRequiredService<IServiceScopeFactory>(), upload.Store,
                NullLogger<VideoUploadCompletionWorker>.Instance);
            await upload.worker.StartAsync(default);
            upload.Store.Start(upload.Actor, upload.Request);
            using var bytes = new MemoryStream([1, 2, 3]);
            await upload.Store.AppendAsync(upload.Actor, upload.Id, 0, new FormFile(bytes, 0, 3, "chunk", "part"), default);
            upload.Controller = new(upload.Content, upload.Store, upload.worker) {
                ControllerContext = new() { HttpContext = new DefaultHttpContext() }
            };
            upload.Controller.HttpContext.User = new ClaimsPrincipal(new ClaimsIdentity([new Claim("sub", upload.Actor.ToString())]));
            upload.Controller.Request.Headers["Prefer"] = "respond-async";
            return upload;
        }

        public async Task<OkObjectResult> WaitForResult()
        {
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            while (true)
            {
                var status = await Controller.Status(Id, deadline.Token);
                if (status.Result is OkObjectResult completed) return completed;
                await Task.Delay(10, deadline.Token);
            }
        }

        public async ValueTask DisposeAsync()
        {
            await worker.StopAsync(default);
            worker.Dispose();
            if (Store.TryResume(Actor, Request) != null) await Store.CancelAsync(Actor, Id, default);
            Store.Dispose();
            await services.DisposeAsync();
        }
    }

    public class StubContent : DispatchProxy
    {
        public VideoResponse Video = null!;
        public Func<CreateVideoCommand, CancellationToken, Task<VideoResponse>> OnCreate = null!;
        protected override object? Invoke(MethodInfo? method, object?[]? args) => method!.Name switch {
            nameof(IContentService.CreateVideoAsync) => OnCreate((CreateVideoCommand)args![1]!, (CancellationToken)args[2]!),
            nameof(IContentService.GetVideoAsync) => Task.FromResult(Video),
            _ => throw new NotSupportedException(method.Name)
        };
    }
}
