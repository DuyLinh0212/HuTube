using HuTube.Api.Services;
using HuTube.Application.Videos;
using Microsoft.AspNetCore.Http;

namespace HuTube.IntegrationTests;

public sealed class ChunkUploadRecoveryTests
{
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
