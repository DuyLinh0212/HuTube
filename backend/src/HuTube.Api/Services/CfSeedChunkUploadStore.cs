using System.Collections.Concurrent;
using HuTube.Application.CfSeeding;
using HuTube.Application.Videos;

namespace HuTube.Api.Services;

public sealed record CfSeedChunkSessionInfo(Guid UploadId, int ChunkSize);
public sealed record CfSeedChunkReady(string FilePath, string FileName, string ContentType,
    long FileSize, CfSeedVideoResponse? CompletedResponse);

public sealed class CfSeedChunkUploadStore
{
    public const int ChunkSize = 24 * 1024 * 1024;
    private const long MaximumFileSize = 256L * 1024 * 1024 * 1024;
    private static readonly TimeSpan SessionLifetime = TimeSpan.FromHours(24);
    private readonly ConcurrentDictionary<Guid, UploadSession> sessions = new();
    private readonly string root;

    public CfSeedChunkUploadStore()
    {
        root = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "hutube-cf-seeder-chunks"));
        Directory.CreateDirectory(root);
    }

    public CfSeedChunkSessionInfo Start(Guid actorId, Guid uploadId, string fileName, string contentType,
        long fileSize, int totalChunks)
    {
        CleanupExpired();
        if (fileSize is <= 0 or > MaximumFileSize)
            throw Error(400, "CF_SEED_FILE_SIZE", "Dung lượng video phải lớn hơn 0 và không vượt quá 256 GB.");
        var expectedChunks = checked((int)Math.Ceiling(fileSize / (double)ChunkSize));
        if (totalChunks != expectedChunks)
            throw Error(400, "CF_SEED_CHUNK_COUNT", "Số phần upload không khớp với dung lượng video.");
        if (uploadId == Guid.Empty) throw Error(400, "CF_SEED_UPLOAD_ID", "Mã phiên upload không hợp lệ.");
        if (sessions.TryGetValue(uploadId, out var existing))
        {
            if (existing.ActorId == actorId && existing.FileSize == fileSize
                && existing.TotalChunks == totalChunks && existing.FileName == Path.GetFileName(fileName))
                return new(uploadId, ChunkSize);
            throw Error(409, "CF_SEED_UPLOAD_ID_CONFLICT", "Mã phiên upload đã được sử dụng cho file khác.");
        }
        var path = SafePath(uploadId);
        var created = new UploadSession(actorId, path, Path.GetFileName(fileName), contentType,
            fileSize, totalChunks, DateTimeOffset.UtcNow);
        if (!sessions.TryAdd(uploadId, created))
            throw Error(409, "CF_SEED_UPLOAD_ID_CONFLICT", "Mã phiên upload vừa được sử dụng.");
        try { using (File.Create(path)) { } }
        catch
        {
            sessions.TryRemove(uploadId, out _);
            throw;
        }
        return new(uploadId, ChunkSize);
    }

    public async Task<int> AppendAsync(Guid actorId, Guid uploadId, int chunkIndex, IFormFile chunk,
        CancellationToken ct)
    {
        var session = Require(actorId, uploadId);
        await session.Gate.WaitAsync(ct);
        try
        {
            if (session.CompletedResponse != null) return session.NextChunk;
            if (session.Processing) throw Error(409, "CF_SEED_UPLOAD_PROCESSING", "Video đang được hoàn tất.");
            if (chunkIndex < 0 || chunkIndex >= session.TotalChunks)
                throw Error(400, "CF_SEED_CHUNK_INDEX", "Số thứ tự phần upload không hợp lệ.");
            if (chunkIndex < session.NextChunk) return session.NextChunk;
            if (chunkIndex != session.NextChunk)
                throw Error(409, "CF_SEED_CHUNK_ORDER", $"Hệ thống đang chờ phần {session.NextChunk}, không phải phần {chunkIndex}.");
            var expectedLength = chunkIndex == session.TotalChunks - 1
                ? session.FileSize - (long)ChunkSize * chunkIndex
                : ChunkSize;
            if (chunk.Length != expectedLength)
                throw Error(400, "CF_SEED_CHUNK_SIZE", $"Phần {chunkIndex} phải có đúng {expectedLength} byte.");

            await using var output = new FileStream(session.FilePath, FileMode.Open, FileAccess.Write,
                FileShare.None, 128 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan);
            var offset = (long)ChunkSize * chunkIndex;
            output.SetLength(offset); // Remove a partial write left by an interrupted attempt.
            output.Position = offset;
            await using var input = chunk.OpenReadStream();
            await input.CopyToAsync(output, ct);
            session.NextChunk++;
            session.LastTouchedAt = DateTimeOffset.UtcNow;
            return session.NextChunk;
        }
        finally { session.Gate.Release(); }
    }

    public async Task<CfSeedChunkReady> PrepareCompletionAsync(Guid actorId, Guid uploadId, CancellationToken ct)
    {
        var session = Require(actorId, uploadId);
        await session.Gate.WaitAsync(ct);
        try
        {
            if (session.CompletedResponse != null)
                return new(session.FilePath, session.FileName, session.ContentType, session.FileSize, session.CompletedResponse);
            if (session.Processing) throw Error(409, "CF_SEED_UPLOAD_PROCESSING", "Video đang được hoàn tất.");
            if (session.NextChunk != session.TotalChunks)
                throw Error(409, "CF_SEED_UPLOAD_INCOMPLETE", $"Mới nhận {session.NextChunk}/{session.TotalChunks} phần video.");
            if (!File.Exists(session.FilePath) || new FileInfo(session.FilePath).Length != session.FileSize)
                throw Error(409, "CF_SEED_UPLOAD_CORRUPTED", "File tạm không đủ dung lượng; hãy upload lại video.");
            session.Processing = true;
            session.LastTouchedAt = DateTimeOffset.UtcNow;
            return new(session.FilePath, session.FileName, session.ContentType, session.FileSize, null);
        }
        finally { session.Gate.Release(); }
    }

    public async Task MarkCompletedAsync(Guid actorId, Guid uploadId, CfSeedVideoResponse response, CancellationToken ct)
    {
        var session = Require(actorId, uploadId);
        await session.Gate.WaitAsync(ct);
        try
        {
            session.CompletedResponse = response;
            session.Processing = false;
            session.LastTouchedAt = DateTimeOffset.UtcNow;
            DeleteSafe(session.FilePath);
        }
        finally { session.Gate.Release(); }
    }

    public async Task ReleaseForRetryAsync(Guid actorId, Guid uploadId)
    {
        if (!sessions.TryGetValue(uploadId, out var session) || session.ActorId != actorId) return;
        await session.Gate.WaitAsync();
        try { session.Processing = false; session.LastTouchedAt = DateTimeOffset.UtcNow; }
        finally { session.Gate.Release(); }
    }

    private UploadSession Require(Guid actorId, Guid uploadId)
    {
        if (!sessions.TryGetValue(uploadId, out var session) || session.ActorId != actorId)
            throw Error(404, "CF_SEED_UPLOAD_NOT_FOUND", "Không tìm thấy phiên upload hoặc phiên đã hết hạn.");
        return session;
    }

    private void CleanupExpired()
    {
        var cutoff = DateTimeOffset.UtcNow - SessionLifetime;
        foreach (var pair in sessions.Where(x => x.Value.LastTouchedAt < cutoff && !x.Value.Processing))
            if (sessions.TryRemove(pair.Key, out var expired)) DeleteSafe(expired.FilePath);
    }

    private string SafePath(Guid uploadId)
    {
        var path = Path.GetFullPath(Path.Combine(root, $"{uploadId:N}.upload"));
        if (!path.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Đường dẫn file tạm không hợp lệ.");
        return path;
    }

    private void DeleteSafe(string path)
    {
        var fullPath = Path.GetFullPath(path);
        if (!fullPath.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) return;
        try { if (File.Exists(fullPath)) File.Delete(fullPath); }
        catch (IOException) { /* A later cleanup pass can remove a transiently locked file. */ }
    }

    private static ContentException Error(int status, string code, string message) => new(status, code, message);

    private sealed class UploadSession(Guid actorId, string filePath, string fileName, string contentType,
        long fileSize, int totalChunks, DateTimeOffset createdAt)
    {
        public Guid ActorId { get; } = actorId;
        public string FilePath { get; } = filePath;
        public string FileName { get; } = fileName;
        public string ContentType { get; } = contentType;
        public long FileSize { get; } = fileSize;
        public int TotalChunks { get; } = totalChunks;
        public int NextChunk { get; set; }
        public bool Processing { get; set; }
        public CfSeedVideoResponse? CompletedResponse { get; set; }
        public DateTimeOffset LastTouchedAt { get; set; } = createdAt;
        public SemaphoreSlim Gate { get; } = new(1, 1);
    }
}
