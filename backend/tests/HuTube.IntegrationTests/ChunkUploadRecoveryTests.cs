using HuTube.Api.Services;
using HuTube.Application.Videos;
using Microsoft.AspNetCore.Http;

namespace HuTube.IntegrationTests;

public sealed class ChunkUploadRecoveryTests
{
    [Fact]
    public async Task UserUploadRestartResumesOnlyCommittedBytesAndKeepsTheOwnerBoundary()
    {
        var directory = Path.Combine(Path.GetTempPath(), "dalitu-upload-test-" + Guid.NewGuid().ToString("N"));
        var actor = Guid.NewGuid();
        var request = new VideoUploadSessionRequest(Guid.NewGuid(), Guid.NewGuid(), "video.mp4", "video/mp4",
            VideoChunkUploadStore.ChunkSize + 3L, 10, "720p");
        try
        {
            using (var first = new VideoChunkUploadStore(directory))
            {
                first.Start(actor, request);
                using var bytes = new MemoryStream(new byte[VideoChunkUploadStore.ChunkSize]);
                await first.AppendAsync(actor, request.UploadId, 0,
                    new FormFile(bytes, 0, bytes.Length, "chunk", "part"), default);
            }
            var path = Path.Combine(directory, $"{request.UploadId:N}.upload");
            using (var partial = new FileStream(path, FileMode.Append)) partial.Write([9, 9]);
            using var restarted = new VideoChunkUploadStore(directory);
            var resumed = restarted.TryResume(actor, request);
            Assert.NotNull(resumed);
            Assert.Equal(1, resumed.NextChunk);
            Assert.Equal(2, resumed.ChunkProtocol);
            Assert.Equal(404, Assert.Throws<ContentException>(() => restarted.Require(Guid.NewGuid(), request.UploadId)).Status);
            using var tail = new MemoryStream(new byte[] { 1, 2, 3 });
            Assert.Equal(2, await restarted.AppendAsync(actor, request.UploadId, 1,
                new FormFile(tail, 0, 3, "chunk", "part"), default));
            Assert.Equal(request.FileSize, new FileInfo(path).Length);
            Assert.Equal(new byte[] { 1, 2, 3 }, (await File.ReadAllBytesAsync(path)).TakeLast(3));
            await restarted.CancelAsync(actor, request.UploadId, default);
            using var afterCancel = new VideoChunkUploadStore(directory);
            Assert.Null(afterCancel.TryResume(actor, request));
        }
        finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
    }

    [Fact]
    public async Task CompletedUserUploadReceiptSurvivesRestartWithoutSourceFile()
    {
        var directory = Path.Combine(Path.GetTempPath(), "dalitu-receipt-test-" + Guid.NewGuid().ToString("N"));
        var actor = Guid.NewGuid();
        var videoId = Guid.NewGuid();
        var request = new VideoUploadSessionRequest(Guid.NewGuid(), Guid.NewGuid(), "video.mp4", "video/mp4", 3, 1, "720p");
        try
        {
            using (var first = new VideoChunkUploadStore(directory))
            {
                first.Start(actor, request);
                using var bytes = new MemoryStream(new byte[] { 1, 2, 3 });
                await first.AppendAsync(actor, request.UploadId, 0, new FormFile(bytes, 0, 3, "chunk", "part"), default);
                var session = first.Require(actor, request.UploadId);
                session.CompletedVideoId = videoId;
                first.Persist(session);
                first.RemoveSource(session);
            }
            using var restarted = new VideoChunkUploadStore(directory);
            Assert.Equal(videoId, restarted.Require(actor, request.UploadId).CompletedVideoId);
            Assert.Equal(1, restarted.TryResume(actor, request)!.NextChunk);
        }
        finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
    }

    [Fact]
    public async Task RestartResumesCommittedChunkAndTruncatesInterruptedWrite()
    {
        var directory = Path.Combine(Path.GetTempPath(), "hutube-chunk-test-" + Guid.NewGuid().ToString("N"));
        var actor = Guid.NewGuid(); var id = Guid.NewGuid();
        try
        {
            int chunkSize;
            using (var first = new CfSeedChunkUploadStore(directory))
            {
                chunkSize = first.Start(actor, id, "video.mp4", "video/mp4", CfSeedChunkUploadStore.ChunkSize + 3L, 2).ChunkSize;
                using var content = new MemoryStream(new byte[chunkSize]);
                Assert.Equal(1, await first.AppendAsync(actor, id, 0, new FormFile(content, 0, chunkSize, "chunk", "part"), default));
            }
            var file = Path.Combine(directory, id.ToString("N") + ".upload");
            using (var interrupted = new FileStream(file, FileMode.Append)) interrupted.Write([9, 9]);
            using var restarted = new CfSeedChunkUploadStore(directory);
            restarted.Start(actor, id, "video.mp4", "video/mp4", chunkSize + 3L, 2);
            using var tail = new MemoryStream(new byte[] { 1, 2, 3 });
            Assert.Equal(2, await restarted.AppendAsync(actor, id, 1, new FormFile(tail, 0, 3, "chunk", "part"), default));
            var ready = await restarted.PrepareCompletionAsync(actor, id, default);
            Assert.Equal(chunkSize + 3L, new FileInfo(ready.FilePath).Length);
            Assert.Equal(new byte[] { 1, 2, 3 }, (await File.ReadAllBytesAsync(ready.FilePath)).TakeLast(3));
            var denied = await Assert.ThrowsAsync<ContentException>(() => restarted.PrepareCompletionAsync(Guid.NewGuid(), id, default));
            Assert.Equal(404, denied.Status);
        }
        finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
    }
}
